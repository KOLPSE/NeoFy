import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'home_store.dart';
import 'liked_store.dart';
import 'models.dart';
import 'spotify_api.dart';

/// Lo que hacía falta saber para dejar la música como estaba después de
/// reiniciar el sidecar de audio.
class ReproduccionEnCurso {
  const ReproduccionEnCurso({
    required this.sonaba,
    required this.posicionMs,
    required this.trackUri,
    required this.contextUri,
  });

  final bool sonaba;
  final int posicionMs;
  final String? trackUri;
  final String? contextUri;
}

/// Estado del reproductor y todas las acciones sobre él.
///
/// La pieza clave del bajo consumo está aquí: en vez de preguntarle a Spotify
/// la posición de la canción constantemente, se sondea cada pocos segundos y
/// **entre sondeos se interpola en local**. La barra de progreso se mueve sola
/// sin gastar ni una petición, y el sondeo baja a un goteo cuando la ventana
/// está oculta o la música parada.
class PlayerController extends ChangeNotifier {
  PlayerController(this.api, this.config);

  final SpotifyApi api;

  /// Hace falta para recordar el volumen entre sesiones: el que el usuario deja
  /// puesto es el que arranca librespot la próxima vez.
  final AppConfig config;

  Playback state = Playback.empty;
  String? ourDeviceId;
  String? lastError;
  bool premiumChecked = false;
  bool isPremium = true;

  /// Id de la cuenta. Hace falta para construir el contexto de "Canciones que
  /// te gustan", que se forma con el id del usuario.
  String? currentUserId;

  /// Última lista que se puso a sonar.
  ///
  /// Hace falta guardarla aparte porque cuando la reproducción se acaba del
  /// todo `GET /me/player` contesta 204 y el estado se queda vacío: sin esto,
  /// al llegar al final de la lista se pierde de qué lista se trataba y ya no
  /// hay forma de volver a empezarla. También cubre el contexto de "Canciones
  /// que te gustan", que la API no devuelve nunca.
  String? _lastContextUri;

  /// Última lista suelta de canciones que se puso a sonar (ver [playLista]).
  ///
  /// Va aparte de [_lastContextUri] porque no es un contexto: no tiene uri, no
  /// se puede pedir por `context_uri` y `GET /me/player` no la devuelve. Sin
  /// guardarla, al acabar la última canción de una tira de la portada no habría
  /// forma de volver a empezarla.
  List<String>? _lastUris;

  /// El contexto que suena, o el último que sonó si ya no suena nada.
  String? get contextUri => state.contextUri ?? _lastContextUri;

  /// Posición interpolada, en ms. Va aparte del resto del estado para que la
  /// barra de progreso se repinte sola sin arrastrar a toda la pantalla.
  final ValueNotifier<int> progressMs = ValueNotifier(0);

  /// Uri de lo que suena, en su propio notificador.
  ///
  /// Las listas lo escuchan para mover el título verde de una canción a la
  /// siguiente. Va aparte del `ChangeNotifier` general porque ese salta en cada
  /// sondeo (cada 3 s) y repintaría las listas sin que hubiera cambiado nada;
  /// esto solo salta cuando cambia la canción de verdad.
  final ValueNotifier<String?> currentUri = ValueNotifier(null);

  bool _windowVisible = true;
  Timer? _pollTimer;
  Timer? _tickTimer;
  DateTime _lastSync = DateTime.now();
  int _lastSyncedProgress = 0;
  bool _polling = false;
  bool _disposed = false;

  // Cambios que acabamos de pedir y que Spotify puede tardar un par de segundos
  // en reflejar. Mientras estén pendientes, el sondeo NO los pisa: si no, subes
  // el volumen y a los 3 segundos vuelve solo al valor anterior, o saltas hacia
  // delante y la barra retrocede antes de avanzar.
  static const _ventanaPendiente = Duration(seconds: 5);

  int? _pendingVolume;
  DateTime _pendingVolumeAt = DateTime.fromMillisecondsSinceEpoch(0);

