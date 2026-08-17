import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  bool get isDeviceNotFound => status == 404;

  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}

class SpotifyApi {
  SpotifyApi(this.auth);

  final SpotifyAuth auth;
  final http.Client _http = http.Client();

  static const _base = 'api.spotify.com';

  static const _plazo = Duration(seconds: 20);

  static const _esperaMaximaEn429 = Duration(seconds: 10);

  final Map<String, DateTime> _penalizadas = {};

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

  bool get reproduccionLimitada => esperaDe('/me/player') != null;

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

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retryOn401 = true,
  }) async {
    if (esperaDe(path) != null) throw ApiException(429, avisoDeCuota ?? '');

    final token = await auth.accessToken();
    final uri = Uri.https(_base, '/v1$path', query);
    final req = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

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
      if (wait > _esperaMaximaEn429.inSeconds) {
        _penalizadas[_familia(path)] = DateTime.now().add(Duration(seconds: wait));
        throw ApiException(429, avisoDeCuota ?? '');
      }
      await Future<void>.delayed(Duration(seconds: wait + 1));
      return _request(method, path, query: query, body: body, retryOn401: retryOn401);
    }
    if (res.statusCode == 410) {
      throw ApiException(
        410,
        'Spotify ha retirado temporalmente esta parte de la API (410). Suele ir '
        'con la cuota agotada del Modo Desarrollo y se recupera solo; mientras '
        'tanto, la reproducción sigue funcionando.',
      );
    }
    _penalizadas.remove(_familia(path));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _extractMessage(res));
    }
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;

    if (!_looksLikeJson(res)) return null;

    try {
      final text = utf8.decode(res.bodyBytes);
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } on FormatException catch (e) {
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

  static bool _looksLikeJson(http.Response res) {
    final type = res.headers['content-type'];
    if (type != null && type.contains('json')) return true;
    if (type != null && type.isNotEmpty) return false;
    for (final b in res.bodyBytes) {
      if (b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) continue;
      return b == 0x7b || b == 0x5b;
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

  Future<Map<String, dynamic>> me() async =>
      (await _request('GET', '/me')) as Map<String, dynamic>;

  Future<Playback?> playbackState() async {
    final j = await _request('GET', '/me/player');
    if (j == null) return null;
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

  Future<ApiPage<Track>> playlistItems(String id, {int limit = 50, int offset = 0}) async {
    final j = await _request('GET', '/playlists/$id/items',
        query: {'limit': '$limit', 'offset': '$offset'}) as Map<String, dynamic>;
    final raw = (j['items'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map((it) => Track.fromJson(
              (it['item'] ?? it['track']) as Map<String, dynamic>?))
          .whereType<Track>()
          .toList(),
      hasMore: j['next'] != null,
      rawCount: raw.length,
    );
  }

  Future<ApiPage<Track>> savedTracks({int limit = 50, int offset = 0}) async {
    final j = await _request('GET', '/me/tracks',
        query: {'limit': '$limit', 'offset': '$offset'}) as Map<String, dynamic>;
    final raw = (j['items'] as List<dynamic>?) ?? const [];
    return ApiPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map((it) => Track.fromJson(
              (it['track'] ?? it['item']) as Map<String, dynamic>?))
          .whereType<Track>()
          .toList(),
      hasMore: j['next'] != null,
      rawCount: raw.length,
      total: (j['total'] as num?)?.toInt(),
    );
  }

  Future<List<bool>> savedContains(List<String> uris) async {
    if (uris.isEmpty) return const [];
    final j = await _request('GET', '/me/library/contains',
        query: {'uris': uris.join(',')}) as List<dynamic>;
    return j.map((e) => e == true).toList();
  }

  Future<void> saveTracks(List<String> uris) =>
      _request('PUT', '/me/library', query: {'uris': uris.join(',')});

  Future<void> removeSavedTracks(List<String> uris) =>
      _request('DELETE', '/me/library', query: {'uris': uris.join(',')});

  static String likedContextUri(String userId) => 'spotify:user:$userId:collection';

  Future<void> addToPlaylist(String id, List<String> uris) =>
      _request('POST', '/playlists/$id/items', body: {'uris': uris});

  Future<void> removeFromPlaylist(String id, List<String> uris) => _request(
        'DELETE',
        '/playlists/$id/items',
        body: {'tracks': [for (final u in uris) {'uri': u}]},
      );

  Future<Playlist> createPlaylist(String name, {bool public = false}) async {
    final j = await _request('POST', '/me/playlists',
        body: {'name': name, 'public': public}) as Map<String, dynamic>;
    return Playlist.fromJson(j);
  }

  Future<void> unfollowPlaylist(String id) =>
      _request('DELETE', '/playlists/$id/followers');

  Future<void> followPlaylist(String id) =>
      _request('PUT', '/playlists/$id/followers');

  Future<bool> isFollowingPlaylist(String id, String userId) async {
    final j = await _request('GET', '/playlists/$id/followers/contains',
        query: {'ids': userId}) as List<dynamic>;
    return j.isNotEmpty && j.first == true;
  }

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

  Future<List<Track>> artistTopTracks(String id) async {
    final j = await _request('GET', '/artists/$id/top-tracks',
        query: {'market': 'from_token'}) as Map<String, dynamic>;
    return ((j['tracks'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>?))
        .whereType<Track>()
        .toList();
  }

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

  Future<List<Album>> newReleases({int limit = 20}) async {
    final j = await _listaConTope('/browse/new-releases', limit);
    final albums = j['albums'] as Map<String, dynamic>?;
    return ((albums?['items'] as List<dynamic>?) ?? const [])
        .map((a) => Album.fromJson(a as Map<String, dynamic>?))
        .whereType<Album>()
        .toList();
  }

  Future<List<Track>> recentlyPlayed({int limit = 20}) async {
    final j = await _listaConTope('/me/player/recently-played', limit);
    final vistas = <String>{};
    final out = <Track>[];
    for (final it in ((j['items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final t = Track.fromJson((it['track'] ?? it['item']) as Map<String, dynamic>?);
      if (t == null || !vistas.add(t.uri)) continue;
      out.add(t);
    }
    return out;
  }

  Future<SearchResults> search(
    String query, {
    List<String> types = const ['track', 'playlist'],
    int limit = 10,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty || types.isEmpty) return const SearchResults.empty();
    final j = await _request('GET', '/search', query: {
      'q': query,
      'type': types.join(','),
      'limit': '${limit.clamp(1, 10)}',
      'offset': '$offset',
    }) as Map<String, dynamic>;

    ApiPage<Track> trackPage = const ApiPage.empty();
    if (j.containsKey('tracks') && j['tracks'] is Map<String, dynamic>) {
      final tracks = j['tracks'] as Map<String, dynamic>;
      final raw = (tracks['items'] as List<dynamic>?) ?? const [];
      trackPage = ApiPage(
        items: raw
            .map((t) => Track.fromJson(t as Map<String, dynamic>?))
            .whereType<Track>()
            .toList(),
        hasMore: tracks['next'] != null,
        rawCount: raw.length,
        total: (tracks['total'] as num?)?.toInt(),
      );
    }

    ApiPage<Playlist> playlistPage = const ApiPage.empty();
    if (j.containsKey('playlists') && j['playlists'] is Map<String, dynamic>) {
      final playlists = j['playlists'] as Map<String, dynamic>;
      final raw = (playlists['items'] as List<dynamic>?) ?? const [];
      playlistPage = ApiPage(
        items: raw
            .whereType<Map<String, dynamic>>()
            .map(Playlist.fromJson)
            .toList(),
        hasMore: playlists['next'] != null,
        rawCount: raw.length,
        total: (playlists['total'] as num?)?.toInt(),
      );
    }

    return SearchResults(
      tracks: trackPage,
      playlists: playlistPage,
    );
  }

  Future<ApiPage<Track>> searchTracks(
    String query, {
    int limit = 10,
    int offset = 0,
  }) async {
    final res = await search(query, types: const ['track'], limit: limit, offset: offset);
    return res.tracks;
  }
}
