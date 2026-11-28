import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'auth.dart';
import 'models.dart';
import 'spotify_api.dart';

class ArtistasFavoritosStore extends ChangeNotifier {
  ArtistasFavoritosStore({
    required this.api,
    required this.auth,
    this.onReauth,
  });

  final SpotifyApi api;
  final SpotifyAuth auth;
  final Future<void> Function()? onReauth;

  final List<Artist> artistas = [];
  final Set<String> _enCurso = {};

  bool _cargando = false;
  bool _cargado = false;
  String? _error;
  int _generacion = 0;
  bool _disposed = false;

  bool get canRead => auth.hasScope(kScopeFollowRead);
  bool get canModify => auth.hasScope(kScopeLibraryModify);
  bool get cargando => _cargando;
  bool get cargado => _cargado;
  String? get error => _error;

  bool esFavorito(String id) {
    for (final a in artistas) {
      if (a.id == id) return true;
    }
    return false;
  }

  bool estaEnCurso(String id) => _enCurso.contains(id);

  static Artist _normalizar(Artist a) {
    final art = (a.art != null && a.art!.isNotEmpty)
        ? a.art
        : ((a.artGrande != null && a.artGrande!.isNotEmpty) ? a.artGrande : null);
    final artGrande = (a.artGrande != null && a.artGrande!.isNotEmpty)
        ? a.artGrande
        : art;
    if (art == a.art && artGrande == a.artGrande) return a;
    return a.copyWith(art: art, artGrande: artGrande);
  }

  void limpiar() {
    _generacion++;
    artistas.clear();
    _enCurso.clear();
    _cargando = false;
    _cargado = false;
    _error = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> cargar({bool forzar = false}) async {
    if (!auth.isLoggedIn || !canRead) {
      artistas.clear();
      _cargando = false;
      _cargado = false;
      _error = null;
      if (!_disposed) notifyListeners();
      return;
    }
    if (_cargando && !forzar) return;
    if (_cargado && !forzar) return;

    final gen = ++_generacion;
    _cargando = true;
    _error = null;
    if (!_disposed) notifyListeners();

    try {
      final encontrados = <Artist>[];
      final vistos = <String>{};
      String? after;
      while (true) {
        final page = await api.followedArtists(limit: 50, after: after);
        if (_disposed || gen != _generacion) return;
        for (final a in page.items) {
          if (a.id.isNotEmpty && vistos.add(a.id)) {
            encontrados.add(_normalizar(a));
          }
        }
        after = page.nextAfter;
        if (after == null || after.isEmpty || page.items.isEmpty) break;
      }
      artistas
        ..clear()
        ..addAll(encontrados);
      _cargado = true;
    } catch (e) {
      if (_disposed || gen != _generacion) return;
      _error = '$e';
    } finally {
      if (!_disposed && gen == _generacion) {
        _cargando = false;
        notifyListeners();
      }
    }
  }

  void actualizarArtista(Artist actualizado) {
    if (actualizado.id.isEmpty) return;
    final i = artistas.indexWhere((a) => a.id == actualizado.id);
    if (i < 0) return;

    final actual = artistas[i];
    final norm = _normalizar(actualizado);
    final fusionado = Artist(
      id: actual.id,
      uri: norm.uri.isNotEmpty ? norm.uri : actual.uri,
      name: norm.name.isNotEmpty && norm.name != 'Desconocido'
          ? norm.name
          : actual.name,
      art: norm.art ?? actual.art,
      artGrande: norm.artGrande ?? actual.artGrande,
      followers: norm.followers > 0 ? norm.followers : actual.followers,
      popularity: norm.popularity > 0 ? norm.popularity : actual.popularity,
      genres: norm.genres.isNotEmpty ? norm.genres : actual.genres,
      biografia: (norm.biografia != null && norm.biografia!.isNotEmpty)
          ? norm.biografia
          : actual.biografia,
    );
    if (fusionado.art == actual.art &&
        fusionado.artGrande == actual.artGrande &&
        fusionado.name == actual.name &&
        fusionado.followers == actual.followers) {
      return;
    }
    artistas[i] = fusionado;
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle(Artist artista) async {
    if (artista.id.isEmpty || _enCurso.contains(artista.id)) return;
    if (!canModify) {
      throw ApiException(
        403,
        'Falta el permiso para seguir o dejar de seguir artistas en Spotify.',
      );
    }

    final normalizado = _normalizar(artista);
    final i = artistas.indexWhere((a) => a.id == normalizado.id);
    final seguia = i >= 0;

    _enCurso.add(normalizado.id);
    if (seguia) {
      artistas.removeAt(i);
    } else {
      artistas.insert(0, normalizado);
    }
    if (!_disposed) notifyListeners();

    try {
      if (seguia) {
        await api.unfollowArtist(normalizado.id);
      } else {
        await api.followArtist(normalizado.id);
        if (normalizado.art == null && normalizado.artGrande == null) {
          unawaited(_completarAvatar(normalizado.id));
        }
      }
    } catch (_) {
      if (!_disposed) {
        if (seguia) {
          if (!esFavorito(normalizado.id)) {
            final idx = i.clamp(0, artistas.length);
            artistas.insert(idx, normalizado);
          }
        } else {
          artistas.removeWhere((a) => a.id == normalizado.id);
        }
      }
      rethrow;
    } finally {
      _enCurso.remove(normalizado.id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _completarAvatar(String artistId) async {
    try {
      final detalle = await api.artist(artistId);
      if (_disposed) return;
      actualizarArtista(detalle);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
