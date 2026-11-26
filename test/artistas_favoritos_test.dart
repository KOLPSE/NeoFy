import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/artistas_favoritos_store.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/ui/artist_favorite_button.dart';

class _AuthPrueba extends SpotifyAuth {
  _AuthPrueba({this.scopes = const {
    kScopeFollowRead,
    kScopeFollowModify,
  }}) : super(AppConfig());

  Set<String> scopes;

  @override
  bool get isLoggedIn => true;

  @override
  bool hasScope(String scope) => scopes.contains(scope);
}

class _ApiArtistasPrueba extends SpotifyApi {
  _ApiArtistasPrueba(super.auth);

  final List<String> seguidosEnSpotify = [];
  final Map<String, Artist> catalogo = {};
  final List<String?> cursorsPedidos = [];
  bool fallarAlSeguir = false;
  bool fallarAlDejar = false;

  @override
  Future<({List<Artist> items, String? nextAfter})> followedArtists({
    int limit = 50,
    String? after,
  }) async {
    cursorsPedidos.add(after);
    if (after == null) {
      return (
        items: const [
          Artist(
            id: 'a1',
            uri: 'spotify:artist:a1',
            name: 'Artista 1',
            art: 'http://art/a1',
          ),
        ],
        nextAfter: 'cursor-2',
      );
    }
    return (
      items: const [
        Artist(
          id: 'a2',
          uri: 'spotify:artist:a2',
          name: 'Artista 2',
          art: null,
          artGrande: 'http://art/a2-big',
        ),
      ],
      nextAfter: null,
    );
  }

  @override
  Future<void> followArtist(String id) async {
    if (fallarAlSeguir) throw ApiException(500, 'error al seguir');
    seguidosEnSpotify.add(id);
  }

  @override
  Future<void> unfollowArtist(String id) async {
    if (fallarAlDejar) throw ApiException(500, 'error al dejar');
    seguidosEnSpotify.remove(id);
  }

  @override
  Future<Artist> artist(String id) async {
    return catalogo[id] ??
        Artist(
          id: id,
          uri: 'spotify:artist:$id',
          name: 'Artista $id',
          art: 'http://art/$id-resolved',
          artGrande: 'http://art/$id-resolved-big',
        );
  }
}

void main() {
  test('carga paginada desde Spotify y normaliza avatar grande si falta pequeño',
      () async {
    final auth = _AuthPrueba();
    final api = _ApiArtistasPrueba(auth);
    final store = ArtistasFavoritosStore(api: api, auth: auth);
    addTearDown(store.dispose);

    await store.cargar();
    expect(api.cursorsPedidos, [null, 'cursor-2']);
    expect(store.artistas.map((a) => a.id), ['a1', 'a2']);
    expect(store.artistas[1].art, 'http://art/a2-big');
  });

  test('sin scope user-follow-read no lee y mantiene lista vacía', () async {
    final auth = _AuthPrueba(scopes: const {});
    final api = _ApiArtistasPrueba(auth);
    final store = ArtistasFavoritosStore(api: api, auth: auth);
    addTearDown(store.dispose);

    await store.cargar();
    expect(store.canRead, isFalse);
    expect(store.artistas, isEmpty);
    expect(api.cursorsPedidos, isEmpty);
  });

  test('toggle sigue, enriquece avatar al instante sin reiniciar y revierte en error',
      () async {
    final auth = _AuthPrueba();
    final api = _ApiArtistasPrueba(auth);
    final store = ArtistasFavoritosStore(api: api, auth: auth);
    addTearDown(store.dispose);

    const sinFoto = Artist(
      id: 'dani',
      uri: 'spotify:artist:dani',
      name: 'Dani Martín',
      art: null,
    );

    await store.toggle(sinFoto);
    expect(store.esFavorito('dani'), isTrue);
    expect(api.seguidosEnSpotify, ['dani']);

    // El enriquecimiento asíncrono de avatar rellena la foto al vuelo.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(store.artistas.first.art, 'http://art/dani-resolved');

    // Si falla dejar de seguir, revierte el estado optimista.
    api.fallarAlDejar = true;
    await expectLater(store.toggle(sinFoto), throwsA(isA<ApiException>()));
    expect(store.esFavorito('dani'), isTrue);

    api.fallarAlDejar = false;
    await store.toggle(sinFoto);
    expect(store.esFavorito('dani'), isFalse);
  });

  testWidgets('ArtistFavoriteButton muestra Seguir / Siguiendo y avisa si falta permiso',
      (t) async {
    final auth = _AuthPrueba();
    final api = _ApiArtistasPrueba(auth);
    var reauthCalls = 0;
    final store = ArtistasFavoritosStore(
      api: api,
      auth: auth,
      onReauth: () async => reauthCalls++,
    );
    addTearDown(store.dispose);

    const artista = Artist(
      id: 'skr',
      uri: 'spotify:artist:skr',
      name: 'Skrillex',
      art: 'http://art/skr',
    );

    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistFavoriteButton(favoritos: store, artista: artista),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Seguir'), findsOneWidget);
    await t.tap(find.text('Seguir'));
    await t.pumpAndSettle();
    expect(find.text('Siguiendo'), findsOneWidget);

    // Si la sesión no tiene scope de escritura, muestra aviso para reautorizar.
    auth.scopes = const {kScopeFollowRead};
    await t.tap(find.text('Siguiendo'));
    await t.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    await t.tap(find.text('Iniciar sesión'));
    await t.pumpAndSettle();
    expect(reauthCalls, 1);
  });
}
