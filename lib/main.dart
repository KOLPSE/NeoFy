import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_config.dart';
import 'core/art_cache.dart';
import 'core/audio_device.dart';
import 'core/auth.dart';
import 'core/home_store.dart';
import 'core/librespot.dart';
import 'core/liked_store.dart';
import 'core/media_keys.dart';
import 'core/metadata_sidecar.dart';
import 'core/mpris.dart';
import 'core/player_state.dart';
import 'core/resource_monitor.dart';
import 'core/settings.dart';
import 'core/spotify_api.dart';
import 'core/updater.dart';
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
  final Updater _updater = Updater();
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

  /// Cambios de la salida de audio del sistema. Ver [_reiniciarAudio].
  late final AudioDeviceWatcher _audio =
      AudioDeviceWatcher(
          onCambio: () => _reiniciarAudio(motivo: 'Windows cambió de altavoz'));

  /// Lo mismo que [_mediaKeys], pero en Linux: allí las teclas multimedia las
  /// reparte el escritorio entre los reproductores que hablan MPRIS. De regalo,
  /// NeoFy sale en el widget de reproducción del sistema con carátula.
  late final MprisService _mpris = MprisService(
    onPlayPause: _player.togglePlay,
    // ⚠️ `Play` no es `togglePlay`: MPRIS distingue las dos cosas y el
    // escritorio manda `Play` a secas cuando el usuario le da al botón de
    // reproducir. Mapearlo al toggle pausaría lo que ya está sonando.
    onPlay: _reproducirSiEstaParado,
    onPause: _player.pause,
    onNext: _player.next,
    onPrevious: _player.previous,
    onSeek: (us) => _player.seek(us ~/ 1000),
    estado: () => EstadoMpris(
      track: _player.state.track,
      sonando: _player.state.isPlaying,
      // La posición interpolada en local, que se actualiza cada 250 ms sin
      // gastar ni una petición. Ver "Sondeo: por qué es como es".
      posicionMs: _player.progressMs.value,
      puedeSaltar: _player.state.canSkipNext,
      puedeVolver: _player.state.canSkipPrevious,
      volumen: _player.state.volumePercent,
    ),
  );

  bool _booting = true;
  bool _sessionStarted = false;
  bool _reiniciandoAudio = false;
  DateTime _ultimoReinicioDeAudio = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _mediaKeys.start();
    unawaited(_mpris.start());
    // Se engancha al notificador general y no a `currentUri`: pausar no cambia
    // de canción, y con solo `currentUri` el widget del escritorio se quedaría
    // diciendo "reproduciendo" con la música parada. Que esto salte cada 3 s no
    // importa — `notificarCambio` compara una firma y no emite si no ha
    // cambiado nada.
    _player.addListener(_mpris.notificarCambio);
    // Las dos vías por las que se detecta que el audio se ha quedado mudo: que
    // Windows cambie de altavoces, y que el propio librespot se queje en su log.
    _audio.start();
    _librespot.onFalloDeAudio = (linea) =>
        unawaited(_reiniciarAudio(motivo: 'error en el log: $linea'));
    _ram.start();
    // Una comprobación al arrancar, sin molestar: si hay algo nuevo, aparece en
    // Ajustes con un punto. No se instala nada sin que el usuario lo pida.
    unawaited(_updater.buscar());
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
    _player.removeListener(_mpris.notificarCambio);
    unawaited(_mpris.stop());
    _audio.stop();
    _player.dispose();
    _likes.dispose();
    _home.dispose();
    _ram.dispose();
    _settings.dispose();
    _updater.dispose();
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

  /// Vuelve a abrir la salida de audio y deja la música donde estaba.
  ///
  /// **El fallo que arregla:** librespot elige el dispositivo de salida al
  /// arrancar y no lo suelta. Si cambia el de por defecto —unos cascos, un
  /// televisor, la salida del monitor— o el que tenía deja de funcionar, se
  /// queda escribiendo audio en el vacío: el proceso sigue vivo, Spotify sigue
  /// diciendo que la canción avanza y no suena nada. Como no se cae, el
  /// reinicio automático de [LibrespotManager] no entra, y la única salida era
  /// cerrar la app entera y volver a abrirla.
  ///
  /// Reiniciar el sidecar corta el sonido un par de segundos, así que no se
  /// hace a la ligera: solo con un aviso del sistema, con un error del backend
  /// de audio en el log, o porque lo pida el usuario desde Ajustes.
  Future<void> _reiniciarAudio({bool porElUsuario = false, String motivo = '?'}) async {
    if (!_sessionStarted || _reiniciandoAudio) return;
    // Reiniciar corta el sonido un par de segundos y se ve igual que una pausa,
    // así que queda dicho quién lo pidió: si alguien reporta que la música se
    // para sola, esta línea distingue un reinicio de audio de una pausa de
    // verdad, que son problemas completamente distintos.
    debugPrint('Reiniciando el audio (motivo: $motivo)');
    // Un cambio de salida llega en ráfaga de avisos y un fallo de audio, en
    // ráfaga de líneas de log. Sin esta ventana, la app se pasaría el rato
    // reiniciando el sidecar y cortando la misma música que intenta salvar.
    // Quien le da al botón sí manda: ese ya sabe lo que está pidiendo.
    final desde = DateTime.now().difference(_ultimoReinicioDeAudio);
    if (!porElUsuario && desde < const Duration(seconds: 20)) return;

    _reiniciandoAudio = true;
    _ultimoReinicioDeAudio = DateTime.now();
    try {
      final antes = _player.instantanea();
      final viejo = _player.olvidarDispositivo();
      await _librespot.reiniciar();

      // librespot tarda unos segundos en volver a registrarse en Spotify
      // Connect, y lo hace con un device_id nuevo. Durante ese rato la API
      // sigue listando el del proceso que acabamos de matar, de ahí el filtro.
      for (var i = 0; i < 20; i++) {
        if (!mounted) return;
        if (await _player.resolveDevice(transfer: false, distintoDe: viejo)) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      // Si el id no cambió (no debería, pero tampoco lo promete nadie), mejor
      // quedarse con el que haya que no quedarse sin dispositivo.
      if (_player.ourDeviceId == null) {
        await _player.resolveDevice(transfer: false);
      }
      if (!mounted) return;
      await _player.retomar(antes);
    } finally {
      _reiniciandoAudio = false;
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

  Future<void> _reproducirSiEstaParado() async {
    if (_player.state.isPlaying) return;
    await _player.togglePlay();
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

  /// ¿Se pudo montar el icono de la bandeja?
  ///
  /// ⚠️ **De esto depende que la X cierre o esconda**, así que no vale con
  /// tragarse el fallo. En Windows la bandeja no falla nunca, pero en Linux
  /// `tray_manager` necesita `libayatana-appindicator` y **en GNOME sin la
  /// extensión de AppIndicator no aparece nada**. Con la app escondiéndose
  /// igualmente al cerrar, el usuario se queda sin ventana y sin icono al que
  /// volver: la única salida sería matar el proceso.
  bool _bandejaDisponible = false;

  Future<void> _setupTray() async {
    // La bandeja es prescindible: si falla (falta el icono, no hay área de
    // notificación), la app tiene que arrancar igual. Mismo criterio que
    // NeoDrive, donde esto ya dio problemas en Linux.
    try {
      final icon = _trayIconPath();
      if (icon == null) {
        debugPrint('Bandeja: no se encuentra el icono; la X cerrará la app.');
        return;
      }
      await trayManager.setIcon(icon);
      await _refreshTrayMenu();
      // ⚠️ Lo imprescindible es el icono y su menú; **hasta aquí** se decide si
      // hay bandeja. El resto son adornos y van después a propósito.
      if (mounted) setState(() => _bandejaDisponible = true);
    } catch (e) {
      // Se queda en false: cerrar cerrará de verdad, que es mejor que esconder
      // la app donde el usuario no puede recuperarla.
      debugPrint('Bandeja no disponible ($e); la X cerrará la app.');
      return;
    }

    // El texto al pasar el ratón es un adorno, y **en Linux no existe**: el
    // plugin de tray_manager solo implementa allí setIcon, setContextMenu,
    // setTitle y destroy.
    //
    // ⚠️ Esto estaba antes dentro del try de arriba, y fue un fallo caro: en
    // Linux lanzaba, se lo tragaba el catch, `_bandejaDisponible` se quedaba en
    // false y **la X cerraba la app entera** aunque el icono se viera
    // perfectamente (setIcon ya había pasado). Un adorno que no existe no puede
    // decidir si hay bandeja.
    if (Platform.isWindows) {
      try {
        await trayManager.setToolTip('NeoFy');
      } catch (_) {}
    }
  }

  /// Windows quiere `.ico` y Linux `.png`: un `.ico` en Linux no lo pinta ni
  /// GTK ni el indicador, y el icono saldría en blanco.
  String? _trayIconPath() {
    final nombre = Platform.isWindows ? 'tray.ico' : 'tray.png';
    final exeDir = p.dirname(Platform.resolvedExecutable);
    for (final c in [
      p.join(exeDir, 'data', 'flutter_assets', 'assets', nombre),
      p.join(Directory.current.path, 'assets', nombre),
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
    // `popUpContextMenu` tampoco está implementado en Linux, y allí no hace
    // falta: el indicador enseña su menú por su cuenta al pulsarlo. Llamarlo
    // igualmente solo conseguiría una excepción sin ningún efecto útil.
    if (!Platform.isWindows) return;
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
    await _mpris.stop();
    try {
      // Si la bandeja no llegó a montarse, destruirla lanza; y morir aquí
      // dejaría la ventana abierta con los sidecars ya matados.
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ------------------------------------------------------------------ ventana

  @override
  void onWindowClose() {
    // Esconder en vez de cerrar: la música no se corta al darle a la X.
    //
    // ⚠️ Salvo que no haya bandeja. Esconder una ventana sin dejar un icono al
    // que volver deja la app viva, sonando y fuera del alcance del usuario, que
    // solo puede matarla desde un monitor de sistema. Si no hay bandeja, la X
    // hace lo que dice que hace.
    if (!_bandejaDisponible) {
      unawaited(_quit());
      return;
    }
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
      updater: _updater,
      onSalirParaActualizar: _quit,
      onReiniciarAudio: () =>
          _reiniciarAudio(porElUsuario: true, motivo: 'botón de Ajustes'),
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
