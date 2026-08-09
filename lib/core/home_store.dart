import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'auth.dart';
import 'models.dart';
import 'spotify_api.dart';

/// Lo que se pinta en la portada.
///
/// Vive en un store y no en la pantalla por lo mismo que la biblioteca: el
/// shell construye solo la vista activa, así que ir a una playlist y volver
/// reconstruye la pantalla entera. Con los datos aquí, la portada se pide una
/// vez por sesión.
///
/// ## Lo que Spotify no deja
///
/// El Discover Weekly / Release Radar / Daily Mix **reales no se pueden sacar
/// por la Web API**. Comprobado con `tool/probe_home.dart` (última vez,
/// 2026-08-09): `/recommendations` está retirado (404),
/// `/browse/featured-playlists` ya ni existe (404) y no hay ningún endpoint
/// que liste las listas generadas para el usuario (`/me/home` da 410,
/// `/me/library/home` da 404). Tampoco vale mirar `/me/playlists`: esas listas
/// no siempre están seguidas ahí. Buscar "Daily Mix" devuelve imitaciones de
/// otra gente, que es peor que no enseñar nada.
///
/// Lo que sí hay, además del historial y lo más escuchado:
///
/// - **[novedades]**: `/browse/new-releases` sí contesta 200. No está
///   personalizado —es el catálogo global, no tus gustos— pero es la única
///   fuente real de "cosas nuevas" que queda.
/// - **[paraTi]**: una aproximación casera al "hecho para ti", armada con las
///   canciones top de tus propios artistas top (`artistTopTracks`, que sí
///   funciona en Modo Desarrollo) y filtrando lo que ya sale en "vuelve a
///   escuchar" o "lo que más escuchas". No es el algoritmo de Spotify, es un
///   sucedáneo hecho con lo que la API deja tocar.
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

  /// ¿Tiene la sesión los permisos que necesita la portada? Son los últimos en
  /// llegar, así que una sesión anterior no los tiene.
  bool get puedeLeer =>
      auth.hasScope(kScopeTopRead) && auth.hasScope(kScopeRecentlyPlayed);

  Future<void> cargar({bool forzar = false}) async {
    if (_cargando || (_cargado && !forzar)) return;
    if (!puedeLeer) return;
    _cargando = true;
    error = null;
    notifyListeners();
    try {
      // En paralelo: son cuatro peticiones independientes y la portada no se
      // pinta entera hasta que están las cuatro.
      final res = await Future.wait([
        api.recentlyPlayed(limit: 20),
        api.topTracks(limit: 20),
        api.topArtists(limit: 20),
        api.newReleases(limit: 20),
      ]);
      recientes = res[0] as List<Track>;
      masEscuchadas = res[1] as List<Track>;
      artistas = res[2] as List<Artist>;
      novedades = res[3] as List<Album>;
      // Depende de artistas y de lo anterior para descartar repetidos, así que
      // va después y no dentro del Future.wait de arriba.
      paraTi = await _armarParaTi();
      _cargado = true;
    } catch (e) {
      error = '$e';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Ver el comentario de cabecera de la clase: no hay radar real, esto es un
  /// sucedáneo con canciones top de los artistas top del usuario.
  ///
  /// Se limita a los primeros 8 artistas para no disparar el número de
  /// peticiones (`artistTopTracks` es una llamada por artista); con 8 hay de
  /// sobra para juntar 30 canciones sin repetir. Un artista que falle (red,
  /// 404 puntual) no debe tirar la sección entera, así que se traga el error y
  /// ese artista simplemente no aporta canciones.
  Future<List<Track>> _armarParaTi() async {
    if (artistas.isEmpty) return const [];
    final base = artistas.take(8).toList();
    final listas = await Future.wait([
      for (final a in base)
        api.artistTopTracks(a.id).catchError((_) => const <Track>[]),
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
