import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
// `hide Track`: media_kit llama `Track` a su pista de audio/vídeo de libmpv y
// choca con el `Track` de Spotify de `core/models.dart`, que es el que habla el
// panel del sistema. Aquí solo hace falta `MediaKit.ensureInitialized()`.
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_config.dart';
import 'core/app_mode.dart';
import 'core/art_cache.dart';
import 'core/audio_device.dart';
import 'core/auth.dart';
import 'core/carpetas_store.dart';
import 'core/home_store.dart';
import 'core/librespot.dart';
import 'core/liked_store.dart';
import 'core/media_keys.dart';
import 'core/metadata_sidecar.dart';
import 'core/models.dart';
import 'core/mpris.dart';
import 'core/player_state.dart';
import 'core/resource_monitor.dart';
import 'core/settings.dart';
import 'core/smtc.dart';
import 'core/spotify_api.dart';
import 'core/updater.dart';
import 'core/yt_auth.dart';
import 'core/yt_music_api.dart';
import 'core/yt_player.dart';
import 'ui/atajos.dart';
import 'ui/login_screen.dart';
import 'ui/mode_host.dart';
import 'ui/neotube_shell.dart';
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

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // La ventana de login de NeoTube (`YtAuth.login()`) es una WebView de
  // verdad, y en Windows `desktop_webview_window` la dibuja relanzando este
  // mismo `neofy.exe` con argumentos especiales para pintar solo su barra de
  // título — por eso esta comprobación va la primera de todas, antes incluso
  // del candado de instancia única: si entra por aquí, no es una segunda
  // NeoFy, es esa ventanita.
  if (runWebViewTitleBarWidget(args)) return;
  // Registra los plugins nativos de media_kit (libmpv). Hace falta antes de
  // crear ningún `Player`, aunque el usuario no llegue a entrar en NeoTube.
  //
  // ⚠️ El try/catch no es defensivo por si acaso: en Linux `media_kit` **no
  // empaqueta libmpv**, la busca en el sistema con `dlopen`, y si no está esta
  // llamada lanza. Al estar antes de `runApp()`, una distribución sin libmpv
  // instalado hacía que la app arrancara y se cerrara sin ventana ni mensaje —
  // el fallo que se veía en Arch, donde `mpv` no viene de serie. Los paquetes
  // ya lo declaran como dependencia, pero el tarball no puede exigir nada, así
  // que aquí NeoTube se apaga y NeoFy (que suena por librespot, en otro
  // proceso) sigue funcionando entera.
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    YtPlayer.libmpvDisponible = false;
    // El mensaje que se enseña es el nuestro y no `$e`: el de media_kit está
    // en inglés y solo sabe recomendar `apt install libmpv-dev`, que no ayuda
    // a nadie en Arch ni en Fedora. El original se queda en el log.
    debugPrint('[NeoTube] sin libmpv, el modo queda desactivado: $e');
  }

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
  // El modo persistido se aplica aquí y no en el constructor de `Settings`:
  // `Settings` se crea más tarde, durante el primer build de `RootScreen`,
  // que ya cuelga del `ValueListenableBuilder<AppMode>` de arriba — mutar
  // `modoApp` en ese momento marcaba un ancestro sucio a mitad de un build en
  // curso ("setState() called during build"). Dejándolo ya correcto aquí, la
  // asignación que hace `Settings` después es un no-op (mismo valor).
  modoApp.value = AppMode.fromNombre(config.modo);
  // Podar la caché de carátulas fuera del camino crítico del arranque.
  unawaited(ArtCache.prune());

  runApp(SpotifyNativeApp(config: config));
}

/// Semillas de color de cada modo. NeoTube usa un rojo propio y no el rojo
/// saturado de la marca de YouTube — mismo motivo que el icono de NeoFy no es
/// el logo de Spotify recoloreado: no sugerir patrocinio de nadie.
///
/// Es el mismo rojo que `kColorFavorito` (`ui/like_button.dart`) y no uno
/// nuevo: varios tonos de rojo probados como semilla de `ColorScheme.fromSeed`
/// salían sucios/marrones en modo oscuro (la paleta tonal de Material 3 baja
/// mucho el croma de las superficies), y este es el único rojo de la app ya
/// validado visualmente.
const Color kSeedNeoFy = Color(0xFF1DB954);
const Color kSeedNeoTube = Color(0xFFE53935);

