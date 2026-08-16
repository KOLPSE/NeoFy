library;

import 'dart:async';

import 'models.dart';
import 'player_state.dart';
import 'puente_yt.dart';
import 'spotify_api.dart';
import 'yt_player.dart';

class ReproduccionLibre {
  ReproduccionLibre({
    required this.puente,
    required this.ytPlayer,
    required this.api,
    required this.controller,
  }) {
    _suscribirYtPlayer();
  }

  final PuenteYt puente;
  final YtPlayer ytPlayer;
  final SpotifyApi api;
  final PlayerController controller;

  List<Track> _colaSpotify = const [];
  int _indice = -1;
  String? _contextUri;
  StreamSubscription<bool>? _subSonando;
  StreamSubscription<Duration>? _subPosicion;

  bool get tieneSesionYt => puente.api.auth.isLoggedIn;

  Track? get actual => (_indice >= 0 && _indice < _colaSpotify.length) ? _colaSpotify[_indice] : null;

  void _suscribirYtPlayer() {
    ytPlayer.alAcabarLaCola = () => siguiente(automatico: true);
    _subSonando = ytPlayer.cambiosDeSonando.listen((_) => _actualizarEstadoController());
    _subPosicion = ytPlayer.cambiosDePosicion.listen((pos) {
      controller.progressMs.value = pos.inMilliseconds;
    });
    ytPlayer.addListener(_actualizarEstadoController);
  }

  void _actualizarEstadoController() {
    final trackSpotify = actual;
    final posMs = ytPlayer.posicion.inMilliseconds;

    controller.state = Playback(
      track: trackSpotify,
      isPlaying: ytPlayer.sonando,
      progressMs: posMs,
      deviceId: null,
      deviceName: null,
      volumePercent: ytPlayer.volumen,
      shuffle: false,
      repeat: 'off',
      contextUri: _contextUri,
      canSkipNext: _indice + 1 < _colaSpotify.length,
      canSkipPrevious: _indice > 0 || ytPlayer.posicion.inSeconds > 3,
    );
    controller.progressMs.value = posMs;
    controller.currentUri.value = trackSpotify?.uri;
    controller.notificar();
  }

  Future<void> ponerLista(List<Track> pistas, {int desde = 0, String? contextUri}) async {
    if (pistas.isEmpty) return;
    _colaSpotify = List.unmodifiable(pistas);
    _contextUri = contextUri;
    _indice = desde.clamp(0, pistas.length - 1);
    await _reproducirActual();
  }

  Future<void> _reproducirActual() async {
    final trackTarget = actual;
    if (trackTarget == null) return;

    final ytTrack = await puente.equivalenteDe(trackTarget);
    if (ytTrack == null) {
      controller.lastError = 'No se encontró "${trackTarget.name}" en YouTube.';
      controller.notificar();
      if (_indice + 1 < _colaSpotify.length) {
        _indice++;
        await _reproducirActual();
      }
      return;
    }

    await ytPlayer.reproducirPista(ytTrack);
    _actualizarEstadoController();

    if (_indice + 1 < _colaSpotify.length) {
      final proxima = _colaSpotify[_indice + 1];
      unawaited(puente.equivalenteDe(proxima));
    }
  }

  Future<void> alternar() async {
    await ytPlayer.alternar();
    _actualizarEstadoController();
  }

  Future<void> pause() async {
    await ytPlayer.pause();
    _actualizarEstadoController();
  }

  Future<void> siguiente({bool automatico = false}) async {
    if (_indice + 1 < _colaSpotify.length) {
      _indice++;
      await _reproducirActual();
    } else if (automatico) {
      await ytPlayer.pause();
      await ytPlayer.seek(Duration.zero);
      _actualizarEstadoController();
    }
  }

  Future<void> anterior() async {
    if (ytPlayer.posicion.inSeconds > 3 || _indice <= 0) {
      await ytPlayer.seek(Duration.zero);
      _actualizarEstadoController();
      return;
    }
    _indice--;
    await _reproducirActual();
  }

  Future<void> saltar(int ms) async {
    await ytPlayer.seek(Duration(milliseconds: ms));
    _actualizarEstadoController();
  }

  Future<void> fijarVolumen(int v) async {
    await ytPlayer.setVolumen(v);
    _actualizarEstadoController();
  }

  Future<void> playTrack(String uri) async {
    final lista = await api.tracks([uri]);
    if (lista.isNotEmpty) {
      await ponerLista(lista, desde: 0);
    } else {
      controller.lastError = 'No se pudo obtener información de la canción.';
      controller.notificar();
    }
  }

  Future<void> playLista(List<String> uris, {int desde = 0}) async {
    if (uris.isEmpty) return;
    final lista = await api.tracks(uris);
    if (lista.isNotEmpty) {
      await ponerLista(lista, desde: desde);
    } else {
      controller.lastError = 'No se pudieron obtener las canciones de la lista.';
      controller.notificar();
    }
  }

  Future<void> playContext(String contextUri, {int? offset}) async {
    List<Track> pistas = [];
    final desde = offset ?? 0;

    try {
      if (contextUri.startsWith('spotify:playlist:')) {
        final id = contextUri.substring('spotify:playlist:'.length);
        final page = await api.playlistItems(id);
        pistas = page.items;
      } else if (controller.currentUserId != null &&
          contextUri == SpotifyApi.likedContextUri(controller.currentUserId!)) {
        final page = await api.savedTracks();
        pistas = page.items;
      } else if (contextUri.startsWith('spotify:artist:')) {
        final id = contextUri.substring('spotify:artist:'.length);
        pistas = await api.artistTopTracks(id);
      } else if (contextUri.startsWith('spotify:album:')) {
        final id = contextUri.substring('spotify:album:'.length);
        pistas = await api.albumTracks(id);
      } else {
        controller.lastError = 'Contexto de reproducción no soportado en modo libre.';
        controller.notificar();
        return;
      }
    } catch (e) {
      controller.lastError = 'Error al cargar el contexto: $e';
      controller.notificar();
      return;
    }

    if (pistas.isNotEmpty) {
      await ponerLista(pistas, desde: desde, contextUri: contextUri);
    } else {
      controller.lastError = 'No se encontraron canciones en este contexto.';
      controller.notificar();
    }
  }

  Future<void> addToQueue(String uri) async {
    final resolved = await api.tracks([uri]);
    if (resolved.isNotEmpty) {
      _colaSpotify = List.unmodifiable([..._colaSpotify, ...resolved]);
      _actualizarEstadoController();
    }
  }

  void dispose() {
    ytPlayer.alAcabarLaCola = null;
    unawaited(_subSonando?.cancel());
    unawaited(_subPosicion?.cancel());
    ytPlayer.removeListener(_actualizarEstadoController);
  }
}
