import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'auth.dart';
import 'models.dart';
import 'spotify_api.dart';

class HomeStore extends ChangeNotifier {
  HomeStore({required this.api, required this.auth});

  final SpotifyApi api;
  final SpotifyAuth auth;

  List<Track> recientes = const [];
  List<Track> masEscuchadas = const [];
  List<Artist> artistas = const [];
  List<Album> novedades = const [];
  List<Track> paraTi = const [];

  bool _cargando = false;
  bool _cargado = false;
  String? error;

  bool get cargando => _cargando;
  bool get cargado => _cargado;
  bool get vacio =>
      recientes.isEmpty && masEscuchadas.isEmpty && artistas.isEmpty;

  bool get puedeLeer =>
      auth.hasScope(kScopeTopRead) && auth.hasScope(kScopeRecentlyPlayed);

  Future<void> cargar({bool forzar = false}) async {
    if (_cargando || (_cargado && !forzar)) return;
    if (!puedeLeer) return;
    _cargando = true;
    error = null;
    notifyListeners();
    try {
      // Spotify a veces contesta [] en short_term y sí rellena medium/long.
      // recently-played puede venir vacío si solo se escucha por la vía libre
      // (YouTube), que no escribe el historial de Spotify.
      final res = await Future.wait([
        api.recentlyPlayed(limit: 20),
        _topConRespaldo((r, n) => api.topTracks(timeRange: r, limit: n)),
        _topConRespaldo((r, n) => api.topArtists(timeRange: r, limit: n)),
      ]);
      recientes = res[0] as List<Track>;
      masEscuchadas = res[1] as List<Track>;
      artistas = res[2] as List<Artist>;
      novedades = await _cargarNovedades();
      paraTi = await _armarParaTi();
      _cargado = true;
    } catch (e) {
      error = '$e';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  static const _rangosTop = ['short_term', 'medium_term', 'long_term'];

  Future<List<T>> _topConRespaldo<T>(
    Future<List<T>> Function(String rango, int limite) pedir,
  ) async {
    for (final rango in _rangosTop) {
      final lista = await pedir(rango, 20);
      if (lista.isNotEmpty) return lista;
    }
    return const [];
  }

  Future<List<Album>> _cargarNovedades() async {
    try {
      return await api.newReleases(limit: 20);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Track>> _armarParaTi() async {
    if (artistas.isEmpty) return const [];
    final base = artistas.take(8).toList();
    final listas = await Future.wait([
      for (final a in base)
        api
            .artistTopTracks(a.id, discosDeRespaldo: 1)
            .catchError((_) => const <Track>[]),
    ]);

    final conocidas = {
      for (final t in recientes) t.uri,
      for (final t in masEscuchadas) t.uri,
    };
    final vistas = <String>{};
    final pool = <Track>[];
    for (final lista in listas) {
      for (final t in lista) {
        if (t.uri.isEmpty || conocidas.contains(t.uri)) continue;
        if (!vistas.add(t.uri)) continue;
        pool.add(t);
      }
    }
    pool.shuffle();
    return pool.take(30).toList();
  }
}
