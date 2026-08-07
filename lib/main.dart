import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_config.dart';
import 'core/art_cache.dart';
import 'core/auth.dart';
import 'core/home_store.dart';
import 'core/librespot.dart';
import 'core/liked_store.dart';
import 'core/media_keys.dart';
import 'core/metadata_sidecar.dart';
import 'core/player_state.dart';
import 'core/resource_monitor.dart';
import 'core/settings.dart';
import 'core/spotify_api.dart';
import 'ui/login_screen.dart';
import 'ui/shell.dart';

/// Instancia única: la primera escucha en un puerto local; las siguientes le
/// mandan "show" para traer su ventana al frente y se cierran. Dos instancias
/// significarían dos librespot peleándose por el mismo dispositivo.
const _lockPort = 53330;

Future<bool> _acquireSingleInstance() async {
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _lockPort);
    server.listen((socket) {
      socket.drain<void>().catchError((_) {});
      windowManager.show();
      windowManager.focus();
      socket.destroy();
    });
    return true;
  } catch (_) {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, _lockPort,
          timeout: const Duration(seconds: 2));
      socket.write('show');
      await socket.flush();
      socket.destroy();
    } catch (_) {}
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!await _acquireSingleInstance()) {
    exit(0);
  }

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1000, 680),
    minimumSize: Size(820, 560),
    center: true,
    title: 'NeoFy',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Cerrar la ventana la esconde en la bandeja: la música sigue sonando.
  await windowManager.setPreventClose(true);

  final config = await AppConfig.load();
  // Podar la caché de carátulas fuera del camino crítico del arranque.
  unawaited(ArtCache.prune());

  runApp(SpotifyNativeApp(config: config));
}

