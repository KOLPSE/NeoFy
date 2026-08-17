import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/followed_playlists_store.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/ui/corazon_animado.dart';
import 'package:neofy/ui/playlist_follow_button.dart';

const _playlist = Playlist(
  id: 'p1',
  uri: 'spotify:playlist:p1',
  name: 'Lofi Beats',
  owner: 'Spotify',
  ownerId: 'spotify',
  art: null,
  trackCount: 150,
);

const _propia = Playlist(
  id: 'p2',
  uri: 'spotify:playlist:p2',
  name: 'Mi lista',
  owner: 'yo',
  ownerId: 'user1',
  art: null,
  trackCount: 3,
);

class _FakeAuth extends SpotifyAuth {
  _FakeAuth({this.concede = true}) : super(AppConfig());
  final bool concede;

  @override
  bool hasScope(String scope) => concede;
}

class _FakeApi extends SpotifyApi {
  _FakeApi(super.auth);

  final List<String> llamadas = [];
  bool respuestaContains = false;
  bool falla = false;

  @override
  Future<bool> isFollowingPlaylist(String id, String userId) async {
    llamadas.add('contains $id $userId');
    return respuestaContains;
  }

  @override
  Future<void> followPlaylist(String id) async {
    llamadas.add('follow $id');
    if (falla) throw ApiException(403, 'Insufficient client scope');
  }

  @override
  Future<void> unfollowPlaylist(String id) async {
    llamadas.add('unfollow $id');
    if (falla) throw ApiException(403, 'Insufficient client scope');
  }
}

final _corazonRojo = find.byWidgetPredicate(
  (w) => w is Icon && w.icon == Icons.favorite && w.color == kColorFavorito,
);

final _corazonVacio = find.byWidgetPredicate(
  (w) => w is Icon && w.icon == Icons.favorite_border,
);

void main() {
  late _FakeApi api;
  late FollowedPlaylistsStore store;

  FollowedPlaylistsStore crear({bool concede = true, String? userId = 'yo'}) {
    final auth = _FakeAuth(concede: concede);
    api = _FakeApi(auth);
    store = FollowedPlaylistsStore(
      api: api,
      auth: auth,
      obtenerUserId: () => userId,
    );
    addTearDown(store.dispose);
    return store;
  }

  Future<void> montar(
    WidgetTester tester,
    FollowedPlaylistsStore followed, {
    Playlist playlist = _playlist,
    bool esPropia = false,
    void Function(Playlist, bool)? onCambio,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaylistFollowButton(
          followed: followed,
          playlist: playlist,
          esPropia: esPropia,
          onCambio: onCambio,
        ),
      ),
    ));
  }

  testWidgets('empieza vacío y se rellena cuando la API dice que se sigue',
      (tester) async {
    final followed = crear();
    api.respuestaContains = true;
    await montar(tester, followed);

    expect(_corazonRojo, findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(api.llamadas, ['contains p1 yo']);
    expect(_corazonRojo, findsOneWidget);
    expect(_corazonVacio, findsOneWidget);
  });

  testWidgets('al pulsar se sigue la playlist', (tester) async {
    final followed = crear();
    Playlist? avisada;
    bool? seguidaTrasCambio;
    await montar(tester, followed, onCambio: (pl, seguida) {
      avisada = pl;
      seguidaTrasCambio = seguida;
    });
    await tester.pumpAndSettle();
    api.llamadas.clear();

    await tester.tap(find.byType(PlaylistFollowButton));
    await tester.pumpAndSettle();

    expect(api.llamadas, ['follow p1']);
    expect(followed.isFollowed('p1'), isTrue);
    expect(_corazonRojo, findsOneWidget);
    expect(avisada?.id, 'p1');
    expect(seguidaTrasCambio, isTrue);
  });

  testWidgets('volver a pulsar deja de seguirla', (tester) async {
    final followed = crear();
    api.respuestaContains = true;
    await montar(tester, followed);
    await tester.pumpAndSettle();
    api.llamadas.clear();

    await tester.tap(find.byType(PlaylistFollowButton));
    await tester.pumpAndSettle();

    expect(api.llamadas, ['unfollow p1']);
    expect(followed.isFollowed('p1'), isFalse);
    expect(_corazonRojo, findsNothing);
  });

  testWidgets('si la petición falla, se deshace', (tester) async {
    final followed = crear();
    api.falla = true;
    await montar(tester, followed);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PlaylistFollowButton));
    await tester.pumpAndSettle();

    expect(followed.isFollowed('p1'), isFalse);
    expect(_corazonRojo, findsNothing);
    expect(find.textContaining('Spotify no dejó cambiar'), findsOneWidget);
  });

  testWidgets('sin permiso se ofrece reautorizar y no llama a la API',
      (tester) async {
    final followed = crear(concede: false);
    await montar(tester, followed);
    await tester.pumpAndSettle();
    api.llamadas.clear();

    await tester.tap(find.byType(PlaylistFollowButton));
    await tester.pumpAndSettle();

    expect(api.llamadas, isEmpty);
    expect(find.textContaining('sin permiso para editar tus playlists'), findsOneWidget);
  });

  testWidgets('una playlist propia ya seguida no se puede quitar desde aquí',
      (tester) async {
    final followed = crear();
    followed.seedFollowed(['p2']);
    await montar(tester, followed, playlist: _propia, esPropia: true);
    await tester.pumpAndSettle();
    api.llamadas.clear();

    await tester.tap(find.byType(PlaylistFollowButton));
    await tester.pumpAndSettle();

    expect(api.llamadas, isEmpty);
    expect(followed.isFollowed('p2'), isTrue);
    expect(find.textContaining('usa el menú'), findsOneWidget);
  });

  group('FollowedPlaylistsStore', () {
    testWidgets('seedFollowed evita preguntar por lo que ya se sabe',
        (tester) async {
      final followed = crear();
      followed.seedFollowed(['p1']);
      await montar(tester, followed);
      await tester.pumpAndSettle();

      expect(api.llamadas, isEmpty);
      expect(_corazonRojo, findsOneWidget);
    });
  });
}
