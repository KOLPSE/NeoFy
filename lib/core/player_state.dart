import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'home_store.dart';
import 'liked_store.dart';
import 'models.dart';
import 'reproduccion_libre.dart';
import 'spotify_api.dart';
import 'ultima_reproduccion.dart';
import 'volumen_local.dart';

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

class PlayerController extends ChangeNotifier {
  PlayerController(this.api, this.config, {VolumenLocal? volumenLocal})
      : _volumenLocal = volumenLocal ?? VolumenLocal();

  final SpotifyApi api;

  final AppConfig config;

  final VolumenLocal _volumenLocal;

  Playback state = Playback.empty;
  String? ourDeviceId;
  String? lastError;
  bool premiumChecked = false;
  bool isPremium = true;

  ReproduccionLibre? libre;

  String? currentUserId;
  String? currentDisplayName;

  void aplicarPerfilSpotify(Map<String, dynamic> perfil) {
    currentUserId = perfil['id'] is String ? perfil['id'] as String : null;
    currentDisplayName = perfil['display_name'] as String?;
    final producto = perfil['product'];
    final sinPremium = producto == 'free' || producto == 'open';
    premiumChecked = producto == 'premium' || sinPremium;
    isPremium = !sinPremium;
    notifyListeners();
  }

  void notificar() => notifyListeners();

  String? _lastContextUri;

  List<String>? _lastUris;

  bool _colaLocalActiva = false;
  int _indiceColaLocal = 0;
  String? _albumDeRespaldoActual;
  bool _avanzandoColaLocal = false;

  String? get contextUri => state.contextUri ?? _lastContextUri;

  final ValueNotifier<int> progressMs = ValueNotifier(0);

  int get posicionActualMs {
    final alternativa = libre;
    if (alternativa != null) return alternativa.posicionActualMs;
    final pista = state.track;
    final anclaje = _ultimoAnclajeMs;
    if (!state.isPlaying || pista == null || anclaje == null) {
      return progressMs.value;
    }
    final transcurrido = _relojDePosicion.elapsedMilliseconds - anclaje;
    return (_lastSyncedProgress + transcurrido).clamp(0, pista.durationMs);
  }

  final ValueNotifier<String?> currentUri = ValueNotifier(null);

  bool _windowVisible = true;
  Timer? _pollTimer;
  Timer? _tickTimer;
  final Stopwatch _relojDePosicion = Stopwatch()..start();
  int? _ultimoAnclajeMs;
  int _lastSyncedProgress = 0;
  int _revisionPosicion = 0;
  bool _polling = false;
  bool _disposed = false;

  static const _ventanaPendiente = Duration(seconds: 5);

  int? _pendingVolume;
  DateTime _pendingVolumeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _volumenAntesDeMutear;
  Timer? _reintentoVolumen;

  int? _pendingSeekMs;
  int _inicioSaltoMs = 0;

  String? _uriDeArranque;
  DateTime? _arranqueLocal;
  bool _yaCorregiArranque = false;

  UltimaReproduccion? _porRetomar;

  bool get hayAlgoPorRetomar => _porRetomar != null;

  void _fijarPosicion(int ms) {
    _lastSyncedProgress = ms;
    _ultimoAnclajeMs = _relojDePosicion.elapsedMilliseconds;
    progressMs.value = ms;
  }

  void restaurar(UltimaReproduccion ultima) {
    if (state.track != null) return;
    _porRetomar = ultima;
    _lastContextUri = ultima.contextUri;
    _lastUris = ultima.uris;
    state = Playback(
      track: ultima.track,
      isPlaying: false,
      progressMs: ultima.posicionMs,
      deviceId: null,
      deviceName: null,
      volumePercent: state.volumePercent,
      shuffle: false,
      repeat: 'off',
      contextUri: ultima.contextUri,
    );
    currentUri.value = ultima.track.uri;
    _fijarPosicion(ultima.posicionMs);
    notifyListeners();
  }

