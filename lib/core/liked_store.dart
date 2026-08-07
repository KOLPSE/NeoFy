import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'auth.dart';
import 'models.dart';
import 'spotify_api.dart';

/// Qué canciones están en "Canciones que te gustan".
///
/// Lo lleva un único sitio porque la misma canción sale en varias pantallas a
/// la vez (búsqueda, playlist, cola) y el corazón tiene que estar igual en
/// todas. Además así una canción solo se consulta una vez en toda la sesión.
///
/// Las consultas se agrupan: cada fila que aparece en pantalla pide saber su
/// estado, y en vez de una petición por fila se junta lo pedido en 120 ms y se
/// manda de 50 en 50. Scrollear rápido por una playlist larga cuesta unas pocas
/// peticiones, no una por canción.
class LikedStore extends ChangeNotifier {
  LikedStore({required this.api, required this.auth, this.onReauth});

  final SpotifyApi api;
  final SpotifyAuth auth;

  /// Se invoca cuando el usuario acepta volver a pasar por el consentimiento,
  /// que es la única forma de conseguir `user-library-modify` en una sesión que
  /// se creó sin él.
  final Future<void> Function()? onReauth;

  /// Cuántas uris caben en una consulta. Mismo criterio que el resto de la app.
  static const _tamanoLote = 50;

  final Set<String> _guardadas = {};
  final Set<String> _conocidas = {};
  final Set<String> _porConsultar = {};

  // ------------------------------------------------- la biblioteca entera
  //
  // La lista vive aquí y no en la pantalla porque el shell construye solo la
  // vista activa: al ir a una playlist y volver, la pantalla se reconstruye
  // desde cero y volvía a bajarse las ~60 páginas. El store no se entera de la
  // navegación, así que la biblioteca se carga una vez por sesión.

  final List<Track> biblioteca = [];

  bool _cargandoBiblioteca = false;
  bool _bibliotecaCompleta = false;
  int _offsetBiblioteca = 0;

  /// Total que dice Spotify, para poder enseñar "1.250 de 3.014".
  int? totalBiblioteca;
  String? errorBiblioteca;

  bool get cargandoBiblioteca => _cargandoBiblioteca;
  bool get bibliotecaCompleta => _bibliotecaCompleta;

  /// Se baja la biblioteca entera, página a página, avisando conforme llega.
  ///
  /// Son ~60 peticiones secuenciales para 3.000 canciones; secuenciales a
  /// propósito, para no saturar la API. Si ya está cargada no hace nada, que es
  /// justo lo que evita recargarla al volver a la pantalla.
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
        // Todo lo que sale de aquí está guardado por definición: se apunta en
        // vez de preguntarlo, que serían otras 60 peticiones para confirmar lo
        // que ya sabemos.
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

  /// ¿Tiene la sesión permiso para tocar la biblioteca? Una sesión iniciada
  /// antes de que existiera el botón no lo tiene, y hay que decirlo en vez de
  /// dejar que Spotify conteste un 403 sin explicación.
  bool get canModify => auth.hasScope(kScopeLibraryModify);

  /// `true` guardada, `false` no, `null` todavía no se sabe. El tercer estado
  /// importa: pintar un corazón vacío mientras se consulta haría que las filas
  /// parpadearan a rojo al llegar la respuesta.
  bool? isSaved(String uri) =>
      _conocidas.contains(uri) ? _guardadas.contains(uri) : null;

  /// Da por sabido, sin preguntar, que estas canciones están guardadas.
  ///
  /// Lo usa la pantalla de la biblioteca: si algo salió de `GET /me/tracks`,
  /// está guardado por definición y preguntarlo serían 60 peticiones para
  /// confirmar lo que ya sabemos.
  void seedSaved(Iterable<String> uris) {
    var nuevas = false;
    for (final uri in uris) {
      if (_conocidas.add(uri)) nuevas = true;
      _guardadas.add(uri);
      _porConsultar.remove(uri);
    }
    if (nuevas) notifyListeners();
  }

  /// Pide averiguar el estado de una canción. Es barato llamarlo desde `build`:
  /// no hace nada si ya se sabe o ya está en la cola.
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
          // Que no se sepa el estado de un lote no es motivo para romper nada:
          // esas filas se quedan con el corazón en "no se sabe" y se volverán a
          // pedir la próxima vez que aparezcan.
        }
      }
    } finally {
      _consultando = false;
    }
  }

  /// Guarda o quita, según cómo esté ahora.
  ///
  /// El cambio se pinta antes de que conteste Spotify —el corazón tiene que
  /// responder al instante— y se deshace si la petición falla. Lanza la
  /// excepción para que quien llama pueda explicar el porqué.
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
