import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_config.dart';
import 'core/art_cache.dart';
import 'core/audio_device.dart';
import 'core/artistas_favoritos_store.dart';
import 'core/auth.dart';
import 'core/carpetas_store.dart';
import 'core/discord_rpc.dart';
import 'core/followed_playlists_store.dart';
import 'core/home_store.dart';
import 'core/idiomas_spotify.dart';
import 'core/librespot.dart';
import 'core/liked_store.dart';
import 'core/media_keys.dart';
import 'core/metadata_sidecar.dart';
import 'core/mpris.dart';
import 'core/player_state.dart';
import 'core/puente_yt.dart';
import 'core/reproduccion_libre.dart';
import 'core/resource_monitor.dart';
import 'core/settings.dart';
import 'core/smtc.dart';
import 'core/spotify_api.dart';
import 'core/tema_store.dart';
import 'core/traductor.dart';
import 'core/ultima_reproduccion.dart';
import 'core/updater.dart';
import 'core/yt_auth.dart';
import 'core/yt_music_api.dart';
import 'core/yt_player.dart';
import 'ui/atajos.dart';
import 'ui/cristal.dart';
import 'ui/login_screen.dart';
import 'ui/shell.dart';

final _lockPort = kDebugMode && Platform.environment['NEOFY_DEBUG_INSTANCE'] == '1' ? 53331 : 53330;