  UltimaReproduccion? paraRecordar() {
    final t = state.track;
    if (t == null || t.uri.isEmpty) return _porRetomar;
    return UltimaReproduccion(
      track: t,
      posicionMs: progressMs.value,
      contextUri: contextUri,
      uris: UltimaReproduccion.colaDesde(_lastUris, t.uri),
    );
  }

  Future<void> _retomarGuardada(UltimaReproduccion ultima) async {
    _revisionPosicion++;
    final enLibre = libre;
    if (enLibre != null) {
      _porRetomar = null;
      final uris = ultima.uris;
      if (uris != null && uris.isNotEmpty) {
        await enLibre.playLista(uris);
      } else {
        await enLibre.playTrack(ultima.track.uri);
      }
      if (ultima.posicionMs > 0) await enLibre.saltar(ultima.posicionMs);
      return;
    }

    if (ourDeviceId == null) await resolveDevice();

    state = state.copyWith(isPlaying: true);
    _fijarPosicion(ultima.posicionMs);
    notifyListeners();

    final cola = ultima.uris;
    final ok = await _withDevice(() => ultima.contextUri == null
        ? _reproducirUris(
            cola != null && cola.isNotEmpty ? cola : [ultima.track.uri],
            posicionMs: ultima.posicionMs,
          )
        : api.play(
            deviceId: ourDeviceId,
            contextUri: ultima.contextUri,
            offsetUri: ultima.track.uri,
            positionMs: ultima.posicionMs,
          ));

    if (ok) {
      _porRetomar = null;
    } else {
      state = state.copyWith(isPlaying: false);
      notifyListeners();
    }
  }

  void start() {
    _tickTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _schedulePoll(const Duration(milliseconds: 200));
    _aplicarVolumenAlAudio(volumeShown);
  }

  void setWindowVisible(bool visible) {
    if (_windowVisible == visible) return;
    _windowVisible = visible;
    if (visible) _schedulePoll(Duration.zero);
  }

  Duration get _pollInterval {
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
    if (libre != null) {
      _pollTimer?.cancel();
      return;
    }
    if (_polling || _disposed) return;
    _polling = true;
    final revision = _revisionPosicion;
    try {
      final pb = await api.playbackState();
      if (_disposed || revision != _revisionPosicion) return;
      var next = pb ?? Playback.empty;

      if (next.track == null) {
        if (state.track != null) {
          _porRetomar = paraRecordar();
          if (state.isPlaying) {
            final posicion = posicionActualMs;
            state = state.copyWith(isPlaying: false);
            _fijarPosicion(posicion);
            notifyListeners();
          }
        }
        lastError = null;
        return;
      }
      _porRetomar = null;

      if (next.track?.uri != state.track?.uri) {
        if (_colaLocalActiva &&
            !_avanzandoColaLocal &&
            _lastUris != null &&
            _indiceColaLocal < _lastUris!.length) {
          final esperada = _lastUris![_indiceColaLocal];
          final contextoCambioExterno =
              _albumDeRespaldoActual != null &&
              next.contextUri != null &&
              next.contextUri != _albumDeRespaldoActual;
          if (contextoCambioExterno) {
            _colaLocalActiva = false;
            _albumDeRespaldoActual = null;
          } else if (state.track?.uri == esperada &&
              next.track?.uri != null &&
              next.track!.uri != esperada &&
              next.progressMs < 15000) {
            // La pista de la lista terminó y Spotify pasó a la siguiente del
            // álbum de respaldo: interceptamos y avanzamos en nuestra lista.
            unawaited(_avanzarColaLocalAutomatico());
            return;
          }
        }
        _pendingSeekMs = null;
        _yaCorregiArranque = false;
      }

      next = _conservarVolumenPendiente(next);
      final aceptarProgreso = _aceptarProgresoDelServidor(next);

      if (next.contextUri != null) _lastContextUri = next.contextUri;

      state = next;
      if (aceptarProgreso) _fijarPosicion(next.progressMs);
      currentUri.value = next.track?.uri;
      lastError = null;
      notifyListeners();
    } catch (e) {
      if (!_disposed && revision == _revisionPosicion) {
        lastError = '$e';
        notifyListeners();
      }
    } finally {
      _polling = false;
      _schedulePoll(revision == _revisionPosicion
          ? _pollInterval
          : const Duration(milliseconds: 500));
    }
  }

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