class SpotifyNativeApp extends StatelessWidget {
  const SpotifyNativeApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppMode>(
      valueListenable: modoApp,
      builder: (context, modo, _) {
        final seed = modo == AppMode.neotube ? kSeedNeoTube : kSeedNeoFy;
        return MaterialApp(
          title: 'NeoFy',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          // No hace falta envolver nada en `AnimatedTheme` a mano: `MaterialApp`
          // ya interpola internamente su `theme`/`darkTheme` con uno — por
          // eso basta con cambiar el `seedColor` de golpe en cada build para
          // que el giro a rojo (o de vuelta a verde) se vea como transición.
          home: RootScreen(config: config),
        );
      },
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
  // Las carpetas de "Tus playlists" son locales (la Web API no las expone), así
  // que este store no toca la red: solo carga y guarda `carpetas.json`.
  late final CarpetasStore _carpetas = CarpetasStore()..cargar();

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

  /// El trío de NeoTube. Nada de esto depende de que el usuario llegue a
  /// entrar en ese modo — se crea igual que `_auth`/`_api`/`_player`, solo
  /// que no arranca ningún proceso hasta la primera reproducción real.
  final YtAuth _ytAuth = YtAuth();
  late final YtMusicApi _ytApi = YtMusicApi(_ytAuth);
  // El volumen viaja en el config, aparte del de NeoFy: son dos reproductores
  // distintos y bajar uno no debe bajar el otro.
  late final YtPlayer _ytPlayer = YtPlayer(volumenInicial: widget.config.volumenNeoTube);

  /// Teclas multimedia del sistema, incluido el botón de los cascos. Llegan
  /// aunque la ventana esté escondida en la bandeja.
  ///
  /// Van al **modo activo**, no a NeoFy siempre: con NeoTube delante, el botón
  /// de los cascos tiene que parar lo que se está oyendo, no reanudar Spotify
  /// por detrás. Ver [_reproductorActivo].
  late final MediaKeys _mediaKeys = MediaKeys(
    onPlayPause: () => _mandoDeFuera('playPause', _alternar),
    onNext: () => _mandoDeFuera('next', _siguiente),
    onPrevious: () => _mandoDeFuera('previous', _anterior),
    onPause: () => _mandoDeFuera('pause', _pausar),
  );

  /// Cuál de los dos reproductores manda ahora mismo.
  ///
  /// Es la pieza que faltaba para que los dos modos sean de verdad dos modos:
  /// las teclas multimedia, el panel del sistema, la bandeja y el espacio del
  /// teclado iban **siempre** a Spotify, así que desde NeoTube cualquiera de
  /// ellos reanudaba música del otro modo por debajo.
  bool get _mandaNeoTube => modoApp.value.esNeoTube;

  Future<void> _alternar() =>
      _mandaNeoTube ? _ytPlayer.alternar() : _player.togglePlay();

  Future<void> _siguiente() => _mandaNeoTube ? _ytPlayer.siguiente() : _player.next();

  Future<void> _anterior() => _mandaNeoTube ? _ytPlayer.anterior() : _player.previous();

  Future<void> _pausar() => _mandaNeoTube ? _ytPlayer.pause() : _player.pause();

  Future<void> _saltarA(int ms) => _mandaNeoTube
      ? _ytPlayer.seek(Duration(milliseconds: ms))
      : _player.seek(ms);

  /// Los controles multimedia de Windows: el panel del centro de control y los
  /// botones bajo la miniatura de la barra de tareas. Es el equivalente de
  /// [_mpris] en Windows, y como allí, lo que consigue es que el sistema sepa
  /// que esto es un reproductor de audio.
  late final SmtcService _smtc = SmtcService(
    onPlayPause: () => _mandoDeFuera('playPause', _alternar),
    // Igual que en MPRIS: `Play` no es el toggle. El panel del sistema manda
    // `Play` a secas y mapearlo al toggle pausaría lo que ya está sonando.
    onPlay: () => _mandoDeFuera('play', _reproducirSiEstaParado),
    onPause: () => _mandoDeFuera('pause', _pausar),
    onNext: () => _mandoDeFuera('next', _siguiente),
    onPrevious: () => _mandoDeFuera('previous', _anterior),
    onSeek: (ms) => _mandoDeFuera('seek', () => _saltarA(ms)),
    estado: _estadoParaElSistema,
  );

  /// Lo que hay que enseñar fuera de la ventana, igual para las dos
  /// plataformas: el panel de Windows y el widget del escritorio en Linux piden
  /// exactamente lo mismo. Y lo que enseñan es el **modo activo**: si no, con
  /// NeoTube sonando el escritorio anunciaba la última canción de Spotify.
  EstadoDelSistema _estadoParaElSistema() =>
      _mandaNeoTube ? _estadoDeNeoTube() : _estadoDeNeoFy();

  EstadoDelSistema _estadoDeNeoFy() => EstadoDelSistema(
        track: _player.state.track,
        sonando: _player.state.isPlaying,
        // La posición interpolada en local, que se actualiza cada 250 ms sin
        // gastar ni una petición. Ver "Sondeo: por qué es como es".
        posicionMs: _player.progressMs.value,
        puedeSaltar: _player.state.canSkipNext,
        puedeVolver: _player.state.canSkipPrevious,
        volumen: _player.state.volumePercent,
      );

  /// NeoTube reproduce en este mismo proceso, así que aquí no hay nada
  /// interpolado ni sondeado: `media_kit` da la posición exacta.
  ///
  /// El `Track` se construye al vuelo porque es el vocabulario que hablan
  /// MPRIS y el panel de Windows; no se guarda en ningún sitio ni pretende ser
  /// un modelo de NeoTube (ese es `YtTrack`).
  EstadoDelSistema _estadoDeNeoTube() {
    final t = _ytPlayer.actual;
    if (t == null) return EstadoDelSistema.vacio;
    return EstadoDelSistema(
      track: Track(
        id: t.videoId,
        uri: 'https://music.youtube.com/watch?v=${t.videoId}',
        name: t.titulo,
        artists: t.artista,
        album: '',
        artSmall: t.miniatura,
        artMedium: t.miniatura,
        durationMs: (_ytPlayer.duracion > Duration.zero
                ? _ytPlayer.duracion
                : (t.duracion ?? Duration.zero))
            .inMilliseconds,
        isLocal: false,
      ),
      sonando: _ytPlayer.sonando,
      posicionMs: _ytPlayer.posicion.inMilliseconds,
      puedeSaltar: _ytPlayer.puedeSaltar,
      puedeVolver: _ytPlayer.puedeVolver,
      volumen: _ytPlayer.volumen,
    );
  }

  /// Cuándo llegó la última orden de fuera de la ventana, y cuál era.
  DateTime _ultimoMando = DateTime.fromMillisecondsSinceEpoch(0);
  String? _ultimoMandoQue;

  /// Ejecuta una orden que viene de fuera **una sola vez**.
  ///
  /// ⚠️ En Windows una misma pulsación puede llegar por **dos vías a la vez**.
  /// El runner registra las teclas multimedia con `RegisterHotKey`, y desde que
  /// la app se anuncia como reproductor Windows también las reparte por el
  /// panel del sistema. Normalmente gana el atajo global y el panel ni las ve,
  /// pero eso depende de quién registró qué antes y de si otra app se adelantó
  /// —cosa que `RegisterMediaKeys` tolera a propósito—. Un play/pausa contado
  /// dos veces se queda exactamente como estaba, y el síntoma sería que el botón
  /// de los cascos "no funciona" unas veces sí y otras no.
  ///
  /// El cuarto de segundo es de sobra para descartar el duplicado (llega en el
  /// mismo evento de entrada, con milisegundos de diferencia) y lo bastante
  /// corto para no comerse un doble salto que el usuario quiera de verdad.
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

  /// Cambios de la salida de audio del sistema. Ver [_reiniciarAudio].
  late final AudioDeviceWatcher _audio =
      AudioDeviceWatcher(
          onCambio: () => _reiniciarAudio(motivo: 'Windows cambió de altavoz'));

  /// Lo mismo que [_mediaKeys], pero en Linux: allí las teclas multimedia las
  /// reparte el escritorio entre los reproductores que hablan MPRIS. De regalo,
  /// NeoFy sale en el widget de reproducción del sistema con carátula.
  late final MprisService _mpris = MprisService(
    onPlayPause: _alternar,
    // ⚠️ `Play` no es `togglePlay`: MPRIS distingue las dos cosas y el
    // escritorio manda `Play` a secas cuando el usuario le da al botón de
    // reproducir. Mapearlo al toggle pausaría lo que ya está sonando.
    onPlay: _reproducirSiEstaParado,
    onPause: _pausar,
    onNext: _siguiente,
    onPrevious: _anterior,
    onSeek: (us) => _saltarA(us ~/ 1000),
    onRaise: () {
      windowManager.show();
      windowManager.focus();
    },
    estado: _estadoParaElSistema,
  );

  bool _booting = true;
  bool _sessionStarted = false;
  bool _reiniciandoAudio = false;

  /// ¿Se ve la ventana? Junto con el modo activo decide el ritmo de sondeo de
  /// la Web API — ver [_ajustarSondeoDeNeoFy].
  bool _ventanaVisible = true;
  StreamSubscription<bool>? _subYtSonando;
  DateTime _ultimoReinicioDeAudio = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _mediaKeys.start();
    unawaited(_mpris.start());
    _smtc.start();
    // Se engancha al notificador general y no a `currentUri`: pausar no cambia
    // de canción, y con solo `currentUri` el widget del escritorio se quedaría
    // diciendo "reproduciendo" con la música parada. Que esto salte cada 3 s no
    // importa — `notificarCambio` compara una firma y no emite si no ha
    // cambiado nada.
    _player.addListener(_avisarAlSistema);
    // Un salto de la barra sí hay que anunciarlo aparte: los dos reproductores
    // del sistema extrapolan la posición por su cuenta y sin esto se quedan
    // enseñando el minuto de antes.
    _player.onSalto = (ms) {
      _mpris.notificarSalto(ms * 1000);
      _smtc.notificarSalto(ms);
    };
    // Las dos vías por las que se detecta que el audio se ha quedado mudo: que
    // Windows cambie de altavoces, y que el propio librespot se queje en su log.
    _audio.start();
    _librespot.onFalloDeAudio = (linea) =>
        unawaited(_reiniciarAudio(motivo: 'error en el log: $linea'));
    // Los dos modos comparten altavoces: que empiece a sonar NeoTube tiene que
    // callar a Spotify, sin excepción. Se hace aquí y no solo al cambiar de
    // modo porque una pista puede arrancar sola al terminar la anterior.
    _ytPlayer.alEmpezarAReproducir = _player.pause;
    // Al soltar el mando, no en cada paso: si no, serían decenas de escrituras
    // del config por cada vez que alguien mueve el volumen.
    _ytPlayer.onVolumenFijado = (v) {
      widget.config.volumenNeoTube = v;
      unawaited(widget.config.save());
    };
    _ytPlayer.onSalto = (ms) {
      _mpris.notificarSalto(ms * 1000);
      _smtc.notificarSalto(ms);
    };
    // El panel del sistema tiene que enterarse de lo que hace NeoTube igual
    // que de lo que hace NeoFy: cambio de pista (el notificador) y play/pausa
    // (el stream de media_kit, que el notificador no cubre).
    _ytPlayer.addListener(_avisarAlSistema);
    _subYtSonando = _ytPlayer.cambiosDeSonando.listen((_) => _avisarAlSistema());
    modoApp.addListener(_alCambiarDeModoDeApp);
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
    modoApp.removeListener(_alCambiarDeModoDeApp);
    _mediaKeys.stop();
    _player.removeListener(_avisarAlSistema);
    _player.onSalto = null;
    _ytPlayer.removeListener(_avisarAlSistema);
    unawaited(_subYtSonando?.cancel());
    unawaited(_mpris.stop());
    unawaited(_smtc.stop());
    _audio.stop();
    _player.dispose();
    _likes.dispose();
    _home.dispose();
    _carpetas.dispose();
    _ram.dispose();
    _settings.dispose();
    _updater.dispose();
    _librespot.dispose();
    _sidecar.dispose();
    _ytPlayer.dispose();
    super.dispose();
  }