Future<bool> _acquireSingleInstance({VoidCallback? alMostrar}) async {
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _lockPort);
    server.listen((socket) {
      socket.drain<void>().catchError((_) {});
      windowManager.show();
      windowManager.focus();
      alMostrar?.call();
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

VoidCallback? _onMostrarOtraInstancia;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (runWebViewTitleBarWidget(args)) return;

  if (!await _acquireSingleInstance(alMostrar: () => _onMostrarOtraInstancia?.call())) {
    exit(0);
  }

  final config = await AppConfig.load();
  final enDebug =
      kDebugMode && Platform.environment['NEOFY_DEBUG_INSTANCE'] == '1';
  final esPreviewInicial =
      config.canalActualizacion == CanalActualizacion.preview ||
      kEsCompilacionPreview;
  modoPreview.value = esPreviewInicial;

  await windowManager.ensureInitialized();
  final options = WindowOptions(
    size: Size(1000, 680),
    minimumSize: Size(820, 560),
    center: true,
    title: nombreVentanaNeoFy(preview: esPreviewInicial, debug: enDebug),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);

  final temas = TemaStore(config);
  await temas.cargar();
  unawaited(ArtCache.prune());

  runApp(SpotifyNativeApp(config: config, temas: temas));
}

class SpotifyNativeApp extends StatelessWidget {
  const SpotifyNativeApp({super.key, required this.config, required this.temas});

  final AppConfig config;
  final TemaStore temas;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([temas, modoPreview]),
      builder: (context, _) => MaterialApp(
        title: nombreVentanaNeoFy(preview: modoPreview.value),
        debugShowCheckedModeBanner: false,
        theme: temas.themeDataClaro,
        darkTheme: temas.themeDataOscuro,
        themeMode: temas.modo,
        themeAnimationDuration: Duration.zero,
        builder: (context, hijo) =>
            FondoDelTema(child: hijo ?? const SizedBox.shrink()),
        home: RootScreen(config: config, temas: temas),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.config, required this.temas});

  final AppConfig config;
  final TemaStore temas;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WindowListener, TrayListener {
  late final SpotifyAuth _auth = SpotifyAuth(widget.config);
  late final Settings _settings = Settings(widget.config)
    ..onCambioDeModo = _alCambiarDeModo
    ..onCambioDiscord = _alCambiarDiscord
    ..onCambioCanalActualizacion = _alCambiarCanalActualizacion
    ..onCambioIdioma = () {
      _traductor.refrescar();
    };
  late final Traductor _traductor = Traductor(
    localeEfectivo: () => _settings.localeEfectivo,
  );
  late final LibrespotManager _librespot = LibrespotManager(widget.config);
  late final MetadataSidecar _sidecar = MetadataSidecar(
    localeEfectivo: () => localeSpotifyEfectivo(widget.config.idiomaPreferido),
    puedeArrancar: () => _sessionStarted && _librespot.hasCredentials,
  );
  late final SpotifyApi _api = SpotifyApi(
    _auth,
    localeEfectivo: () => localeSpotifyEfectivo(widget.config.idiomaPreferido),
  );
  late final PlayerController _player = PlayerController(_api, widget.config);
  late final LikedStore _likes =
      LikedStore(api: _api, auth: _auth, onReauth: _reauth)
        ..cargarUrisDesdeDisco();
  late final FollowedPlaylistsStore _followed = FollowedPlaylistsStore(
    api: _api,
    auth: _auth,
    obtenerUserId: () => _player.currentUserId,
    onReauth: _reauth,
  );
  late final ArtistasFavoritosStore _favoritos = ArtistasFavoritosStore(
    api: _api,
    auth: _auth,
    onReauth: _reauth,
  );
  late final HomeStore _home = HomeStore(api: _api, auth: _auth);
  late final CarpetasStore _carpetas = CarpetasStore()..cargar();
  final UltimaReproduccionStore _memoria = UltimaReproduccionStore();

  late final ResourceMonitor _ram = ResourceMonitor(
    pidsDeSidecars: () => [_librespot.pid, _sidecar.pid],
  );

  late final DiscordRpc _discordRpc = DiscordRpc();
  late final Updater _updater = Updater(
    canalInicial: widget.config.canalActualizacion,
  );

  static bool _mediaKitInicializado = false;
  final YtAuth _ytAuth = YtAuth();
  late final YtMusicApi _ytApi = YtMusicApi(_ytAuth);
  YtPlayer? _ytPlayer;

  YtPlayer _asegurarYtPlayer() {
    final existente = _ytPlayer;
    if (existente != null) return existente;
    if (!_mediaKitInicializado) {
      try {
        MediaKit.ensureInitialized();
      } catch (e) {
        YtPlayer.libmpvDisponible = false;
        debugPrint('[vía libre] sin libmpv, no se podrá reproducir por YouTube: $e');
      }
      _mediaKitInicializado = true;
    }
    final player = YtPlayer(volumenInicial: widget.config.volumenNeoTube);
    player.alEmpezarAReproducir = _player.pause;
    player.onVolumenFijado = (v) {
      widget.config.volumenNeoTube = v;
      unawaited(widget.config.save());
    };
    player.onSalto = (ms) {
      _mpris.notificarSalto(ms * 1000);
      _smtc.notificarSalto(ms);
    };
    _ytPlayer = player;
    return player;
  }

  late final MediaKeys _mediaKeys = MediaKeys(
    onPlayPause: () => _mandoDeFuera('playPause', _alternar),
    onNext: () => _mandoDeFuera('next', _siguiente),
    onPrevious: () => _mandoDeFuera('previous', _anterior),
    onPause: () => _mandoDeFuera('pause', _pausar),
  );

  Future<void> _alternar() => _player.togglePlay();

  Future<void> _siguiente() => _player.next();

  Future<void> _anterior() => _player.previous();

  Future<void> _pausar() => _player.pause();

  Future<void> _saltarA(int ms) => _player.seek(ms);

  late final SmtcService _smtc = SmtcService(
    onPlayPause: () => _mandoDeFuera('playPause', _alternar),
    onPlay: () => _mandoDeFuera('play', _reproducirSiEstaParado),
    onPause: () => _mandoDeFuera('pause', _pausar),
    onNext: () => _mandoDeFuera('next', _siguiente),
    onPrevious: () => _mandoDeFuera('previous', _anterior),
    onSeek: (ms) => _mandoDeFuera('seek', () => _saltarA(ms)),
    estado: _estadoParaElSistema,
  );

  EstadoDelSistema _estadoParaElSistema() => EstadoDelSistema(
        track: _player.state.track,
        sonando: _player.state.isPlaying,
        posicionMs: _player.progressMs.value,
        puedeSaltar: _player.state.canSkipNext,
        puedeVolver: _player.state.canSkipPrevious,
        volumen: _player.state.volumePercent,
      );

  DateTime _ultimoMando = DateTime.fromMillisecondsSinceEpoch(0);
  String? _ultimoMandoQue;

  Future<void> _mandoDeFuera(String que, Future<void> Function() accion) async {
    final ahora = DateTime.now();
    if (que == _ultimoMandoQue &&
        ahora.difference(_ultimoMando) < const Duration(milliseconds: 250)) {
      return;
    }
    _ultimoMandoQue = que;
    _ultimoMando = ahora;
    await accion();
  }

  late final AudioDeviceWatcher _audio =
      AudioDeviceWatcher(
          onCambio: () => _reiniciarAudio(motivo: 'Windows cambió de altavoz'));

  late final MprisService _mpris = MprisService(
    onPlayPause: _alternar,
    onPlay: _reproducirSiEstaParado,
    onPause: _pausar,
    onNext: _siguiente,
    onPrevious: _anterior,
    onSeek: (us) => _saltarA(us ~/ 1000),
    onRaise: () {
      windowManager.show();
      windowManager.focus();
      _alVerse();
    },
    estado: _estadoParaElSistema,
  );

  bool _booting = true;
  bool _sessionStarted = false;
  int _generacionSesion = 0;
  bool _reiniciandoAudio = false;

  bool _ventanaVisible = true;
  bool _bibliotecaLiberada = false;
  Timer? _podaAlEsconder;
  Timer? _podaAlEsconderTardia;
  DateTime _ultimoReinicioDeAudio = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _onMostrarOtraInstancia = () {
      if (mounted) _alVerse();
    };
    windowManager.addListener(this);
    trayManager.addListener(this);
    _mediaKeys.start();
    unawaited(_mpris.start());
    _smtc.start();
    if (_settings.discordRpcEnabled && _settings.discordClientId.isNotEmpty) {
      _discordRpc.start(_settings.discordClientId);
    }
    _player.addListener(_avisarAlSistema);
    _player.onSalto = (ms) {
      _mpris.notificarSalto(ms * 1000);
      _smtc.notificarSalto(ms);
    };
    _audio.start();
    _librespot.onFalloDeAudio = (linea) =>
        unawaited(_reiniciarAudio(motivo: 'error en el log: $linea'));
    _ram.start();
    unawaited(_updater.buscar());
    _aplicarTechoDeMemoria(_settings.performanceMode);
    unawaited(_setupTray());
    unawaited(_boot());
  }

  @override
  void dispose() {
    _onMostrarOtraInstancia = null;
    _podaAlEsconder?.cancel();
    _podaAlEsconderTardia?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _mediaKeys.stop();
    _player.removeListener(_avisarAlSistema);
    _player.onSalto = null;
    _ytPlayer?.alEmpezarAReproducir = null;
    _ytPlayer?.onVolumenFijado = null;
    _ytPlayer?.onSalto = null;
    unawaited(_mpris.stop());
    unawaited(_smtc.stop());
    _audio.stop();
    _player.dispose();
    _likes.dispose();
    _followed.dispose();
    _favoritos.dispose();
    _traductor.dispose();
    _home.dispose();
    _carpetas.dispose();
    _ram.dispose();
    _settings.dispose();
    _discordRpc.dispose();
    _updater.dispose();
    _librespot.dispose();
    _sidecar.dispose();
    _ytPlayer?.dispose();
    _api.close();
    _auth.close();
    _ytApi.close();
    super.dispose();
  }

  DateTime _ultimoRecuerdo = DateTime.fromMillisecondsSinceEpoch(0);
  String? _uriRecordada;

  Future<void> _recordarReproduccion({bool forzar = false}) async {
    final ultima = _player.paraRecordar();
    if (ultima == null) return;
    final ahora = DateTime.now();
    if (!forzar &&
        ultima.track.uri == _uriRecordada &&
        ahora.difference(_ultimoRecuerdo) < const Duration(seconds: 20)) {
      return;
    }
    _uriRecordada = ultima.track.uri;
    _ultimoRecuerdo = ahora;
    await _memoria.guardar(ultima);
  }

  void _avisarAlSistema() {
    unawaited(_recordarReproduccion());
    caratulaDeFondo.value =
        _player.state.track?.artMedium ?? _player.state.track?.artSmall;
    _mpris.notificarCambio();
    _smtc.notificarCambio();
    if (_player.libre == null) {
      _discordRpc.actualizarActividad(
        track: _player.state.track,
        sonando: _player.state.isPlaying,
        progresoMs: _player.progressMs.value,
        obtenerCola: _api.queue,
      );
    } else {
      unawaited(_discordRpc.limpiar());
    }
  }

  Future<void> _boot() async {
    await _auth.loadStored();
    if (_auth.isLoggedIn) {
      await _startSession();
    }
    unawaited(_ytAuth.loadStored().then((_) {
      if (mounted) setState(() {});
    }));
    if (mounted) setState(() => _booting = false);
  }

  Future<void> _startSession() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    final generacion = ++_generacionSesion;
    _player.aplicarPerfilSpotify(const {});

    final ultima = await _memoria.cargar();
    if (!mounted) return;
    if (ultima != null) _player.restaurar(ultima);

    await _librespot.start();

    unawaited(_cargarCuenta(generacion));
    unawaited(_favoritos.cargar());
    _player.start();
    unawaited(_waitForDevice(generacion));
  }

  Future<void> _cargarCuenta(int generacion) async {
    try {
      final me = await _api.me();
      if (!mounted || generacion != _generacionSesion) return;
      _player.aplicarPerfilSpotify(me);

      if (!_player.isPremium) {
        _player.libre = ReproduccionLibre(
          puente: PuenteYt(_ytApi),
          ytPlayer: _asegurarYtPlayer(),
          api: _api,
          controller: _player,
        );
        _player.olvidarDispositivo();
        await _librespot.stop();
      }
    } catch (_) {}
  }

  Future<void> _reiniciarAudio({bool porElUsuario = false, String motivo = '?'}) async {
    if (!_sessionStarted || _reiniciandoAudio) return;
    debugPrint('Reiniciando el audio (motivo: $motivo)');
    final desde = DateTime.now().difference(_ultimoReinicioDeAudio);
    if (!porElUsuario && desde < const Duration(seconds: 20)) return;

    _reiniciandoAudio = true;
    _ultimoReinicioDeAudio = DateTime.now();
    try {
      final antes = _player.instantanea();
      final viejo = _player.olvidarDispositivo();
      await _librespot.reiniciar();

      for (var i = 0; i < 20; i++) {
        if (!mounted) return;
        if (await _player.resolveDevice(transfer: false, distintoDe: viejo)) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      if (_player.ourDeviceId == null) {
        await _player.resolveDevice(transfer: false);
      }
      if (!mounted) return;
      await _player.retomar(antes);
    } finally {
      _reiniciandoAudio = false;
    }
  }

  void _alCambiarDeModo(bool activo) {
    _aplicarTechoDeMemoria(activo);
    if (activo) {
      unawaited(_sidecar.stop());
      ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
    }
  }

  void _alCambiarDiscord(bool activo, String clientId) {
    if (activo && clientId.isNotEmpty) {
      _discordRpc.start(clientId);
      _avisarAlSistema();
    } else {
      unawaited(_discordRpc.stop());
    }
  }

  void _alCambiarCanalActualizacion(CanalActualizacion canal) {
    unawaited(_actualizarTituloVentana());
    unawaited(_updater.cambiarCanal(canal));
  }

  Future<void> _actualizarTituloVentana() async {
    final enDebug =
        kDebugMode && Platform.environment['NEOFY_DEBUG_INSTANCE'] == '1';
    final titulo = nombreVentanaNeoFy(
      preview: _settings.enModoPreview,
      debug: enDebug,
    );
    try {
      await windowManager.setTitle(titulo);
    } catch (_) {}
    if (Platform.isWindows && _bandejaDisponible) {
      try {
        await trayManager.setToolTip(
          nombreVentanaNeoFy(preview: _settings.enModoPreview),
        );
      } catch (_) {}
    }
  }

  static const _techoRendimiento = 75 << 20;

  void _aplicarTechoDeMemoria(bool activo) {
    _ram.techoBytes = activo ? _techoRendimiento : null;
    if (activo) {
      ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
    }
  }

  Future<void> _waitForDevice(int generacion) async {
    for (var i = 0; i < 15; i++) {
      if (!mounted ||
          generacion != _generacionSesion ||
          _player.libre != null) {
        return;
      }
      if (await _player.resolveDevice()) {
        if (!mounted ||
            generacion != _generacionSesion ||
            _player.libre != null) {
          return;
        }
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
    _smtc.start();
    await _startSession();
    if (mounted) setState(() {});
  }

  Future<void> _reauth() async {
    try {
      await _auth.login();
      unawaited(_favoritos.cargar(forzar: true));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo reautorizar: $e')));
      }
    }
  }

  bool _bandejaDisponible = false;

  Future<void> _setupTray() async {
    try {
      final icon = _trayIconPath();
      if (icon == null) {
        debugPrint('Bandeja: no se encuentra el icono; la X cerrará la app.');
        return;
      }
      await trayManager.setIcon(icon);
      await _refreshTrayMenu();
      if (mounted) setState(() => _bandejaDisponible = true);
    } catch (e) {
      debugPrint('Bandeja no disponible ($e); la X cerrará la app.');
      return;
    }

    if (Platform.isWindows) {
      try {
        await trayManager.setToolTip(
          nombreVentanaNeoFy(preview: _settings.enModoPreview),
        );
      } catch (_) {}
    }
  }

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
    _alVerse();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!Platform.isWindows) return;
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'playpause':
        unawaited(_alternar());
      case 'next':
        unawaited(_siguiente());
      case 'previous':
        unawaited(_anterior());
      case 'show':
        windowManager.show();
        windowManager.focus();
        _alVerse();
      case 'exit':
        unawaited(_quit());
    }
  }

  Future<void> _quit() async {
    await _recordarReproduccion(forzar: true);
    await _sidecar.stop();
    await _librespot.stop();
    await _mpris.stop();
    await _smtc.stop();
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
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
  void onWindowRestore() => _alVerse();

  @override
  void onWindowFocus() => _alVerse();

  void _alVerse() {
    _podaAlEsconder?.cancel();
    _podaAlEsconder = null;
    _podaAlEsconderTardia?.cancel();
    _podaAlEsconderTardia = null;
    final cambio = !_ventanaVisible;
    _ventanaVisible = true;
    _ram.setVisible(true);
    _ajustarSondeo();
    if (cambio && mounted) {
      setState(() {});
      if (_bibliotecaLiberada) {
        _bibliotecaLiberada = false;
        unawaited(_likes.cargarBiblioteca());
      }
    }
  }

  void _alEsconderse() {
    final cambio = _ventanaVisible;
    _ventanaVisible = false;
    _ram.setVisible(false);
    _ajustarSondeo();
    if (cambio && mounted) setState(() {});

    unawaited(_recordarReproduccion(forzar: true));
    unawaited(_sidecar.detenerSiInactivo(inmediato: true));
    _liberarBibliotecaAlEsconder();

    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);

    _podaAlEsconder?.cancel();
    _podaAlEsconder = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _ventanaVisible) return;
      final c = PaintingBinding.instance.imageCache;
      c.clear();
      c.clearLiveImages();
      ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
    });

    _podaAlEsconderTardia?.cancel();
    _podaAlEsconderTardia = Timer(const Duration(seconds: 3), () {
      if (!mounted || _ventanaVisible) return;
      final c = PaintingBinding.instance.imageCache;
      c.clear();
      c.clearLiveImages();
      _liberarBibliotecaAlEsconder();
      ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
    });
  }

  void _liberarBibliotecaAlEsconder() {
    if (_likes.liberarMemoriaDeBiblioteca()) _bibliotecaLiberada = true;
  }

  void _ajustarSondeo() => _player.setWindowVisible(_ventanaVisible);

  @override
  Widget build(BuildContext context) {
    return TraductorScope(
      notifier: _traductor,
      child: TickerMode(
        enabled: _ventanaVisible,
        child: _buildContenido(),
      ),
    );
  }

  Widget _buildContenido() {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_auth.isLoggedIn) {
      return LoginScreen(
        auth: _auth,
        config: widget.config,
        onLoggedIn: _onLoggedIn,
        ytAuth: _ytAuth,
      );
    }
    return AtajosDeReproduccion(
      onPlayPause: () => unawaited(_alternar()),
      onNext: () => unawaited(_siguiente()),
      onPrevious: () => unawaited(_anterior()),
      child: AppShell(
        api: _api,
        auth: _auth,
        player: _player,
        likes: _likes,
        followed: _followed,
        favoritos: _favoritos,
        home: _home,
        carpetas: _carpetas,
        ram: _ram,
        settings: _settings,
        temas: widget.temas,
        updater: _updater,
        onSalirParaActualizar: _quit,
        onReiniciarAudio: () =>
            _reiniciarAudio(porElUsuario: true, motivo: 'botón de Ajustes'),
        librespot: _librespot,
        sidecar: _sidecar,
        onReauth: _reauth,
        ytAuth: _ytAuth,
        onLogout: () async {
          ++_generacionSesion;
          await _sidecar.stop();
          await _librespot.stop();
          _player.libre?.dispose();
          _player.libre = null;
          _ytPlayer?.alEmpezarAReproducir = null;
          _ytPlayer?.onVolumenFijado = null;
          _ytPlayer?.onSalto = null;
          _ytPlayer?.dispose();
          _ytPlayer = null;
          _player.olvidarDispositivo();
          await _auth.logout();
          _favoritos.limpiar();
          await _smtc.stop();
          _sessionStarted = false;
          if (mounted) setState(() {});
        },
      ),
    );
  }
}