  bool _aceptarProgresoDelServidor(Playback next) {
    if (_esRearranqueEspurio(next)) {
      final ms = _progresoLocalDe(next);
      if (next.track?.uri != state.track?.uri) {
        _fijarPosicion(ms);
      }
      if (!_yaCorregiArranque) {
        _yaCorregiArranque = true;
        unawaited(seek(ms));
      }
      return false;
    }

    final objetivo = _pendingSeekMs;
    if (objetivo == null) return true;

    final desde = _relojDePosicion.elapsedMilliseconds - _inicioSaltoMs;
    if (desde > _ventanaPendiente.inMilliseconds) {
      _pendingSeekMs = null;
      return true;
    }
    final esperado = objetivo + (next.isPlaying ? desde : 0);
    if ((next.progressMs - esperado).abs() < 750) {
      _pendingSeekMs = null;
      return true;
    }
    return false;
  }

  int _progresoLocalDe(Playback next) {
    if (next.track?.uri == state.track?.uri) return posicionActualMs;
    if (next.track?.uri == _uriDeArranque && _arranqueLocal != null) {
      return DateTime.now().difference(_arranqueLocal!).inMilliseconds;
    }
    return 0;
  }

  bool _esRearranqueEspurio(Playback next) {
    if (_pendingSeekMs != null) return false;
    if (!next.isPlaying) return false;
    final uri = next.track?.uri;
    if (uri == null || uri.isEmpty) return false;

    final local = _progresoLocalDe(next);
    final duracion = next.track?.durationMs ?? 0;
    if (duracion > 0 && local > duracion - 2000) return false;
    return local >= 2000 && local <= 12000 && next.progressMs < 1500;
  }

  void _marcarArranque(String? uri) {
    _revisionPosicion++;
    _uriDeArranque = uri;
    _arranqueLocal = DateTime.now();
    _yaCorregiArranque = false;
  }

  void _tick() {
    if (libre != null || !state.isPlaying || state.track == null) return;
    progressMs.value = posicionActualMs;
  }

  Future<bool> resolveDevice({bool transfer = true, String? distintoDe}) async {
    if (libre != null) return false;
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

  String? olvidarDispositivo() {
    final anterior = ourDeviceId;
    ourDeviceId = null;
    notifyListeners();
    return anterior;
  }

  ReproduccionEnCurso instantanea() => ReproduccionEnCurso(
        sonaba: state.isPlaying,
        posicionMs: posicionActualMs,
        trackUri: state.track?.uri,
        contextUri: contextUri,
      );

  Future<void> retomar(ReproduccionEnCurso antes) async {
    final device = ourDeviceId;
    if (device == null) return;
    _revisionPosicion++;
    try {
      await api.transfer(device, play: antes.sonaba);
      if (antes.sonaba) {
        await api.seek(antes.posicionMs);
        _pendingSeekMs = antes.posicionMs;
        _inicioSaltoMs = _relojDePosicion.elapsedMilliseconds;
      }
      state = state.copyWith(isPlaying: antes.sonaba);
      _fijarPosicion(antes.posicionMs);
      lastError = null;
      notifyListeners();
    } catch (_) {
      await _arrancarDeNuevo(antes);
    }
    _schedulePoll(const Duration(milliseconds: 500));
  }

  Future<void> _arrancarDeNuevo(ReproduccionEnCurso antes) async {
    final uri = antes.trackUri;
    if (!antes.sonaba || uri == null) return;
    try {
      if (antes.contextUri == null) {
        await _reproducirUris([uri], posicionMs: antes.posicionMs);
      } else {
        await api.play(
          deviceId: ourDeviceId,
          contextUri: antes.contextUri,
          offsetUri: uri,
          positionMs: antes.posicionMs,
        );
      }
      lastError = null;
    } catch (e) {
      lastError = 'No se pudo retomar la reproducción tras reiniciar el '
          'audio: $e';
    }
    notifyListeners();
  }

  bool _mandoDelUsuario = false;

  Future<void> ensurePausedAtStartup() async {
    if (libre != null || _mandoDelUsuario) return;
    try {
      final pb = await api.playbackState();
      if (pb == null || !pb.isPlaying || _mandoDelUsuario || _disposed) return;
      final revision = ++_revisionPosicion;
      await api.pause();
      if (_disposed || revision != _revisionPosicion) return;
      state = pb.copyWith(isPlaying: false);
      _fijarPosicion(pb.progressMs);
      currentUri.value = pb.track?.uri;
      notifyListeners();
    } catch (_) {
    }
  }

  Future<bool> _withDevice(
    Future<void> Function() action, {
    Future<bool> Function()? siProhibido,
  }) async {
    if (libre != null) return false;
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
            ? 'Spotify rechazó la acción: ${e.message}'
            : '$e';
        notifyListeners();
        return false;
      }
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
    _schedulePoll(const Duration(milliseconds: 500));
    return true;
  }