  int? _pendingSeekMs;
  DateTime _pendingSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    _tickTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _schedulePoll(const Duration(milliseconds: 200));
  }

  /// La ventana minimizada a la bandeja no necesita datos frescos: se pasa a
  /// sondear cada 30 s en vez de cada 3.
  void setWindowVisible(bool visible) {
    if (_windowVisible == visible) return;
    _windowVisible = visible;
    if (visible) _schedulePoll(Duration.zero);
  }

  Duration get _pollInterval {
    // Con la cuota agotada, sondear cada 3 s son 1.200 peticiones a la hora que
    // no van a contestar y que mantienen viva la penalización. Se comprueba de
    // vez en cuando por si se levanta antes de lo dicho, y nada más.
    final espera = api.esperaDe('/me/player');
    if (espera != null) {
      return espera < const Duration(minutes: 1)
          ? espera + const Duration(seconds: 2)
          : const Duration(minutes: 1);
    }
    if (!_windowVisible) return const Duration(seconds: 30);
    if (!state.isPlaying) return const Duration(seconds: 15);
    return const Duration(seconds: 3);
  }

  void _schedulePoll(Duration d) {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(d, _poll);
  }

  Future<void> _poll() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final pb = await api.playbackState();
      if (_disposed) return;
      var next = pb ?? Playback.empty;

      // Si ha cambiado la canción, cualquier salto pendiente ya no aplica.
      if (next.track?.uri != state.track?.uri) _pendingSeekMs = null;

      next = _conservarVolumenPendiente(next);
      final aceptarProgreso = _aceptarProgresoDelServidor(next);

      // Un 204 (nada sonando) no borra la lista: es justo cuando más falta
      // hace saber cuál era, para poder volver a arrancarla.
      if (next.contextUri != null) _lastContextUri = next.contextUri;

      state = next;
      currentUri.value = next.track?.uri;
      if (aceptarProgreso) {
        _lastSyncedProgress = next.progressMs;
        _lastSync = DateTime.now();
        progressMs.value = next.progressMs;
      }
      lastError = null;
      notifyListeners();
    } catch (e) {
      if (!_disposed) {
        lastError = '$e';
        notifyListeners();
      }
    } finally {
      _polling = false;
      _schedulePoll(_pollInterval);
    }
  }

  /// Mantiene el volumen que pidió el usuario hasta que el servidor lo
  /// confirme o se agote la ventana. Sin esto, el sondeo devuelve el valor
  /// viejo y el slider salta hacia atrás solo.
  Playback _conservarVolumenPendiente(Playback next) {
    final pedido = _pendingVolume;
    if (pedido == null) return next;
    final caducado = DateTime.now().difference(_pendingVolumeAt) > _ventanaPendiente;
    if (caducado || next.volumePercent == pedido) {
      _pendingVolume = null;
      return next;
    }
    return next.copyWith(volumePercent: pedido);
  }

  /// ¿Nos creemos la posición que dice el servidor?
  ///
  /// Tras un salto, Spotify tarda un poco en aplicarlo y durante ese rato
  /// sigue informando de la posición anterior. Aceptarla haría que la barra
  /// retrocediera al punto de partida antes de saltar de verdad.
  bool _aceptarProgresoDelServidor(Playback next) {
    final objetivo = _pendingSeekMs;
    if (objetivo == null) return true;

    final desde = DateTime.now().difference(_pendingSeekAt);
    if (desde > _ventanaPendiente) {
      _pendingSeekMs = null;
      return true;
    }
    // Donde debería estar ya, contando lo que lleva sonando desde el salto.
    final esperado = objetivo + (next.isPlaying ? desde.inMilliseconds : 0);
    if ((next.progressMs - esperado).abs() < 3000) {
      _pendingSeekMs = null;
      return true;
    }
    return false;
  }

  /// Avanza la posición en local entre sondeos.
  void _tick() {
    if (!state.isPlaying || state.track == null) return;
    final elapsed = DateTime.now().difference(_lastSync).inMilliseconds;
    final next = _lastSyncedProgress + elapsed;
    progressMs.value = next.clamp(0, state.track!.durationMs);
  }

  // ------------------------------------------------------------- dispositivo

  /// Localiza el dispositivo de librespot por nombre y le pasa la reproducción.
  ///
  /// Se llama al arrancar y cada vez que la API responde "device not found",
  /// que es lo que pasa cuando el sidecar se ha reiniciado y tiene un id nuevo.
  /// [distintoDe] sirve para el reinicio del audio: durante unos segundos
  /// Spotify sigue listando el dispositivo del librespot que acabamos de matar,
  /// y quedarse con ese id significaría mandar la música a un proceso muerto.
  Future<bool> resolveDevice({bool transfer = true, String? distintoDe}) async {
    try {
      final list = await api.devices();
      final ours = list
          .where((d) => d.name == kDeviceName && d.id != distintoDe)
          .toList();
      if (ours.isEmpty) return false;
      ourDeviceId = ours.first.id;
      if (transfer && !ours.first.isActive) {
        await api.transfer(ourDeviceId!, play: false);
      }
      return true;
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
  }

  /// Olvida el dispositivo actual. Se llama justo antes de reiniciar el
  /// sidecar: el id que tenemos ya no vale, y mientras no haya otro la barra
  /// de reproducción avisa de que se está buscando el reproductor.
  String? olvidarDispositivo() {
    final anterior = ourDeviceId;
    ourDeviceId = null;
    notifyListeners();
    return anterior;
  }

  /// Foto de lo que suena, para poder dejarlo igual tras reiniciar el audio.
  ReproduccionEnCurso instantanea() => ReproduccionEnCurso(
        sonaba: state.isPlaying,
        posicionMs: progressMs.value,
        trackUri: state.track?.uri,
        contextUri: contextUri,
      );

  /// Vuelve a poner lo que sonaba en el librespot recién arrancado.
  ///
  /// Basta con traspasar la reproducción: el estado vive en la **sesión** de
  /// Spotify, no en el dispositivo — es la misma razón por la que abrir la app
  /// reanudaba la música sola. Lo que no se recupera solo es la posición: con
  /// el dispositivo muerto se queda clavada donde se cortó, o sigue corriendo
  /// sin que suene nada, así que se manda el salto aparte.
  Future<void> retomar(ReproduccionEnCurso antes) async {
    final device = ourDeviceId;
    if (device == null) return;
    try {
      await api.transfer(device, play: antes.sonaba);
      if (antes.sonaba) {
        await api.seek(antes.posicionMs);
        _pendingSeekMs = antes.posicionMs;
        _pendingSeekAt = DateTime.now();
      }
      state = state.copyWith(isPlaying: antes.sonaba);
      lastError = null;
      notifyListeners();
    } catch (_) {
      await _arrancarDeNuevo(antes);
    }
    _schedulePoll(const Duration(milliseconds: 500));
  }

  /// Plan B cuando el traspaso no cuaja: arrancar la reproducción a mano.
  ///
  /// Pasa cuando la sesión de Spotify se dio por terminada mientras el
  /// dispositivo no existía. Con contexto se vuelve a él apuntando a la canción
  /// concreta, para no perder la lista; sin contexto, la canción suelta.
  Future<void> _arrancarDeNuevo(ReproduccionEnCurso antes) async {
    if (!antes.sonaba || antes.trackUri == null) return;
    try {
      await api.play(
        deviceId: ourDeviceId,
        contextUri: antes.contextUri,
        uris: antes.contextUri == null ? [antes.trackUri!] : null,
        offsetUri: antes.contextUri == null ? null : antes.trackUri,
        positionMs: antes.posicionMs,
      );
      lastError = null;
    } catch (e) {
      lastError = 'No se pudo retomar la reproducción tras reiniciar el '
          'audio: $e';
    }
    notifyListeners();
  }

  /// Deja la reproducción parada al arrancar la app.
  ///
  /// Spotify guarda el estado de la **sesión**, no el del dispositivo: si la
  /// app se cerró sonando, al transferir la reproducción a librespot recién
  /// arrancado la reanuda sola. Abrir la app y que empiece a sonar sin haberle
  /// dado a nada no lo espera nadie.
  Future<void> ensurePausedAtStartup() async {
    try {
      final pb = await api.playbackState();
      if (pb == null || !pb.isPlaying) return;
      await api.pause();
      state = pb.copyWith(isPlaying: false);
      currentUri.value = pb.track?.uri;
      progressMs.value = pb.progressMs;
      _lastSyncedProgress = pb.progressMs;
      _lastSync = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Si falla, el sondeo normal enseñará lo que haya. No es motivo para
      // entorpecer el arranque.
    }
  }

  /// Ejecuta una acción y, si el dispositivo se ha esfumado, lo vuelve a
  /// resolver y lo intenta una segunda vez.
  ///
  /// [siProhibido] es la salida para los 403 de "acción no permitida en este
  /// estado": si devuelve true, se da el 403 por resuelto y no se enseña error.
  ///
  /// Devuelve `true` solo si la acción se ejecutó tal cual. Un 403 resuelto por
  /// [siProhibido] devuelve `false`: la salida de emergencia ya hizo lo suyo y
  /// quien llamó no debe encadenar nada más encima.
  Future<bool> _withDevice(
    Future<void> Function() action, {
    Future<bool> Function()? siProhibido,
  }) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (e.isDeviceNotFound && await resolveDevice()) {
        try {
          await action();
        } catch (e2) {
          lastError = '$e2';
          notifyListeners();
          return false;
        }
      } else if (e.isForbidden && siProhibido != null && await siProhibido()) {
        return false;
      } else {
        lastError = e.isForbidden
            ? 'Spotify rechazó la acción. Suele ser que la cuenta no es Premium '
                'o que no se puede saltar en este contexto.'
            : '$e';
        notifyListeners();
        return false;
      }
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
    // Confirmar pronto: el estado optimista que acabamos de pintar puede no
    // coincidir con lo que Spotify hizo realmente.
    _schedulePoll(const Duration(milliseconds: 500));
    return true;
  }

  // ---------------------------------------------------------------- acciones

  Future<void> togglePlay() async {
    // Si la reproducción se terminó del todo, no hay nada que reanudar: un
    // `play` pelado no arranca nada y el botón se queda mudo. Se vuelve a
    // poner la última lista desde el principio.
    if (!state.isPlaying && state.track == null && await _volverAlPrincipio()) {
      return;
    }

    final wasPlaying = state.isPlaying;
    // Pintado optimista: el botón responde al instante y el siguiente sondeo
    // corrige si Spotify no hizo lo que esperábamos.
    state = state.copyWith(isPlaying: !wasPlaying);
    if (!wasPlaying) {
      _lastSync = DateTime.now();
      _lastSyncedProgress = progressMs.value;
    }
    notifyListeners();
    await _withDevice(() => wasPlaying ? api.pause() : api.play(deviceId: ourDeviceId));
  }

  /// Pausa sin alternar. La tecla "stop" de los cascos y del teclado
  /// multimedia para, no alterna: darle dos veces no debe reanudar.
  Future<void> pause() async {
    if (!state.isPlaying) return;
    state = state.copyWith(isPlaying: false);
    notifyListeners();
    await _withDevice(api.pause);
  }

  /// Siguiente canción, **dando la vuelta al llegar al final**.
  ///
  /// Spotify no la da: en la última canción con la repetición apagada, `next`
  /// no vuelve a la primera. O lo rechaza con un 403, o —lo que pasa con
  /// librespot— para la reproducción y deja el dispositivo inactivo, con lo
  /// que a partir de ahí no suena nada y ni el botón de play lo arregla.
  ///
  /// Se detecta por las dos vías, porque cuál de las dos ocurre depende del
  /// contexto: `canSkipNext` antes de pedirlo, y el 403 después.
  Future<void> next() async {
    final sinSiguiente = !state.canSkipNext || state.track == null;
    if (sinSiguiente && await _volverAlPrincipio()) return;

    progressMs.value = 0;
    if (await _withDevice(api.next, siProhibido: _volverAlPrincipio)) {
      await _reanudarTrasSaltar();
    }
  }

  Future<void> previous() async {
    // Igual que Spotify: si ya han pasado más de 3 s, "anterior" vuelve al
    // principio de la canción en vez de saltar a la de antes. Y en la primera
    // canción de la lista tampoco hay adónde ir: reiniciarla es lo que hace el
    // cliente oficial, y de paso evita el 403.
    if (progressMs.value > 3000 || !state.canSkipPrevious) {
      await seek(0);
      return;
    }
    progressMs.value = 0;
    if (await _withDevice(api.previous)) await _reanudarTrasSaltar();
  }

  /// Saltar de canción **no reanuda la reproducción**: Spotify conserva el
  /// estado de pausa y la siguiente se queda parada en el segundo 0. Quien le
  /// da a "siguiente" quiere oírla, así que se reanuda.
  Future<void> _reanudarTrasSaltar() async {
    if (state.isPlaying) return;
    state = state.copyWith(isPlaying: true);
    _lastSyncedProgress = 0;
    _lastSync = DateTime.now();
    notifyListeners();
    await _withDevice(() => api.play(deviceId: ourDeviceId));
  }

  /// Vuelve a poner desde el principio la lista que suena (o la última que
  /// sonó). Devuelve false si no hay lista que reiniciar —una canción suelta
  /// no tiene contexto—, para que quien llama siga con su plan B.
  ///
  /// Sirve para las dos formas de poner música: un contexto de Spotify (una
  /// playlist, un álbum, un artista) y una lista suelta de uris de [playLista].
  /// La segunda hay que reenviarla entera, porque no tiene uri por la que
  /// pedirla.
  Future<bool> _volverAlPrincipio() async {
    final ctx = contextUri;
    final uris = _lastUris;
    if (ctx == null && uris == null) return false;
    progressMs.value = 0;
    _lastSyncedProgress = 0;
    _lastSync = DateTime.now();
    await _withDevice(() => ctx != null
        ? api.play(
            deviceId: ourDeviceId,
            contextUri: ctx,
            offsetPosition: 0,
          )
        : api.play(
            deviceId: ourDeviceId,
            uris: uris,
            offsetPosition: 0,
          ));
    return true;
  }

  /// Se avisa cuando la posición **da un salto**.
  ///
  /// Es lo único que los reproductores del sistema —el widget de MPRIS en Linux
  /// y el panel multimedia en Windows— no pueden deducir solos: mientras la
  /// música avanza extrapolan la posición por su cuenta desde la última que se
  /// les dio, así que anunciarla cada pocos segundos sería trabajo para nada,
  /// pero sin este aviso un arrastre de la barra dentro de NeoFy los deja
  /// enseñando el minuto de antes hasta que cambie la canción.
  void Function(int ms)? onSalto;

  Future<void> seek(int ms) async {
    _pendingSeekMs = ms;
    _pendingSeekAt = DateTime.now();
    progressMs.value = ms;
    _lastSyncedProgress = ms;
    _lastSync = DateTime.now();
    onSalto?.call(ms);
    await _withDevice(() => api.seek(ms));
  }

  /// Volumen que debe enseñar la interfaz.
  ///
  /// Cuando no hay reproducción activa, `GET /me/player` no informa de ningún
  /// volumen. Antes se caía a un 50 fijo, y el síntoma era que al abrir la app
  /// la barra aparecía a la mitad sin que nadie la hubiera tocado. El respaldo
  /// correcto es el último volumen que puso el usuario, que además es con el
  /// que arranca librespot.
  int get volumeShown => state.volumePercent ?? config.initialVolume;

  Future<void> setVolume(int percent) async {
    final v = percent.clamp(0, 100);
    _pendingVolume = v;
    _pendingVolumeAt = DateTime.now();
    state = state.copyWith(volumePercent: v);
    notifyListeners();
    // Se recuerda en disco: librespot arranca con `--initial-volume`, así que
    // sin esto cada reinicio volvía al valor de fábrica.
    if (config.initialVolume != v) {
      config.initialVolume = v;
      unawaited(config.save());
    }
    await _withDevice(() => api.setVolume(v));
  }

  /// Calcula 3 offsets estratificados no solapados para muestrear la biblioteca
  /// en tres bandas independientes (reciente, media y antigua), garantizando
  /// acceso completo hasta la última canción sin privilegiar la cabecera.
  static List<int> calcularOffsetsEstratificados(
    int total, {
    Random? random,
    int tamanoVentana = 25,
  }) {
    if (total <= 0) return const [0];
    final maxOffset = (total - tamanoVentana).clamp(0, total);
    if (maxOffset == 0) return const [0];

    final rand = random ?? Random();

    final b0Min = 0;
    final b0Max = (maxOffset / 3).floor();

    final b1Min = (b0Max + 1).clamp(0, maxOffset);
    final b1Max = ((2 * maxOffset) / 3).floor().clamp(b1Min, maxOffset);

    final b2Min = (b1Max + 1).clamp(0, maxOffset);
    final b2Max = maxOffset;

    int randRango(int min, int max) {
      if (min >= max) return min;
      return min + rand.nextInt(max - min + 1);
    }

    return [
      randRango(b0Min, b0Max),
      randRango(b1Min, b1Max),
      randRango(b2Min, b2Max),
    ];
  }

  /// Máximo número de canciones de 'top tracks' (más escuchadas) que aportan a la bolsa de conocidas.
  static const int kMaxPistasTopEnAleatorio = 10;

  /// Proporción de canciones conocidas frente a recomendadas en el modo 'Aleatorio inteligente' (~60% conocidas / 40% nuevas).
  static const double kProporcionConocidasModoInteligente = 0.60;

  bool _aleatorioInteligente = false;

  /// ¿Está activo el modo aleatorio inteligente?
  bool get esAleatorioInteligente => _aleatorioInteligente;

  /// Modo aleatorio activo (apagado / estándar / inteligente).
  ModoAleatorio get modoAleatorio {
    if (_aleatorioInteligente) return ModoAleatorio.inteligente;
    if (state.shuffle) return ModoAleatorio.estandar;
    return ModoAleatorio.apagado;
  }

  /// Alterna entre los tres modos de aleatorio: apagado -> estándar -> inteligente -> apagado.
  Future<void> ciclarModoAleatorio({LikedStore? likes, HomeStore? home}) async {
    switch (modoAleatorio) {
      case ModoAleatorio.apagado:
        // Apagado -> Estándar
        _aleatorioInteligente = false;
        state = state.copyWith(shuffle: true);
        notifyListeners();
        await _withDevice(() => api.setShuffle(true));
        break;

      case ModoAleatorio.estandar:
        // Estándar -> Inteligente
        state = state.copyWith(shuffle: false);
        _aleatorioInteligente = true;
        notifyListeners();
        await _withDevice(() => api.setShuffle(false));
        await activarAleatorioInteligente(likes: likes, home: home);
        break;

      case ModoAleatorio.inteligente:
        // Inteligente -> Apagado
        _aleatorioInteligente = false;
        state = state.copyWith(shuffle: false);
        notifyListeners();
        await _withDevice(() => api.setShuffle(false));
        break;
    }
  }

  /// Construye y reproduce una cola mezclada de canciones conocidas (~60%)
  /// y canciones nuevas recomendadas de sus artistas top (~40%).
  Future<void> activarAleatorioInteligente({LikedStore? likes, HomeStore? home}) async {
    try {
      final urisConocidas = <String>{};
      final pistasConocidas = <String>[];
      final pistasNuevas = <String>[];
      final urisRecientesExcluidas = <String>{};

      // 0. Recolectar canciones recientes para EXCLUSIÓN (no volver a sonar lo recién escuchado)
      if (home != null && home.cargado) {
        for (final t in home.recientes) {
          if (t.uri.isNotEmpty) urisRecientesExcluidas.add(t.uri);
        }
      } else {
        try {
          final rec = await api.recentlyPlayed(limit: 20);
          for (final t in rec) {
            if (t.uri.isNotEmpty) urisRecientesExcluidas.add(t.uri);
          }
        } catch (_) {}
      }

      // 1. Canciones conocidas: lista actual, biblioteca completa (o muestreo por offset) y top acotado
      if (_lastUris != null && _lastUris!.isNotEmpty) {
        for (final u in _lastUris!) {
          if (u.isNotEmpty && !urisRecientesExcluidas.contains(u) && urisConocidas.add(u)) {
            pistasConocidas.add(u);
          }
        }
      }
      if (state.track?.uri != null && state.track!.uri.isNotEmpty) {
        urisConocidas.add(state.track!.uri);
      }

      // Biblioteca: si está totalmente cargada en LikedStore, usar esa. Si no, realizar
      // muestreo por offsets aleatorios a lo largo de toda la biblioteca en Spotify.
      if (likes != null && likes.bibliotecaCompleta && likes.biblioteca.isNotEmpty) {
        for (final t in likes.biblioteca) {
          if (t.uri.isNotEmpty && !urisRecientesExcluidas.contains(t.uri) && urisConocidas.add(t.uri)) {
            pistasConocidas.add(t.uri);
          }
        }
      } else {
        try {
          final primerPagina = await api.savedTracks(limit: 1, offset: 0);
          final total = primerPagina.total ?? primerPagina.rawCount;
          if (total > 0) {
            final paginasGuardadas = <ApiPage<Track>>[];
            if (total <= 50) {
              paginasGuardadas.add(await api.savedTracks(limit: 50, offset: 0));
            } else {
              final offsets = calcularOffsetsEstratificados(total, tamanoVentana: 25);
              const paginaVacia = ApiPage<Track>(items: [], hasMore: false, rawCount: 0);
              paginasGuardadas.addAll(await Future.wait([
                api.savedTracks(limit: 25, offset: offsets[0]).catchError((_) => paginaVacia),
                api.savedTracks(limit: 25, offset: offsets[1]).catchError((_) => paginaVacia),
                api.savedTracks(limit: 25, offset: offsets[2]).catchError((_) => paginaVacia),
              ]));
            }
            for (final pag in paginasGuardadas) {
              for (final t in pag.items) {
                if (t.uri.isNotEmpty && !urisRecientesExcluidas.contains(t.uri) && urisConocidas.add(t.uri)) {
                  pistasConocidas.add(t.uri);
                }
              }
            }
          }
        } catch (_) {}
      }

      // Top canciones del usuario (acotadas por kMaxPistasTopEnAleatorio)
      List<Track> topPistas = const [];
      if (home != null && home.cargado) {
        topPistas = home.masEscuchadas.take(kMaxPistasTopEnAleatorio).toList();
      } else {
        try {
          topPistas = await api.topTracks(limit: kMaxPistasTopEnAleatorio);
        } catch (_) {}
      }
      for (final t in topPistas) {
        if (t.uri.isNotEmpty && !urisRecientesExcluidas.contains(t.uri) && urisConocidas.add(t.uri)) {
          pistasConocidas.add(t.uri);
        }
      }

      // 2. Canciones nuevas: top tracks de sus artistas top (descartando las que ya conoce o escuchó recientemente)
      List<Artist> artistasTop = const [];
      if (home != null && home.artistas.isNotEmpty) {
        artistasTop = home.artistas;
      } else {
        try {
          artistasTop = await api.topArtists(limit: 20);
        } catch (_) {}
      }

      if (artistasTop.isNotEmpty) {
        final artistasBase = artistasTop.take(8).toList();
        final listasPistasArtista = await Future.wait([
          for (final a in artistasBase)
            api.artistTopTracks(a.id).catchError((_) => const <Track>[]),
        ]);
        final vistasNuevas = <String>{};
        for (final lista in listasPistasArtista) {
          for (final t in lista) {
            if (t.uri.isEmpty || urisConocidas.contains(t.uri) || urisRecientesExcluidas.contains(t.uri)) continue;
            if (vistasNuevas.add(t.uri)) {
              pistasNuevas.add(t.uri);
            }
          }
        }
      }

      // 3. Mezcla respetando kProporcionConocidasModoInteligente (~60/40)
      const totalObjetivo = 40;
      var cantidadConocidasObjetivo =
          (totalObjetivo * kProporcionConocidasModoInteligente).round();
      var cantidadNuevasObjetivo = totalObjetivo - cantidadConocidasObjetivo;

      final conocidasBarajadas = List<String>.from(pistasConocidas)..shuffle();
      final nuevasBarajadas = List<String>.from(pistasNuevas)..shuffle();

      if (nuevasBarajadas.length < cantidadNuevasObjetivo) {
        cantidadNuevasObjetivo = nuevasBarajadas.length;
        cantidadConocidasObjetivo = (totalObjetivo - cantidadNuevasObjetivo)
            .clamp(0, conocidasBarajadas.length);
      } else if (conocidasBarajadas.length < cantidadConocidasObjetivo) {
        cantidadConocidasObjetivo = conocidasBarajadas.length;
        cantidadNuevasObjetivo =
            (totalObjetivo - cantidadConocidasObjetivo).clamp(0, nuevasBarajadas.length);
      }

      final conocidasSeleccionadas =
          conocidasBarajadas.take(cantidadConocidasObjetivo).toList();
      final nuevasSeleccionadas =
          nuevasBarajadas.take(cantidadNuevasObjetivo).toList();

      final uriPistaActual = state.track?.uri;
      final colaFinal = <String>[];

      // Si hay una canción sonando actualmente, la dejamos al principio para no perder
      // el contexto, pero recordando su posición actual en ms (posicionMs) para que
      // Spotify no la reinicie desde el segundo cero.
      final int? posicionActualMs =
          (uriPistaActual != null && progressMs.value > 0) ? progressMs.value : null;

      if (uriPistaActual != null && uriPistaActual.isNotEmpty) {
        colaFinal.add(uriPistaActual);
        conocidasSeleccionadas.remove(uriPistaActual);
        nuevasSeleccionadas.remove(uriPistaActual);
      }

      // El patrón de intercalado (pasoConocidas y pasoNuevas) se calcula dinámicamente
      // según kProporcionConocidasModoInteligente (p. ej. 0.60 -> 6 conocidas / 4 nuevas -> 3:2).
      int mcd(int a, int b) => b == 0 ? a : mcd(b, a % b);
      final numConocidas = (kProporcionConocidasModoInteligente * 10).round().clamp(1, 9);
      final numNuevas = 10 - numConocidas;
      final divisorComun = mcd(numConocidas, numNuevas);
      final pasoConocidas = numConocidas ~/ divisorComun;
      final pasoNuevas = numNuevas ~/ divisorComun;

      var i = 0, j = 0;
      while (i < conocidasSeleccionadas.length || j < nuevasSeleccionadas.length) {
        for (var k = 0; k < pasoConocidas && i < conocidasSeleccionadas.length; k++) {
          if (!colaFinal.contains(conocidasSeleccionadas[i])) {
            colaFinal.add(conocidasSeleccionadas[i]);
          }
          i++;
        }
        for (var k = 0; k < pasoNuevas && j < nuevasSeleccionadas.length; k++) {
          if (!colaFinal.contains(nuevasSeleccionadas[j])) {
            colaFinal.add(nuevasSeleccionadas[j]);
          }
          j++;
        }
      }

      if (colaFinal.isEmpty) {
        _aleatorioInteligente = false;
        notifyListeners();
        return;
      }

      await playLista(
        colaFinal,
        desde: 0,
        esInteligente: true,
        posicionMs: posicionActualMs,
      );
    } catch (_) {
      // Si la red o la API fallan (o la cuenta no tiene artistas top), la cola no
      // se puede armar. Se desactiva el aleatorio inteligente y se notifica a la
      // interfaz para que el estado refleje la realidad en lugar de mentir.
      _aleatorioInteligente = false;
      notifyListeners();
    }
  }

  Future<void> cycleRepeat() async {
    const order = ['off', 'context', 'track'];
    final next = order[(order.indexOf(state.repeat) + 1) % order.length];
    state = state.copyWith(repeat: next);
    notifyListeners();
    await _withDevice(() => api.setRepeat(next));
  }

  Future<void> playContext(String contextUri, {int? offset}) {
    // Se apunta aquí y no solo en el sondeo porque el contexto de "Canciones
    // que te gustan" no lo devuelve `GET /me/player`: si no lo guardáramos al
    // pedirlo, no habría manera de saber que era esa lista.
    _aleatorioInteligente = false;
    _lastContextUri = contextUri;
    _lastUris = null;
    return _withDevice(() => api.play(
          deviceId: ourDeviceId,
          contextUri: contextUri,
          offsetPosition: offset,
        ));
  }

  /// Pone a sonar una lista de canciones suelta —una tira de la portada, por
  /// ejemplo— empezando por la de la posición [desde].
  ///
  /// ⚠️ **No es lo mismo que llamar a [playTrack] con la canción pulsada**, y
  /// la diferencia solo se nota al darle a "siguiente". Una canción suelta no
  /// tiene nada detrás: Spotify marca el salto como prohibido, [next] intenta
  /// entonces reiniciar la lista que sonaba, no hay ninguna, y el único efecto
  /// visible es que **la misma canción vuelve a empezar**. Mandando la tira
  /// entera sí hay por dónde seguir.
  ///
  /// Se pide la posición y no la uri porque una lista puede traer repetidos:
  /// en "Vuelve a escuchar" es de lo más normal que la misma canción salga dos
  /// veces, y buscarla por uri empezaría siempre por la primera aparición.
  Future<void> playLista(
    List<String> uris, {
    int desde = 0,
    bool esInteligente = false,
    int? posicionMs,
  }) {
    // Estas listas no son un contexto de Spotify —no tienen uri propia— y
    // `GET /me/player` no las devuelve, así que hay que guardarlas aquí o al
    // llegar al final no habría manera de saber qué se estaba escuchando. Es
    // exactamente la misma razón por la que existe `_lastContextUri`.
    if (!esInteligente) {
      _aleatorioInteligente = false;
    }
    _lastContextUri = null;
    _lastUris = List.unmodifiable(uris);
    return _withDevice(() => api.play(
          deviceId: ourDeviceId,
          uris: uris,
          offsetPosition: desde,
          positionMs: posicionMs,
        ));
  }

  Future<void> playTrack(String uri) {
    // Una canción suelta no es una lista: al acabar no hay adónde volver.
    _aleatorioInteligente = false;
    _lastContextUri = null;
    _lastUris = null;
    return _withDevice(() => api.play(deviceId: ourDeviceId, uris: [uri]));
  }

  Future<void> addToQueue(String uri) => _withDevice(() => api.addToQueue(uri));

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    progressMs.dispose();
    currentUri.dispose();
    super.dispose();
  }
}
