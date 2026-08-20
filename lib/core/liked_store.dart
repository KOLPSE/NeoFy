import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'auth.dart';
import 'models.dart';
import 'spotify_api.dart';

class LikedStore extends ChangeNotifier {
  LikedStore({required this.api, required this.auth, this.onReauth});

  final SpotifyApi api;
  final SpotifyAuth auth;

  final Future<void> Function()? onReauth;

  static const _tamanoLote = 50;

  final Set<String> _guardadas = {};
  final Set<String> _conocidas = {};
  final Set<String> _porConsultar = {};

  final List<Track> biblioteca = [];

  bool _cargandoBiblioteca = false;
  bool _bibliotecaCompleta = false;
  int _offsetBiblioteca = 0;

  int? totalBiblioteca;
  String? errorBiblioteca;

  bool get cargandoBiblioteca => _cargandoBiblioteca;
  bool get bibliotecaCompleta => _bibliotecaCompleta;

  Future<void> cargarBiblioteca({bool forzar = false}) async {
    if (_cargandoBiblioteca) return;
    if (_bibliotecaCompleta && !forzar) return;
    if (forzar) {
      biblioteca.clear();
      _offsetBiblioteca = 0;
      _bibliotecaCompleta = false;
    }
    _cargandoBiblioteca = true;
    errorBiblioteca = null;
    notifyListeners();
    try {
      var quedan = true;
      while (quedan && !_disposed) {
        final page = await api.savedTracks(limit: 50, offset: _offsetBiblioteca);
        biblioteca.addAll(page.items);
        _offsetBiblioteca += page.rawCount;
        totalBiblioteca = page.total ?? totalBiblioteca;
        seedSaved(page.items.map((t) => t.uri));
        quedan = page.hasMore;
        if (!_disposed) notifyListeners();
      }
      if (!quedan) _bibliotecaCompleta = true;
    } catch (e) {
      errorBiblioteca = '$e';
    } finally {
      _cargandoBiblioteca = false;
      if (!_disposed) notifyListeners();
    }
  }

  Timer? _agrupador;
  bool _consultando = false;
  bool _disposed = false;

  bool get canModify => auth.hasScope(kScopeLibraryModify);

  bool? isSaved(String uri) =>
      _conocidas.contains(uri) ? _guardadas.contains(uri) : null;

  void seedSaved(Iterable<String> uris) {
    var nuevas = false;
    for (final uri in uris) {
      if (_conocidas.add(uri)) nuevas = true;
      _guardadas.add(uri);
      _porConsultar.remove(uri);
    }
    if (nuevas) notifyListeners();
  }

  void ensureKnown(String uri) {
    if (uri.isEmpty || _conocidas.contains(uri) || _porConsultar.contains(uri)) {
      return;
    }
    _porConsultar.add(uri);
    _agrupador ??= Timer(const Duration(milliseconds: 120), _consultarPendientes);
  }

  Future<void> _consultarPendientes() async {
    _agrupador = null;
    if (_consultando || _disposed) return;
    _consultando = true;
    try {
      while (_porConsultar.isNotEmpty && !_disposed) {
        final lote = _porConsultar.take(_tamanoLote).toList();
        _porConsultar.removeAll(lote);
        try {
          final res = await api.savedContains(lote);
          for (var i = 0; i < lote.length && i < res.length; i++) {
            _conocidas.add(lote[i]);
            if (res[i]) {
              _guardadas.add(lote[i]);
            } else {
              _guardadas.remove(lote[i]);
            }
          }
          if (!_disposed) notifyListeners();
        } catch (_) {
        }
      }
    } finally {
      _consultando = false;
    }
  }

  Future<void> toggle(String uri) async {
    if (!canModify) {
      throw ApiException(403, 'Falta el permiso para editar tus favoritos.');
    }
    final estaba = isSaved(uri) ?? false;
    _aplicar(uri, !estaba);
    try {
      if (estaba) {
        await api.removeSavedTracks([uri]);
      } else {
        await api.saveTracks([uri]);
      }
    } catch (e) {
      _aplicar(uri, estaba);
      rethrow;
    }
  }

  void _aplicar(String uri, bool guardada) {
    _conocidas.add(uri);
    if (guardada) {
      _guardadas.add(uri);
    } else {
      _guardadas.remove(uri);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _agrupador?.cancel();
    super.dispose();
  }
}
