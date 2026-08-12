import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  /// El dispositivo de librespot desapareció (se reinició el sidecar, se perdió
  /// la red...). Quien llama debe volver a resolver el device_id.
  bool get isDeviceNotFound => status == 404;

  /// Spotify devuelve 403 cuando la cuenta no es Premium o la acción no está
  /// permitida en el estado actual (p. ej. saltar en una radio).
  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}

/// Cliente de la Web API de Spotify.
///
/// ⚠️ Los endpoints de playlist se renombraron en febrero de 2026:
/// `/playlists/{id}/items` (no `/tracks`) y `POST /me/playlists`
/// (no `/users/{id}/playlists`). Casi toda la documentación de terceros que
/// circula sigue usando los nombres viejos, que ahora dan 404.
class SpotifyApi {
  SpotifyApi(this.auth);

  final SpotifyAuth auth;
  final http.Client _http = http.Client();

  static const _base = 'api.spotify.com';

  /// Plazo de cada petición. Generoso, pero finito: lo que no puede pasar es
  /// que una llamada colgada se coma el arranque.
  static const _plazo = Duration(seconds: 20);

  /// Lo máximo que se espera a un 429 antes de rendirse y contarlo.
  static const _esperaMaximaEn429 = Duration(seconds: 10);

  /// Rutas penalizadas por cuota y hasta cuándo.
  ///
  /// ⚠️ **La cuota se agota por endpoint, no de golpe.** Comprobado con
  /// `tool/probe_quota.dart` teniendo la cuota reventada: `/me` contestaba 429
  /// `QUOTA_EXCEEDED` con `Retry-After` de 8 horas mientras `/me/player`,
  /// `/me/player/devices` y `/me/player/queue` seguían dando 200 — o sea, la
  /// reproducción entera funcionaba. Llevar una sola bandera global apagaba la
  /// app por el 429 de una llamada que solo sirve para saber si la cuenta es
  /// Premium.
  ///
  /// Seguir preguntando a una ruta penalizada no adelanta nada y mantiene viva
  /// la penalización, así que esas fallan en el acto sin salir a la red.
  final Map<String, DateTime> _penalizadas = {};

  /// Familia de la ruta: los dos primeros tramos. `/me/player/devices` y
  /// `/me/player/queue` comparten castigo con `/me/player`, que es como parece
  /// aplicarlo Spotify, pero `/me` no arrastra a `/me/player`.
  static String _familia(String path) {
    final tramos = path.split('/').where((t) => t.isNotEmpty).take(2);
    return '/${tramos.join('/')}';
  }

  Duration? esperaDe(String path) {
    final hasta = _penalizadas[_familia(path)];
    if (hasta == null) return null;
    final queda = hasta.difference(DateTime.now());
    if (!queda.isNegative) return queda;
    _penalizadas.remove(_familia(path));
    return null;
  }

  /// ¿Está limitado el control de reproducción? Es lo único que impide usar la
  /// app para lo que es.
  bool get reproduccionLimitada => esperaDe('/me/player') != null;

  /// Aviso para enseñar tal cual, o `null` si no hay nada penalizado. Dice la
  /// hora y no los segundos: "vuelve a las 23:47" se entiende; "faltan
  /// 30.819 s", no. Y aclara si la reproducción sigue en pie, que es la
  /// diferencia entre "la app no va" y "no puedes buscar".
  String? get avisoDeCuota {
    _penalizadas.removeWhere((_, hasta) => hasta.isBefore(DateTime.now()));
    if (_penalizadas.isEmpty) return null;

    final hasta = _penalizadas.values.reduce((a, b) => a.isAfter(b) ? a : b);
    final h = hasta.hour.toString().padLeft(2, '0');
    final m = hasta.minute.toString().padLeft(2, '0');
    final quedan = hasta.difference(DateTime.now());
    final cuanto = quedan.inHours >= 1
        ? '${quedan.inHours} h ${quedan.inMinutes % 60} min'
        : '${quedan.inMinutes} min';

    final alcance = reproduccionLimitada
        ? 'Spotify ha agotado la cuota de peticiones de la app'
        : 'Spotify ha agotado la cuota de buscar y navegar (la reproducción '
            'sigue funcionando)';
    return '$alcance. Vuelve sobre las $h:$m (en $cuanto). Es el límite del '
        'Modo Desarrollo y se recupera solo.';
  }