class SpotifyNativeApp extends StatelessWidget {
  const SpotifyNativeApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1DB954); // verde Spotify
    return MaterialApp(
      title: 'NeoFy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: RootScreen(config: config),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.config});

  final AppConfig config;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WindowListener, TrayListener {
  late final SpotifyAuth _auth = SpotifyAuth(widget.config);
  late final SpotifyApi _api = SpotifyApi(_auth);
  late final PlayerController _player = PlayerController(_api, widget.config);
  // El estado de "me gusta" se comparte: la misma canción sale en la búsqueda,
  // en una playlist y en la cola, y el corazón tiene que estar igual en todas.
  late final LikedStore _likes =
      LikedStore(api: _api, auth: _auth, onReauth: _reauth);
  late final HomeStore _home = HomeStore(api: _api, auth: _auth);

  /// Mide los tres procesos. Los pids se piden al vuelo porque los sidecars se
  /// reinician solos y cambian de pid.
  late final ResourceMonitor _ram = ResourceMonitor(
    pidsDeSidecars: () => [_librespot.pid, _sidecar.pid],
  );

  late final Settings _settings = Settings(widget.config)
    ..onCambioDeModo = _alCambiarDeModo;
  late final LibrespotManager _librespot = LibrespotManager(widget.config);
  final MetadataSidecar _sidecar = MetadataSidecar();

  /// Teclas multimedia del sistema, incluido el botón de los cascos. Llegan
  /// aunque la ventana esté escondida en la bandeja.
  late final MediaKeys _mediaKeys = MediaKeys(
    onPlayPause: _player.togglePlay,
    onNext: _player.next,
    onPrevious: _player.previous,
    onPause: _player.pause,
  );

  bool _booting = true;
  bool _sessionStarted = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _mediaKeys.start();
    _ram.start();
    // Aplica el modo guardado: techo de la caché de bitmaps y, si toca, del
    // residente.
    _aplicarTechoDeMemoria(_settings.performanceMode);
    unawaited(_setupTray());
    unawaited(_boot());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _mediaKeys.stop();
    _player.dispose();
    _likes.dispose();
    _home.dispose();
    _ram.dispose();
    _settings.dispose();
    _librespot.dispose();
    _sidecar.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _auth.loadStored();
    if (_auth.isLoggedIn) {
      await _startSession();
    }
    if (mounted) setState(() => _booting = false);
  }

  /// Arranca todo lo que depende de tener sesión: el sidecar de audio, el
  /// sondeo del estado y la resolución de nuestro dispositivo Connect.
  Future<void> _startSession() async {
    if (_sessionStarted) return;
    _sessionStarted = true;

    // ⚠️ El audio arranca **antes** que ninguna llamada a la Web API. Tenerlo
    // al revés hacía que un `/me` lento —o un 429 con Retry-After largo— dejara
    // la app sin librespot y sin sidecar, o sea muda, sin más síntoma que un
    // silencio. Nada de lo que da `/me` hace falta para reproducir.
    await _librespot.start();

    unawaited(_cargarCuenta());
    _player.start();
    unawaited(_waitForDevice());
    unawaited(_startSidecar());
  }

  /// Una sola llamada a `/me` da las dos cosas: si la cuenta es Premium y su
  /// id, que hace falta para el contexto de "Canciones que te gustan". Va por
  /// libre: si falla o tarda, la música ya está sonando.
  Future<void> _cargarCuenta() async {
    try {
      final me = await _api.me();
      if (!mounted) return;
      _player.isPremium = (me['product'] as String?) == 'premium';
      _player.currentUserId = me['id'] as String?;
      _player.premiumChecked = true;
    } catch (_) {
      // Ya fallará más adelante con un mensaje concreto en la pantalla que lo
      // necesite; no es motivo para entorpecer el arranque.
    }
  }

  /// Encender el modo rendimiento apaga el sidecar de metadatos; apagarlo lo
  /// vuelve a levantar. El audio no se toca en ningún caso.
  void _alCambiarDeModo(bool activo) {
    _aplicarTechoDeMemoria(activo);
    if (activo) {
      unawaited(_sidecar.stop());
      // Soltar la caché no basta: hasta que Windows no recoja las páginas, la
      // memoria sigue contando como residente. Se le pide que las recoja ya.
      ResourceMonitor.vaciarWorkingSet([_librespot.pid, _sidecar.pid]);
    } else if (_sessionStarted) {
      unawaited(_startSidecar());
    }
  }

  /// El objetivo del modo rendimiento: 100 MB entre los tres procesos.
  static const _techoRendimiento = 100 << 20;

  void _aplicarTechoDeMemoria(bool activo) {
    _ram.techoBytes = activo ? _techoRendimiento : null;
    if (activo) {
      ResourceMonitor.vaciarWorkingSet([_librespot.pid, _sidecar.pid]);
    }
  }

  /// El sidecar de metadatos reutiliza las credenciales que deja librespot al
  /// iniciar sesión, así que hay que esperar a que existan. En el primer
  /// arranque eso incluye el paso por el navegador, de ahí el margen largo.
  Future<void> _startSidecar() async {
    // En modo rendimiento no se arranca: son ~13 MB y solo es el plan B para
    // leer playlists ajenas.
    if (_settings.performanceMode) return;
    for (var i = 0; i < 60; i++) {
      if (!mounted) return;
      if (_librespot.hasCredentials) {
        await _sidecar.start();
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  /// librespot tarda unos segundos en registrarse en Spotify Connect, así que
  /// se reintenta un rato antes de darlo por perdido.
  Future<void> _waitForDevice() async {
    for (var i = 0; i < 15; i++) {
      if (!mounted) return;
      if (await _player.resolveDevice()) {
        // Spotify recuerda el estado de la sesión, no el del dispositivo: si
        // la app se cerró sonando, el traspaso a librespot recién arrancado
        // reanuda la música sola. Abrir la app no debe empezar a sonar.
        await _player.ensurePausedAtStartup();
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _onLoggedIn() async {
    await _startSession();
    if (mounted) setState(() {});
  }

  /// Vuelve a pasar por el consentimiento sin cerrar sesión.
  ///
  /// Hace falta cuando la app empieza a pedir un permiso que la sesión guardada
  /// no tenía: renovar un token viejo no le añade permisos nuevos.
  Future<void> _reauth() async {
    try {
      await _auth.login();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo reautorizar: $e')));
      }
    }
  }

  // ------------------------------------------------------------------ bandeja

  Future<void> _setupTray() async {
    // La bandeja es prescindible: si falla (falta el icono, no hay área de
    // notificación), la app tiene que arrancar igual. Mismo criterio que
    // NeoDrive, donde esto ya dio problemas en Linux.
    try {
      final icon = _trayIconPath();
      if (icon != null) await trayManager.setIcon(icon);
      await trayManager.setToolTip('NeoFy');
      await _refreshTrayMenu();
    } catch (_) {}
  }

  String? _trayIconPath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    for (final c in [
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'tray.ico'),
      p.join(Directory.current.path, 'assets', 'tray.ico'),
    ]) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> _refreshTrayMenu() async {
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'playpause', label: 'Reproducir / Pausar'),
        MenuItem(key: 'next', label: 'Siguiente'),
        MenuItem(key: 'previous', label: 'Anterior'),
        MenuItem.separator(),
        MenuItem(key: 'show', label: 'Mostrar ventana'),
        MenuItem(key: 'exit', label: 'Salir'),
      ]));
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'playpause':
        unawaited(_player.togglePlay());
      case 'next':
        unawaited(_player.next());
      case 'previous':
        unawaited(_player.previous());
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'exit':
        unawaited(_quit());
    }
  }

  /// Salida ordenada: matar librespot antes de irnos, o queda un proceso
  /// huérfano sonando de fondo sin ventana que lo controle.
  Future<void> _quit() async {
    await _sidecar.stop();
    await _librespot.stop();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ------------------------------------------------------------------ ventana

  @override
  void onWindowClose() {
    // Esconder en vez de cerrar: la música no se corta al darle a la X.
    windowManager.hide();
    _alEsconderse();
  }

  @override
  void onWindowMinimize() => _alEsconderse();

  @override
  void onWindowRestore() => _player.setWindowVisible(true);

  @override
  void onWindowFocus() => _player.setWindowVisible(true);

  /// Un reproductor de música se pasa la vida escondido en la bandeja, y ahí
  /// no hay ni una imagen que mirar: los bitmaps decodificados que quedaran en
  /// la caché serían megas retenidos durante horas para nada. Se sueltan.
  ///
  /// No se pierde nada: las carátulas siguen en disco, así que al volver se
  /// vuelven a decodificar sin bajar nada de la red.
  void _alEsconderse() {
    _player.setWindowVisible(false);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    // Y que Windows se lleve las páginas que quedan sin usar: escondida en la
    // bandeja, la app no necesita tener nada residente.
    ResourceMonitor.vaciarWorkingSet([_librespot.pid, _sidecar.pid]);
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_auth.isLoggedIn) {
      return LoginScreen(
        auth: _auth,
        config: widget.config,
        onLoggedIn: _onLoggedIn,
      );
    }
    return AppShell(
      api: _api,
      auth: _auth,
      player: _player,
      likes: _likes,
      home: _home,
      ram: _ram,
      settings: _settings,
      librespot: _librespot,
      sidecar: _sidecar,
      onReauth: _reauth,
      onLogout: () async {
        await _sidecar.stop();
        await _librespot.stop();
        await _auth.logout();
        _sessionStarted = false;
        if (mounted) setState(() {});
      },
    );
  }
}
