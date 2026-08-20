import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/home_store.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/spotify_api.dart';

class _FakeAuth extends SpotifyAuth {
  _FakeAuth() : super(AppConfig());

  @override
  bool hasScope(String scope) => true;
}

const _pista = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Una canción',
  artists: 'Un artista',
  album: 'Un álbum',
  artSmall: null,
  artMedium: null,
  durationMs: 185000,
  isLocal: false,
);

const _artista = Artist(
  id: '1',
  uri: 'spotify:artist:1',
  name: 'Un artista',
  art: null,
);

class _FakeApi extends SpotifyApi {
  _FakeApi(super.auth, {this.novedadesFalla = false});

  final bool novedadesFalla;

  @override
  Future<List<Track>> recentlyPlayed({int limit = 20}) async => const [_pista];

  @override
  Future<List<Track>> topTracks({String timeRange = 'short_term', int limit = 20}) async =>
      const [_pista];

  @override
  Future<List<Artist>> topArtists({String timeRange = 'short_term', int limit = 20}) async =>
      const [_artista];

  @override
  Future<List<Track>> artistTopTracks(String id, {int discosDeRespaldo = 6}) async => const [];

  @override
  Future<List<Album>> newReleases({int limit = 20}) async {
    if (novedadesFalla) throw ApiException(403, 'Forbidden');
    return const [];
  }
}

void main() {
  test('si /browse/new-releases falla, el resto de la portada carga igual', () async {
    final api = _FakeApi(_FakeAuth(), novedadesFalla: true);
    final home = HomeStore(api: api, auth: _FakeAuth());

    await home.cargar();

    expect(home.error, isNull);
    expect(home.cargado, isTrue);
    expect(home.recientes, isNotEmpty);
    expect(home.masEscuchadas, isNotEmpty);
    expect(home.artistas, isNotEmpty);
    expect(home.novedades, isEmpty);
  });

  test('sin fallos, novedades también se rellena', () async {
    final api = _FakeApi(_FakeAuth());
    final home = HomeStore(api: api, auth: _FakeAuth());

    await home.cargar();

    expect(home.error, isNull);
    expect(home.recientes, isNotEmpty);
  });
}