  Future<void> togglePlay() async {
    _mandoDelUsuario = true;
    final guardada = _porRetomar;
    if (guardada != null && !state.isPlaying) return _retomarGuardada(guardada);
    if (libre != null) return libre!.alternar();
    if (!state.isPlaying && state.track == null && await _volverAlPrincipio()) {
      return;
    }

    await _cambiarPausaSpotify();
  }

  Future<void> pause() async {
    if (libre != null) return libre!.pause();
    if (!state.isPlaying) return;
    await _cambiarPausaSpotify();
  }

  Future<void> _cambiarPausaSpotify() async {
    final sonaba = state.isPlaying;
    final posicion = posicionActualMs;
    final inicio = _relojDePosicion.elapsedMilliseconds;
    final pista = state.track?.uri;
    final revision = ++_revisionPosicion;
    state = state.copyWith(isPlaying: !sonaba);
    _fijarPosicion(posicion);
    notifyListeners();
    final ok = await _withDevice(
      () => sonaba ? api.pause() : api.play(deviceId: ourDeviceId),
    );
    if (ok || _disposed || revision != _revisionPosicion ||
        state.track?.uri != pista) {
      return;
    }
    state = state.copyWith(isPlaying: sonaba);
    final delta = sonaba ? _relojDePosicion.elapsedMilliseconds - inicio : 0;
    _fijarPosicion((posicion + delta).clamp(0, state.track?.durationMs ?? posicion));
    notifyListeners();
    _schedulePoll(Duration.zero);
  }

  Future<void> next() async {
    _mandoDelUsuario = true;
    final guardada = _porRetomar;
    if (guardada != null) return _retomarGuardada(guardada);
    if (libre != null) return libre!.siguiente();
    if (_colaLocalActiva && _lastUris != null && _lastUris!.isNotEmpty) {
      await _saltarEnColaLocal(1);
      return;
    }
    final sinSiguiente = !state.canSkipNext || state.track == null;
    if (sinSiguiente && await _volverAlPrincipio()) return;

    _revisionPosicion++;
    _fijarPosicion(0);
    if (await _withDevice(api.next, siProhibido: _volverAlPrincipio)) {
      await _reanudarTrasSaltar();
    }
  }

  Future<void> previous() async {
    _mandoDelUsuario = true;
    final guardada = _porRetomar;
    if (guardada != null) return _retomarGuardada(guardada);
    if (libre != null) return libre!.anterior();
    if (_colaLocalActiva && _lastUris != null && _lastUris!.isNotEmpty) {
      if (progressMs.value > 3000) {
        await seek(0);
        return;
      }
      await _saltarEnColaLocal(-1);
      return;
    }
    if (progressMs.value > 3000 || !state.canSkipPrevious) {
      await seek(0);
      return;
    }
    _revisionPosicion++;
    _fijarPosicion(0);
    if (await _withDevice(api.previous)) await _reanudarTrasSaltar();
  }

