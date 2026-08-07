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
/// Los mixes diarios y el radar de novedades **no se pueden sacar por la Web
/// API**. Comprobado con `tool/probe_home.dart`: `/browse/featured-playlists`,
/// `/browse/new-releases` y `/browse/categories` contestan 403 en Modo
/// Desarrollo, `/recommendations` está retirado (404) y no hay ningún endpoint
/// que liste las listas generadas para el usuario. Buscar "Daily Mix" devuelve
/// imitaciones de otra gente, que es peor que no enseñar nada.
///
/// Lo que sí hay es esto: el historial y lo más escuchado, que son datos
/// propios del usuario y salen de su cuenta.
class HomeStore extends ChangeNotifier {
  HomeStore({required this.api, required this.auth});

  final SpotifyApi api;
  final SpotifyAuth auth;

  List<Track> recientes = const [];
  List<Track> masEscuchadas = const [];
  List<Artist> artistas = const [];

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
      // En paralelo: son tres peticiones independientes y la portada no se
      // pinta entera hasta que están las tres.
      final res = await Future.wait([
        api.recentlyPlayed(limit: 20),
        api.topTracks(limit: 20),
        api.topArtists(limit: 20),
      ]);
      recientes = res[0] as List<Track>;
      masEscuchadas = res[1] as List<Track>;
      artistas = res[2] as List<Artist>;
      _cargado = true;
    } catch (e) {
      error = '$e';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }
}
