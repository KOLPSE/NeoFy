import 'dart:async';

import 'package:flutter/foundation.dart';

import 'player_state.dart';

/// Temporizador real de apagado de reproducción.
///
/// Soporta cuenta atrás en minutos o pausa automática al cambiar/terminar la
/// canción actual. Al cumplirse invoca [onPausar] (por defecto pausa el
/// [PlayerController] si sigue sonando).
class TemporizadorApagado extends ChangeNotifier {
  TemporizadorApagado(
    this._player, {
    this.onPausar,
  }) {
    _player.currentUri.addListener(_alCambiarPista);
  }

  final PlayerController _player;
  final Future<void> Function()? onPausar;

  Timer? _timer;
  Duration? _restante;
  bool _alFinalDeLaCancion = false;
  String? _uriEsperada;
  bool _disposed = false;

  bool get activo => _restante != null || _alFinalDeLaCancion;
  bool get alFinalDeLaCancion => _alFinalDeLaCancion;
  Duration? get restante => _restante;

  String get etiquetaRestante {
    if (_alFinalDeLaCancion) return 'Al final de la canción';
    final r = _restante;
    if (r == null) return '';
    final minutos = r.inMinutes;
    final segundos = (r.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  void activarMinutos(int minutos) {
    if (minutos <= 0) {
      cancelar();
      return;
    }
    _timer?.cancel();
    _alFinalDeLaCancion = false;
    _uriEsperada = null;
    _restante = Duration(minutes: minutos);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (!_disposed) notifyListeners();
  }

  void activarFinDeCancion() {
    _timer?.cancel();
    _timer = null;
    _restante = null;
    _alFinalDeLaCancion = true;
    _uriEsperada = _player.currentUri.value ?? _player.state.track?.uri;
    if (!_disposed) notifyListeners();
  }

  void cancelar() {
    if (!activo) return;
    _timer?.cancel();
    _timer = null;
    _restante = null;
    _alFinalDeLaCancion = false;
    _uriEsperada = null;
    if (!_disposed) notifyListeners();
  }

  void _tick() {
    final actual = _restante;
    if (actual == null) return;
    final siguiente = actual - const Duration(seconds: 1);
    if (siguiente <= Duration.zero) {
      unawaited(_ejecutarPausa());
    } else {
      _restante = siguiente;
      if (!_disposed) notifyListeners();
    }
  }

  void _alCambiarPista() {
    if (!_alFinalDeLaCancion) return;
    final actual = _player.currentUri.value ?? _player.state.track?.uri;
    if (_uriEsperada == null) {
      _uriEsperada = actual;
      return;
    }
    if (actual != null && actual != _uriEsperada) {
      unawaited(_ejecutarPausa());
    }
  }

  Future<void> _ejecutarPausa() async {
    _timer?.cancel();
    _timer = null;
    _restante = null;
    _alFinalDeLaCancion = false;
    _uriEsperada = null;
    if (!_disposed) notifyListeners();
    if (onPausar != null) {
      await onPausar!();
    } else if (_player.state.isPlaying) {
      await _player.pause();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _player.currentUri.removeListener(_alCambiarPista);
    super.dispose();
  }
}
