import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
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
  Future<bool> _volverAlPrincipio() async {
    final ctx = contextUri;
    if (ctx == null) return false;
    progressMs.value = 0;
    _lastSyncedProgress = 0;
    _lastSync = DateTime.now();
    await _withDevice(() => api.play(
          deviceId: ourDeviceId,
          contextUri: ctx,
          offsetPosition: 0,
        ));
    return true;
  }

  Future<void> seek(int ms) async {
    _pendingSeekMs = ms;
    _pendingSeekAt = DateTime.now();
    progressMs.value = ms;
    _lastSyncedProgress = ms;
    _lastSync = DateTime.now();
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

  Future<void> toggleShuffle() async {
    final next = !state.shuffle;
    state = state.copyWith(shuffle: next);
    notifyListeners();
    await _withDevice(() => api.setShuffle(next));
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
    _lastContextUri = contextUri;
    return _withDevice(() => api.play(
          deviceId: ourDeviceId,
          contextUri: contextUri,
          offsetPosition: offset,
        ));
  }

  Future<void> playTrack(String uri) {
    // Una canción suelta no es una lista: al acabar no hay adónde volver.
    _lastContextUri = null;
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