  /// Punto único por el que pasa toda petición: mete el token, reintenta una
  /// vez ante un 401 y respeta `Retry-After` en los 429.
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retryOn401 = true,
  }) async {
    // Con esta ruta penalizada no se sale a la red siquiera: cada petición de
    // más es una que Spotify cuenta para mantener la penalización. Ojo: solo
    // esta ruta — que `/me` esté castigado no impide controlar el reproductor.
    if (esperaDe(path) != null) throw ApiException(429, avisoDeCuota ?? '');

    final token = await auth.accessToken();
    final uri = Uri.https(_base, '/v1$path', query);
    final req = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    // Sin plazo, una petición que no contesta se queda colgada para siempre y
    // se lleva por delante a quien la esperaba. Pasó en el arranque: la llamada
    // a `/me` bloqueada dejaba la app sin lanzar ni librespot ni el sidecar.
    final streamed = await _http.send(req).timeout(
          _plazo,
          onTimeout: () => throw ApiException(
              408, 'Spotify no contestó a $method /v1$path en ${_plazo.inSeconds} s.'),
        );
    final res = await http.Response.fromStream(streamed).timeout(
          _plazo,
          onTimeout: () => throw ApiException(
              408, 'Spotify cortó la respuesta de $method /v1$path.'),
        );

    if (res.statusCode == 401 && retryOn401) {
      await auth.forceRefresh();
      return _request(method, path, query: query, body: body, retryOn401: false);
    }
    if (res.statusCode == 429) {
      final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 3;
      // ⚠️ El `Retry-After` de Spotify no siempre son unos segundos: al agotar
      // la cuota diaria del Modo Desarrollo pide **horas** (visto: 30.819 s).
      // Dormirlos dentro de la petición congelaba la app entera sin decir por
      // qué. Se espera solo lo razonable y, si pide más, se anota y se avisa.
      if (wait > _esperaMaximaEn429.inSeconds) {
        _penalizadas[_familia(path)] = DateTime.now().add(Duration(seconds: wait));
        throw ApiException(429, avisoDeCuota ?? '');
      }
      await Future<void>.delayed(Duration(seconds: wait + 1));
      return _request(method, path, query: query, body: body, retryOn401: retryOn401);
    }
    // ⚠️ Visto con la cuota reventada: los endpoints de navegar (`/me/tracks`,
    // `/me/playlists`, `/search`) empiezan a contestar **410 con el cuerpo
    // vacío**. No es que hayan desaparecido —una hora antes iban— así que un
    // "HTTP 410" pelado en pantalla no le dice nada a nadie.
    if (res.statusCode == 410) {
      throw ApiException(
        410,
        'Spotify ha retirado temporalmente esta parte de la API (410). Suele ir '
        'con la cuota agotada del Modo Desarrollo y se recupera solo; mientras '
        'tanto, la reproducción sigue funcionando.',
      );
    }
    // Una respuesta buena significa que esta ruta ya no está penalizada.
    _penalizadas.remove(_familia(path));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _extractMessage(res));
    }
    // Los comandos del reproductor (next, pause, seek...) contestan 204, y
    // algunos 200 con el cuerpo vacío. Se comprueba sobre los bytes crudos:
    // `res.body` decodifica según la cabecera y puede reventar por su cuenta.
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;

    // ⚠️ `PUT /me/player/seek` (y compañía) responden 200 **sin content-type**
    // y con un identificador opaco de comando en el cuerpo, tipo
    // `jv7Ra_vijxxyQa8yrwA2dkEaDUY`. No es JSON y no nos sirve de nada, así
    // que se descarta en vez de intentar parsearlo. Se mira la cabecera y, si
    // no la hay, el primer carácter: solo `{` o `[` pueden ser JSON.
    if (!_looksLikeJson(res)) return null;

    try {
      final text = utf8.decode(res.bodyBytes);
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } on FormatException catch (e) {
      // Un "FormatException" pelado no dice ni qué endpoint ni qué llegó. Si
      // Spotify contesta algo que no es JSON (una página de error de su CDN,
      // por ejemplo), el mensaje tiene que bastar para saberlo sin depurar.
      final preview = String.fromCharCodes(res.bodyBytes.take(120))
          .replaceAll(RegExp(r'\s+'), ' ');
      throw ApiException(
        res.statusCode,
        'Respuesta no válida de $method /v1$path (HTTP ${res.statusCode}, '
        'content-type: ${res.headers['content-type'] ?? 'ninguno'}): ${e.message}\n'
        'Empieza por: $preview',
      );
    }
  }

  /// ¿El cuerpo es JSON? Si la cabecera lo dice, se cree. Si no viene cabecera
  /// —que es el caso de los comandos del reproductor— se mira el primer
  /// carácter no blanco.
  static bool _looksLikeJson(http.Response res) {
    final type = res.headers['content-type'];
    if (type != null && type.contains('json')) return true;
    if (type != null && type.isNotEmpty) return false;
    for (final b in res.bodyBytes) {
      if (b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) continue;
      return b == 0x7b || b == 0x5b; // '{' o '['
    }
    return false;
  }

  String _extractMessage(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final err = j['error'];
      if (err is Map && err['message'] is String) return err['message'] as String;
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }

  // ---------------------------------------------------------------- cuenta

  Future<Map<String, dynamic>> me() async =>
      (await _request('GET', '/me')) as Map<String, dynamic>;

  // ------------------------------------------------------------ reproductor

  Future<Playback?> playbackState() async {
    final j = await _request('GET', '/me/player');
    if (j == null) return null; // 204: no hay ninguna sesión activa
    return Playback.fromJson(j as Map<String, dynamic>);
  }

  Future<List<Device>> devices() async {
    final j = await _request('GET', '/me/player/devices') as Map<String, dynamic>;
    return ((j['devices'] as List<dynamic>?) ?? const [])
        .map((d) => Device.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  Future<void> transfer(String deviceId, {bool play = false}) => _request(
        'PUT',
        '/me/player',
        body: {'device_ids': [deviceId], 'play': play},
      );

  /// Reanuda, o arranca algo concreto.
  ///
  /// [contextUri] para una playlist/álbum entero, [uris] para canciones
  /// sueltas, [offsetPosition] para empezar en la pista N del contexto y
  /// [offsetUri] para empezar en una canción concreta de ese contexto sin
  /// saber en qué posición está — que es el caso al recuperarse de un corte de
  /// audio: se sabe qué sonaba, no por dónde iba la lista.
  Future<void> play({
    String? deviceId,
    String? contextUri,
    List<String>? uris,
    int? offsetPosition,
    String? offsetUri,
    int? positionMs,
  }) {
    final body = <String, dynamic>{};
    if (contextUri != null) body['context_uri'] = contextUri;
    if (uris != null) body['uris'] = uris;
    if (offsetPosition != null) body['offset'] = {'position': offsetPosition};
    if (offsetUri != null) body['offset'] = {'uri': offsetUri};
    if (positionMs != null) body['position_ms'] = positionMs;
    return _request(
      'PUT',
      '/me/player/play',
      query: deviceId == null ? null : {'device_id': deviceId},
      body: body.isEmpty ? null : body,
    );
  }

  Future<void> pause() => _request('PUT', '/me/player/pause');
  Future<void> next() => _request('POST', '/me/player/next');
  Future<void> previous() => _request('POST', '/me/player/previous');

  Future<void> seek(int positionMs) =>
      _request('PUT', '/me/player/seek', query: {'position_ms': '$positionMs'});

  Future<void> setVolume(int percent) => _request('PUT', '/me/player/volume',
      query: {'volume_percent': '${percent.clamp(0, 100)}'});

  Future<void> setShuffle(bool on) =>
      _request('PUT', '/me/player/shuffle', query: {'state': '$on'});

  /// [mode] es `off`, `track` o `context`.
  Future<void> setRepeat(String mode) =>
      _request('PUT', '/me/player/repeat', query: {'state': mode});

  Future<void> addToQueue(String uri) =>
      _request('POST', '/me/player/queue', query: {'uri': uri});

  Future<List<Track>> queue() async {
    final j = await _request('GET', '/me/player/queue') as Map<String, dynamic>?;
    if (j == null) return const [];
    return ((j['queue'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>))
        .whereType<Track>()
        .toList();
  }

  // -------------------------------------------------------------- playlists

  Future<ApiPage<Playlist>> myPlaylists({int limit = 50, int offset = 0}) async {
    final j = await _request('GET', '/me/playlists',
        query: {'limit': '$limit', 'offset': '$offset'}) as Map<String, dynamic>;
    final raw = (j['items'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: raw.whereType<Map<String, dynamic>>().map(Playlist.fromJson).toList(),
      hasMore: j['next'] != null,
      rawCount: raw.length,
    );
  }

  /// ⚠️ `/items`, no `/tracks` (renombrado en febrero de 2026).
  ///
  /// Se pagina de 50 en 50: una playlist grande no cabe en memoria de golpe ni
  /// hace falta que quepa.
  Future<ApiPage<Track>> playlistItems(String id, {int limit = 50, int offset = 0}) async {
    final j = await _request('GET', '/playlists/$id/items',
        query: {'limit': '$limit', 'offset': '$offset'}) as Map<String, dynamic>;
    final raw = (j['items'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          // ⚠️ Comprobado contra la API: el envoltorio trae la pista en `item`.
          // Se acepta `track` de reserva, que es como se llamaba antes.
          .map((it) => Track.fromJson(
              (it['item'] ?? it['track']) as Map<String, dynamic>?))
          .whereType<Track>()
          .toList(),
      hasMore: j['next'] != null,
      rawCount: raw.length,
    );
  }

  // ------------------------------------------------------- canciones que gustan

  /// "Canciones que te gustan" **no es una playlist**: es la biblioteca guardada
  /// y no aparece en `GET /me/playlists`. Se lee por su propio endpoint.
  ///
  /// Comprobado contra la API: sigue siendo `GET /v1/me/tracks`. El
  /// `/v1/me/library` que introdujo la migración de febrero de 2026 solo acepta
  /// PUT y DELETE (guardar y quitar); un GET ahí devuelve 405.
  /// Requiere el permiso `user-library-read`.
  Future<ApiPage<Track>> savedTracks({int limit = 50, int offset = 0}) async {
    final j = await _request('GET', '/me/tracks',
        query: {'limit': '$limit', 'offset': '$offset'}) as Map<String, dynamic>;
    final raw = (j['items'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          // Mismo criterio que en las playlists: se aceptan las dos claves.
          .map((it) => Track.fromJson(
              (it['track'] ?? it['item']) as Map<String, dynamic>?))
          .whereType<Track>()
          .toList(),
      hasMore: j['next'] != null,
      rawCount: raw.length,
      total: (j['total'] as num?)?.toInt(),
    );
  }

  /// ¿Están estas canciones en la biblioteca? Devuelve un booleano por cada
  /// uri, **en el mismo orden** en que se pasaron.
  ///
  /// ⚠️ Comprobado contra la API: va por `/me/library/contains` y pide **uris
  /// completas** (`spotify:track:…`), no ids — un id suelto da 400 "Invalid
  /// Spotify URI". El `/me/tracks/contains` de siempre ahora responde 403.
  Future<List<bool>> savedContains(List<String> uris) async {
    if (uris.isEmpty) return const [];
    final j = await _request('GET', '/me/library/contains',
        query: {'uris': uris.join(',')}) as List<dynamic>;
    return j.map((e) => e == true).toList();
  }

  /// Guarda en "Canciones que te gustan". Requiere `user-library-modify`.
  ///
  /// ⚠️ Las uris van en la **query**, no en el cuerpo: un `{"uris": [...]}` en
  /// el body devuelve 400 "Missing required field: uris".
  Future<void> saveTracks(List<String> uris) =>
      _request('PUT', '/me/library', query: {'uris': uris.join(',')});

  Future<void> removeSavedTracks(List<String> uris) =>
      _request('DELETE', '/me/library', query: {'uris': uris.join(',')});

  /// Contexto de reproducción de las canciones guardadas. No hay un `uri` que
  /// devuelva la API para esto: es el que usa el propio cliente de Spotify.
  static String likedContextUri(String userId) => 'spotify:user:$userId:collection';

  // -------------------------------------------------------- (playlists, cont.)

  Future<void> addToPlaylist(String id, List<String> uris) =>
      _request('POST', '/playlists/$id/items', body: {'uris': uris});

  Future<void> removeFromPlaylist(String id, List<String> uris) => _request(
        'DELETE',
        '/playlists/$id/items',
        body: {'tracks': [for (final u in uris) {'uri': u}]},
      );

  /// ⚠️ `POST /me/playlists`, no `/users/{id}/playlists` (que da 403).
  /// Comprobado contra la API: responde 201 con la playlist ya creada.
  Future<Playlist> createPlaylist(String name, {bool public = false}) async {
    final j = await _request('POST', '/me/playlists',
        body: {'name': name, 'public': public}) as Map<String, dynamic>;
    return Playlist.fromJson(j);
  }

  /// Borrar una playlist en Spotify **es dejar de seguirla**: no existe ningún
  /// endpoint que la destruya. Para las tuyas el efecto visible es el mismo
  /// (desaparece de tu biblioteca y se puede recuperar desde la web durante
  /// unos días); para las ajenas, la quitas de tu lista sin tocar el original.
  ///
  /// Comprobado contra la API: `DELETE /playlists/{id}/followers` → 200.
  Future<void> unfollowPlaylist(String id) =>
      _request('DELETE', '/playlists/$id/followers');

  // ---------------------------------------------------------------- portada

  /// Algunos endpoints están capados en Modo Desarrollo y contestan 400 si el
  /// `limit` se pasa (a `/search` le pusieron un tope de 10). No hay forma de
  /// saber el tope de antemano, así que se pide lo que interesa y se reintenta
  /// con 10 —lo único garantizado— si lo rechaza.
  Future<Map<String, dynamic>> _listaConTope(
    String path,
    int limit, [
    Map<String, String>? extra,
  ]) async {
    try {
      return await _request('GET', path,
          query: {'limit': '$limit', ...?extra}) as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.status != 400) rethrow;
      return await _request('GET', path,
          query: {'limit': '10', ...?extra}) as Map<String, dynamic>;
    }
  }

  /// Lo que más escuchas. [timeRange] es `short_term` (4 semanas),
  /// `medium_term` (6 meses) o `long_term` (años). Requiere `user-top-read`.
  Future<List<Track>> topTracks({
    String timeRange = 'short_term',
    int limit = 20,
  }) async {
    final j = await _listaConTope('/me/top/tracks', limit, {'time_range': timeRange});
    return ((j['items'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>?))
        .whereType<Track>()
        .toList();
  }

  Future<List<Artist>> topArtists({
    String timeRange = 'short_term',
    int limit = 20,
  }) async {
    final j = await _listaConTope('/me/top/artists', limit, {'time_range': timeRange});
    return ((j['items'] as List<dynamic>?) ?? const [])
        .map((a) => Artist.fromJson(a as Map<String, dynamic>?))
        .whereType<Artist>()
        .toList();
  }

  /// Las canciones más populares de un artista, con su duración.
  ///
  /// Devuelve **10 como mucho**: es el tope del endpoint, no un límite nuestro.
  ///
  /// ✅ **Funciona en Modo Desarrollo**, comprobado con
  /// `dart run tool/probe_artist.dart` contra la cuenta real (200, y las de la
  /// ficha del artista y sus álbumes también). Merece decirlo porque no era
  /// evidente: aquí `/v1/tracks?ids=` da 403 y las canciones de una playlist
  /// ajena también, así que **poder reproducir algo no implica poder leerlo** y
  /// había que comprobarlo antes de construir una pantalla encima.
  ///
  /// `market=from_token` hace que Spotify devuelva las populares **en el país
  /// de la cuenta**, que es lo que el usuario espera ver.
  Future<List<Track>> artistTopTracks(String id) async {
    final j = await _request('GET', '/artists/$id/top-tracks',
        query: {'market': 'from_token'}) as Map<String, dynamic>;
    return ((j['tracks'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>?))
        .whereType<Track>()
        .toList();
  }

  /// Obtiene los datos completos de una lista de canciones por sus IDs.
  /// Se realizan peticiones a `GET /v1/tracks?ids=` en lotes de 50 máximo.
  Future<List<Track>> tracks(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final idsLimpios = ids.map((id) => id.startsWith('spotify:track:') ? id.substring(14) : id).toList();
    final resultado = <Track>[];

    for (var i = 0; i < idsLimpios.length; i += 50) {
      final lote = idsLimpios.sublist(i, i + 50 > idsLimpios.length ? idsLimpios.length : i + 50);
      final j = await _request('GET', '/tracks', query: {'ids': lote.join(',')}) as Map<String, dynamic>?;
      if (j == null) continue;
      final raw = (j['tracks'] as List<dynamic>?) ?? const [];
      for (final item in raw) {
        final t = Track.fromJson(item as Map<String, dynamic>?);
        if (t != null) resultado.add(t);
      }
    }
    return resultado;
  }

  /// Obtiene las pistas de un álbum por su ID (`GET /v1/albums/{id}`).
  ///
  /// Pide el álbum completo para rellenar el nombre del álbum y las imágenes
  /// (`artSmall`/`artMedium`) en los objetos de pista simplificados devueltos.
  Future<List<Track>> albumTracks(String id) async {
    final albumId = id.startsWith('spotify:album:') ? id.substring(14) : id;
    final j = await _request('GET', '/albums/$albumId') as Map<String, dynamic>?;
    if (j == null) return const [];
    final images = j['images'] as List<dynamic>?;
    final albumName = (j['name'] as String?) ?? '';
    final artSmall = pickImage(images, 64);
    final artMedium = pickImage(images, 300);
    final tracksObj = j['tracks'] as Map<String, dynamic>?;
    final raw = (tracksObj?['items'] as List<dynamic>?) ?? (j['items'] as List<dynamic>?) ?? const [];
    return raw.map((t) {
      final track = Track.fromJson(t as Map<String, dynamic>?);
      if (track == null) return null;
      return track.copyWith(
        album: track.album.isEmpty ? albumName : track.album,
        artSmall: track.artSmall ?? artSmall,
        artMedium: track.artMedium ?? artMedium,
      );
    }).whereType<Track>().toList();
  }

  /// Álbumes recién publicados en el catálogo global de Spotify.
  ///
  /// No es personalizado a los gustos del usuario —eso es justo lo que hacía
  /// `/recommendations`, retirado (404)— pero es la única fuente de
  /// "novedades" que Modo Desarrollo deja usar hoy. Comprobado con
  /// `tool/probe_home.dart`: 200, a diferencia de `/browse/featured-playlists`
  /// (404, el endpoint ya ni existe).
  Future<List<Album>> newReleases({int limit = 20}) async {
    final j = await _listaConTope('/browse/new-releases', limit);
    final albums = j['albums'] as Map<String, dynamic>?;
    return ((albums?['items'] as List<dynamic>?) ?? const [])
        .map((a) => Album.fromJson(a as Map<String, dynamic>?))
        .whereType<Album>()
        .toList();
  }

  /// Historial reciente, **sin repetidas**: si has puesto la misma canción
  /// cuatro veces seguidas, Spotify la devuelve cuatro veces y una fila de
  /// "vuelve a escuchar" con la misma carátula cuatro veces no sirve de nada.
  /// Requiere `user-read-recently-played`.
  Future<List<Track>> recentlyPlayed({int limit = 20}) async {
    final j = await _listaConTope('/me/player/recently-played', limit);
    final vistas = <String>{};
    final out = <Track>[];
    for (final it in ((j['items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()) {
      // Misma precaución que en las playlists: la clave se renombró a `item`.
      final t = Track.fromJson((it['track'] ?? it['item']) as Map<String, dynamic>?);
      if (t == null || !vistas.add(t.uri)) continue;
      out.add(t);
    }
    return out;
  }

  // --------------------------------------------------------------- búsqueda

  /// ⚠️ En Modo Desarrollo `limit` está capado a **10** (antes 50) y su valor
  /// por defecto es 5. Para ver más resultados hay que paginar con [offset].
  Future<ApiPage<Track>> searchTracks(
    String query, {
    int limit = 10,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty) return ApiPage<Track>.empty();
    final j = await _request('GET', '/search', query: {
      'q': query,
      'type': 'track',
      'limit': '${limit.clamp(1, 10)}',
      'offset': '$offset',
    }) as Map<String, dynamic>;
    final tracks = j['tracks'] as Map<String, dynamic>?;
    final raw = (tracks?['items'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: raw
          .map((t) => Track.fromJson(t as Map<String, dynamic>?))
          .whereType<Track>()
          .toList(),
      hasMore: tracks?['next'] != null,
      rawCount: raw.length,
    );
  }
}