  Future<void> _avanzarColaLocalAutomatico() async {
    if (_avanzandoColaLocal || !_colaLocalActiva) return;
    final uris = _lastUris;
    if (uris == null || uris.isEmpty) return;
    if (state.repeat == 'off' && _indiceColaLocal + 1 >= uris.length) {
      _colaLocalActiva = false;
      _albumDeRespaldoActual = null;
      await pause();
      return;
    }
    await _saltarEnColaLocal(1);
  }

  Future<void> _saltarEnColaLocal(int delta) async {
    final uris = _lastUris;
    if (uris == null || uris.isEmpty) return;
    _avanzandoColaLocal = true;
    try {
      final int siguiente;
      if (state.repeat == 'track') {
        siguiente = _indiceColaLocal.clamp(0, uris.length - 1);
      } else if (delta > 0) {
        siguiente = (_indiceColaLocal + delta) % uris.length;
      } else {
        siguiente = _indiceColaLocal > 0
            ? _indiceColaLocal - 1
            : (state.repeat == 'context' ? uris.length - 1 : 0);
      }
      _indiceColaLocal = siguiente;
      final cola = uris.sublist(siguiente);
      _marcarArranque(cola.first);
      _fijarPosicion(0);
      await _withDevice(() => _reproducirUris(cola));
    } finally {
      _avanzandoColaLocal = false;
    }
  }

  Future<void> _reanudarTrasSaltar() async {
    if (state.isPlaying) return;
    state = state.copyWith(isPlaying: true);
    _fijarPosicion(0);
    notifyListeners();
    await _withDevice(() => api.play(deviceId: ourDeviceId));
  }

  Future<bool> _volverAlPrincipio() async {
    final ctx = contextUri;
    final uris = _lastUris;
    if (ctx == null && uris == null) return false;
    _revisionPosicion++;
    _fijarPosicion(0);
    await _withDevice(() => ctx != null
        ? api.play(
            deviceId: ourDeviceId,
            contextUri: ctx,
            offsetPosition: 0,
          )
        : _reproducirUris(uris!));
    return true;
  }

  void Function(int ms)? onSalto;

  Future<void> seek(int ms) async {
    final guardada = _porRetomar;
    if (guardada != null) {
      _porRetomar = guardada.conPosicion(ms);
      state = state.copyWith(progressMs: ms);
      _fijarPosicion(ms);
      notifyListeners();
      return;
    }
    if (libre != null) return libre!.saltar(ms);
    final revision = ++_revisionPosicion;
    final posicionPrevia = _lastSyncedProgress;
    final anclajePrevio = _ultimoAnclajeMs;
    _pendingSeekMs = ms;
    _inicioSaltoMs = _relojDePosicion.elapsedMilliseconds;
    _fijarPosicion(ms);
    onSalto?.call(ms);
    final ok = await _withDevice(() => api.seek(ms));
    if (!ok && !_disposed && revision == _revisionPosicion) {
      _pendingSeekMs = null;
      _lastSyncedProgress = posicionPrevia;
      _ultimoAnclajeMs = anclajePrevio;
      progressMs.value = state.isPlaying ? posicionActualMs : posicionPrevia;
      _schedulePoll(Duration.zero);
    }
  }

  bool get muteado => _volumenAntesDeMutear != null;

  int get volumeShown =>
      _volumenAntesDeMutear ?? state.volumePercent ?? config.initialVolume;

  void _aplicarVolumenAlAudio(int percent, {int intentos = 0}) {
    unawaited(_volumenLocal.aplicar(percent).then((ok) {
      if (ok || _disposed || intentos >= 8) return;
      _reintentoVolumen?.cancel();
      _reintentoVolumen = Timer(const Duration(milliseconds: 800), () {
        if (!_disposed) {
          _aplicarVolumenAlAudio(percent, intentos: intentos + 1);
        }
      });
    }));
  }

  /// Solo el audio, sin hablar con Spotify. El arrastre del slider lo usa
  /// para no disparar un PUT por cada pixel (eso acaba en 429).
  void previsualizarVolumen(int percent) {
    final v = percent.clamp(0, 100);
    if (_volumenAntesDeMutear != null) {
      _volumenAntesDeMutear = null;
    }
    if (libre != null) {
      unawaited(libre!.fijarVolumen(v));
      return;
    }
    state = state.copyWith(volumePercent: v);
    _aplicarVolumenAlAudio(v);
  }

