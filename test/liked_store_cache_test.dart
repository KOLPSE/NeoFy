import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/spotify_api.dart';

const _una = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Las Ganas',
  artists: 'Pignoise',
  album: 'Disco',
  artSmall: null,
  artMedium: null,
  durationMs: 167000,
  isLocal: false,
);

const _otra = Track(
  id: '2',
  uri: 'spotify:track:2',
  name: 'Cama Vacía',
  artists: 'Pignoise',
  album: 'Disco',
  artSmall: null,
  artMedium: null,
  durationMs: 240000,
  isLocal: false,
);

class _FakeAuth extends SpotifyAuth {
  _FakeAuth() : super(AppConfig());

  @override
  bool hasScope(String scope) => true;
}

class _FakeApi extends SpotifyApi {
  _FakeApi(super.auth);

  int cargas = 0;
  List<Track> remotas = const [_una, _otra];

  @override
  Future<ApiPage<Track>> savedTracks({int limit = 50, int offset = 0}) async {
    cargas++;
    return ApiPage(
      items: remotas,
      hasMore: false,
      rawCount: remotas.length,
      total: remotas.length,
    );
  }

  @override
  Future<void> saveTracks(List<String> uris) async {}

  @override
  Future<void> removeSavedTracks(List<String> uris) async {}
}

void main() {
  Directory dirTemporal() {
    final d = Directory('${Directory.systemTemp.path}'
        '/neofy_biblio_${DateTime.now().microsecondsSinceEpoch}');
    d.createSync(recursive: true);
    return d;
  }

  test('la primera carga se queda en disco y la siguiente no vuelve a Spotify',
      () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));
    final api = _FakeApi(_FakeAuth());

    final primero = LikedStore(api: api, auth: _FakeAuth(), directorio: dir);
    addTearDown(primero.dispose);
    await primero.cargarBiblioteca();
    expect(api.cargas, 1);
    expect(primero.biblioteca.map((t) => t.uri), [_una.uri, _otra.uri]);
    expect(File('${dir.path}/biblioteca.json').existsSync(), isTrue);

    final segundo = LikedStore(api: api, auth: _FakeAuth(), directorio: dir);
    addTearDown(segundo.dispose);
    await segundo.cargarBiblioteca();
    expect(api.cargas, 1);
    expect(segundo.bibliotecaCompleta, isTrue);
    expect(segundo.biblioteca.first.name, 'Las Ganas');
  });

  test('un me gusta nuevo se pone el primero sin recargar la lista', () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));
    final api = _FakeApi(_FakeAuth());
    final likes = LikedStore(api: api, auth: _FakeAuth(), directorio: dir);
    addTearDown(likes.dispose);
    await likes.cargarBiblioteca();

    const nueva = Track(
      id: '9',
      uri: 'spotify:track:9',
      name: 'Nueva',
      artists: 'Alguien',
      album: 'Disco',
      artSmall: null,
      artMedium: null,
      durationMs: 120000,
      isLocal: false,
    );
    await likes.toggle(nueva.uri, pista: nueva);

    expect(likes.biblioteca.first.uri, nueva.uri);
    expect(likes.biblioteca.length, 3);
    expect(likes.isSaved(nueva.uri), isTrue);
  });

  test('quitar el corazón saca la canción de la lista en caliente', () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));
    final api = _FakeApi(_FakeAuth());
    final likes = LikedStore(api: api, auth: _FakeAuth(), directorio: dir);
    addTearDown(likes.dispose);
    await likes.cargarBiblioteca();

    await likes.toggle(_una.uri, pista: _una);
    expect(likes.biblioteca.any((t) => t.uri == _una.uri), isFalse);
    expect(likes.isSaved(_una.uri), isFalse);
  });

  test('el fichero es JSON plano, no un volcado de la API', () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));
    final likes =
        LikedStore(api: _FakeApi(_FakeAuth()), auth: _FakeAuth(), directorio: dir);
    addTearDown(likes.dispose);
    await likes.cargarBiblioteca();

    final map = jsonDecode(
        File('${dir.path}/biblioteca.json').readAsStringSync()) as Map;
    expect(map['pistas'], isA<List>());
    expect((map['pistas'] as List).first['uri'], _una.uri);
  });
}