  /// Los dos a la vez: solo uno está activo en cada plataforma, y el otro no
  /// hace nada. Tenerlo en un único sitio evita que se queden contando cosas
  /// distintas, que es justo lo que no se podría probar desde aquí.
  void _avisarAlSistema() {
    _mpris.notificarCambio();
    _smtc.notificarCambio();
  }

  Future<void> _boot() async {
    await _auth.loadStored();
    if (_auth.isLoggedIn) {
      await _startSession();
    }
    // La sesión de NeoTube no bloquea el arranque de NeoFy: es independiente
    // y no hay ningún proceso que levantar solo por tener el token guardado.
    unawaited(_ytAuth.loadStored().then((_) {
      if (mounted) setState(() {});
    }));
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
      // Soltar la caché no basta: hasta que el sistema no recoja las páginas
      // —o glibc no suelte sus arenas en Linux—, la memoria sigue contando
      // como residente aunque ya esté libre. Se pide que la recojan ya.
      ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
    } else if (_sessionStarted) {
      unawaited(_startSidecar());
    }
  }

  /// El objetivo del modo rendimiento: 100 MB entre los tres procesos.
  static const _techoRendimiento = 100 << 20;

  void _aplicarTechoDeMemoria(bool activo) {
    _ram.techoBytes = activo ? _techoRendimiento : null;
    if (activo) {
      ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
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
    if (_mandaNeoTube) {
      if (_ytPlayer.sonando) return;
      await _ytPlayer.resume();
      return;
    }
    if (_player.state.isPlaying) return;
    await _player.togglePlay();
  }

  Future<void> _onLoggedIn() async {
    // Cerrar sesión apaga el panel del sistema para no dejarlo enseñando la
    // canción de una sesión que ya no existe; volver a entrar tiene que
    // encenderlo otra vez o se quedaría muerto hasta el siguiente arranque.
    _smtc.start();
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
      // Al modo activo, como las teclas multimedia: desde NeoTube, el menú de
      // la bandeja no debe manejar Spotify a espaldas del usuario.
      case 'playpause':
        unawaited(_alternar());
      case 'next':
        unawaited(_siguiente());
      case 'previous':
        unawaited(_anterior());
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
    await _smtc.stop();
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
  void onWindowRestore() => _alVerse();

  @override
  void onWindowFocus() => _alVerse();

  void _alVerse() {
    _ventanaVisible = true;
    _ajustarSondeoDeNeoFy();
  }

  /// Un reproductor de música se pasa la vida escondido en la bandeja, y ahí
  /// no hay ni una imagen que mirar: los bitmaps decodificados que quedaran en
  /// la caché serían megas retenidos durante horas para nada. Se sueltan.
  ///
  /// No se pierde nada: las carátulas siguen en disco, así que al volver se
  /// vuelven a decodificar sin bajar nada de la red.
  void _alEsconderse() {
    _ventanaVisible = false;
    _ajustarSondeoDeNeoFy();
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    // Y que el sistema se lleve las páginas que quedan sin usar: escondida en
    // la bandeja, la app no necesita tener nada residente. Aquí es donde más
    // se nota, porque la caché de imágenes se acaba de vaciar entera.
    ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
  }

  /// Lo mismo que [_alEsconderse], pero disparado al cambiar de modo (ver
  /// `ModeToggleText.onSufijoBorrado`): a mitad de la animación del botón,
  /// con el sufijo ya borrado y el nuevo aún sin escribir. La caché de
  /// imágenes de Flutter es una sola, compartida por NeoFy y NeoTube — no
  /// hace falta saber cuál de los dos la llenó, basta con vaciarla justo
  /// antes de que el modo saliente deje de pintarse, que es cuando no sirve
  /// para nada tenerla ocupando RAM.
  void _liberarRamDelModoSaliente() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    ResourceMonitor.devolverMemoriaAlSistema([_librespot.pid, _sidecar.pid]);
  }

  /// Cambiar de modo **calla el modo que se deja**.
  ///
  /// NeoFy y NeoTube no son dos pestañas de un mismo reproductor: son dos
  /// reproductores, cada uno con su sesión y su audio, y comparten unos únicos
  /// altavoces. Que Spotify siguiera sonando (o simplemente "activo", listo
  /// para que el espacio o los cascos lo reanudaran) con NeoTube delante era el
  /// síntoma que más se notaba de que el aislamiento no estaba hecho.
  ///
  /// Se pausa, no se apaga: librespot sigue vivo porque es lo que mantiene el
  /// dispositivo registrado en Spotify Connect, y matarlo obligaría a esperar
  /// otra vez a que se registre al volver.
  void _alCambiarDeModoDeApp() {
    if (_mandaNeoTube) {
      unawaited(_player.pause());
    } else {
      unawaited(_ytPlayer.pause());
    }
    _ajustarSondeoDeNeoFy();
    // El panel del sistema tiene que dejar de anunciar el modo que se acaba de
    // dejar: quien manda ahora es el otro.
    _avisarAlSistema();
  }

  /// La Web API solo hace falta sondearla deprisa cuando NeoFy está delante.
  /// Con NeoTube en pantalla, Spotify está pausado y mirando: sondear cada 3 s
  /// serían 1.200 peticiones a la hora para no enseñar nada.
  void _ajustarSondeoDeNeoFy() =>
      _player.setWindowVisible(_ventanaVisible && !_mandaNeoTube);

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
    // Los atajos van **por encima** de los dos modos y reparten según cuál
    // esté activo. Antes vivían dentro de `AppShell`, que sigue montado detrás
    // de NeoTube: por eso el espacio reanudaba Spotify desde NeoTube.
    return AtajosDeReproduccion(
      onPlayPause: () => unawaited(_alternar()),
      onNext: () => unawaited(_siguiente()),
      onPrevious: () => unawaited(_anterior()),
      child: _modos(),
    );
  }

  Widget _modos() {
    return ModeHost(
      neofy: AppShell(
        api: _api,
        auth: _auth,
        player: _player,
        likes: _likes,
        home: _home,
        carpetas: _carpetas,
        ram: _ram,
        settings: _settings,
        updater: _updater,
        onSalirParaActualizar: _quit,
        onReiniciarAudio: () =>
            _reiniciarAudio(porElUsuario: true, motivo: 'botón de Ajustes'),
        librespot: _librespot,
        sidecar: _sidecar,
        onReauth: _reauth,
        onToggleMode: _alternarModo,
        onLiberarRam: _liberarRamDelModoSaliente,
        onLogout: () async {
          await _sidecar.stop();
          await _librespot.stop();
          await _auth.logout();
          // Sin sesión no hay nada sonando: el panel del sistema tiene que
          // quedarse vacío, no con la última canción de la sesión anterior.
          await _smtc.stop();
          _sessionStarted = false;
          if (mounted) setState(() {});
        },
      ),
      neotube: NeoTubeShell(
        onToggleMode: _alternarModo,
        onLiberarRam: _liberarRamDelModoSaliente,
        auth: _ytAuth,
        api: _ytApi,
        player: _ytPlayer,
        // Las mismas piezas que recibe `AppShell`: Ajustes es un único
        // diálogo compartido, no una copia por modo.
        ram: _ram,
        settings: _settings,
        updater: _updater,
        onSalirParaActualizar: _quit,
        onLogout: () async {
          await _ytPlayer.stop();
          await _ytAuth.logout();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// El botón NeoFy/NeoTube de cualquiera de los dos shells llega aquí.
  void _alternarModo() {
    final destino =
        _settings.modo == AppMode.neofy ? AppMode.neotube : AppMode.neofy;
    unawaited(_settings.setModo(destino));
  }
}