  Future<void> alternarMute() async {
    if (muteado) {
      final v = _volumenAntesDeMutear!;
      _volumenAntesDeMutear = null;
      await setVolume(v);
      return;
    }
    _volumenAntesDeMutear = volumeShown == 0 ? 50 : volumeShown;
    notifyListeners();
    if (libre != null) {
      await libre!.fijarVolumen(0);
      return;
    }
    _aplicarVolumenAlAudio(0);
    _pendingVolume = 0;
    _pendingVolumeAt = DateTime.now();
    await _withDevice(() => api.setVolume(0, deviceId: ourDeviceId));
  }

  Future<void> setVolume(int percent) async {
    _volumenAntesDeMutear = null;
    if (libre != null) return libre!.fijarVolumen(percent);
    final v = percent.clamp(0, 100);
    _pendingVolume = v;
    _pendingVolumeAt = DateTime.now();
    state = state.copyWith(volumePercent: v);
    notifyListeners();
    if (config.initialVolume != v) {
      config.initialVolume = v;
      unawaited(config.save());
    }
    _aplicarVolumenAlAudio(v);
    await _withDevice(() => api.setVolume(v, deviceId: ourDeviceId));
  }

  static List<int> calcularOffsetsEstratificados(
    int total, {
    Random? random,
    int tamanoVentana = 25,
  }) {
    if (total <= 0) return const [0, 0, 0];
    final maxOffset = (total - tamanoVentana).clamp(0, total);
    if (maxOffset == 0) return const [0, 0, 0];

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

  static const int kMaxPistasTopEnAleatorio = 10;

  static const double kProporcionConocidasModoInteligente = 0.60;

  bool _aleatorioInteligente = false;

  bool get esAleatorioInteligente => _aleatorioInteligente;

  ModoAleatorio get modoAleatorio {
    if (_aleatorioInteligente) return ModoAleatorio.inteligente;
    if (state.shuffle) return ModoAleatorio.estandar;
    return ModoAleatorio.apagado;
  }

  Future<void> ciclarModoAleatorio({LikedStore? likes, HomeStore? home}) async {
    if (libre != null) return;
    switch (modoAleatorio) {
      case ModoAleatorio.apagado:
        _aleatorioInteligente = false;
        state = state.copyWith(shuffle: true);
        notifyListeners();
        await _withDevice(() => api.setShuffle(true));
        break;

      case ModoAleatorio.estandar:
        state = state.copyWith(shuffle: false);
        _aleatorioInteligente = true;
        notifyListeners();
        await _withDevice(() => api.setShuffle(false));
        await activarAleatorioInteligente(likes: likes, home: home);
        break;

      case ModoAleatorio.inteligente:
        _aleatorioInteligente = false;
        state = state.copyWith(shuffle: false);
        notifyListeners();
        await _withDevice(() => api.setShuffle(false));
        break;
    }
  }

  Future<void> activarAleatorioInteligente({LikedStore? likes, HomeStore? home}) async {
    if (libre != null) return;
    try {
      final urisConocidas = <String>{};
      final pistasConocidas = <String>[];
      final pistasNuevas = <String>[];
      final urisRecientesExcluidas = <String>{};

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
            api
                .artistTopTracks(a.id, discosDeRespaldo: 1)
                .catchError((_) => const <Track>[]),
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

      final int? posicionActualMs =
          (uriPistaActual != null && progressMs.value > 0) ? progressMs.value : null;

      if (uriPistaActual != null && uriPistaActual.isNotEmpty) {
        colaFinal.add(uriPistaActual);
        conocidasSeleccionadas.remove(uriPistaActual);
        nuevasSeleccionadas.remove(uriPistaActual);
      }

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
      _aleatorioInteligente = false;
      notifyListeners();
    }
  }

  Future<void> cycleRepeat() async {
    if (libre != null) return;
    const order = ['off', 'context', 'track'];
    final next = order[(order.indexOf(state.repeat) + 1) % order.length];
    state = state.copyWith(repeat: next);
    notifyListeners();
    await _withDevice(() => api.setRepeat(next));
  }

  Future<void> playContext(
    String contextUri, {
    int? offset,
    String? offsetUri,
  }) {
    _mandoDelUsuario = true;
    _porRetomar = null;
    _colaLocalActiva = false;
    _albumDeRespaldoActual = null;
    _marcarArranque(offsetUri);
    if (libre != null) return libre!.playContext(contextUri, offset: offset);
    _aleatorioInteligente = false;
    _lastContextUri = contextUri;
    _lastUris = null;
    return _withDevice(() async {
      try {
        await api.play(
          deviceId: ourDeviceId,
          contextUri: contextUri,
          offsetPosition: offsetUri == null ? offset : null,
          offsetUri: offsetUri,
        );
      } on ApiException catch (e) {
        if (offsetUri == null ||
            offset == null ||
            (e.status != 400 && !e.isForbidden)) {
          rethrow;
        }
        await api.play(
          deviceId: ourDeviceId,
          contextUri: contextUri,
          offsetPosition: offset,
        );
      }
    });
  }

  Future<void> playLista(
    List<String> uris, {
    int desde = 0,
    bool esInteligente = false,
    int? posicionMs,
  }) {
    if (uris.isEmpty) return Future<void>.value();
    _mandoDelUsuario = true;
    _porRetomar = null;
    _colaLocalActiva = false;
    _albumDeRespaldoActual = null;
    final inicio = desde.clamp(0, uris.length - 1);
    _indiceColaLocal = inicio;
    _marcarArranque(uris[inicio]);
    if (libre != null) return libre!.playLista(uris, desde: inicio);
    if (!esInteligente) {
      _aleatorioInteligente = false;
    }
    _lastContextUri = null;
    _lastUris = List.unmodifiable(uris);
    // Spotify solo admite offset con un contexto de álbum o playlist.
    // Para una cola de URIs, la primera de la petición es la que debe sonar.
    final cola = uris.sublist(inicio);
    return _withDevice(() => _reproducirUris(cola, posicionMs: posicionMs));
  }

  Future<void> playTrack(String uri) {
    _mandoDelUsuario = true;
    _porRetomar = null;
    _colaLocalActiva = false;
    _albumDeRespaldoActual = null;
    _marcarArranque(uri);
    if (libre != null) return libre!.playTrack(uri);
    _aleatorioInteligente = false;
    _lastContextUri = null;
    _lastUris = null;
    return _withDevice(() => _reproducirUris([uri]));
  }

  Future<void> _reproducirUris(List<String> uris, {int? posicionMs}) async {
    final revision = _revisionPosicion;
    try {
      await api.play(deviceId: ourDeviceId, uris: uris, positionMs: posicionMs);
      _colaLocalActiva = false;
      _albumDeRespaldoActual = null;
    } on ApiException catch (e) {
      if (!e.isPlaybackRestriction || !uris.first.startsWith('spotify:track:')) {
        rethrow;
      }
      if (_disposed || revision != _revisionPosicion) return;
      final contexto = await api.contextoDePista(uris.first);
      if (_disposed || revision != _revisionPosicion) return;
      if (contexto == null) rethrow;
      await api.play(
        deviceId: ourDeviceId,
        contextUri: contexto.album,
        offsetUri: contexto.pista,
        positionMs: posicionMs,
      );
      if (_lastUris != null && _lastUris!.length > 1) {
        _colaLocalActiva = true;
        _albumDeRespaldoActual = contexto.album;
      }
    }
  }

  Future<void> addToQueue(String uri) {
    if (libre != null) return libre!.addToQueue(uri);
    return _withDevice(() => api.addToQueue(uri));
  }

  @override
  void dispose() {
    _disposed = true;
    libre?.dispose();
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _reintentoVolumen?.cancel();
    progressMs.dispose();
    currentUri.dispose();
    super.dispose();
  }
}
