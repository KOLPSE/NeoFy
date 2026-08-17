import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/ui/search_screen.dart';
import 'package:neofy/ui/track_tile.dart';

class _FakeConfig extends AppConfig {
  _FakeConfig() : super(initialVolume: 50);

  @override
  Future<void> save() async {}
}

class _FakeAuth extends SpotifyAuth {
  _FakeAuth() : super(AppConfig());

  @override
  bool hasScope(String scope) => true;
}

class _MockSpotifyApi extends SpotifyApi {
  _MockSpotifyApi() : super(_FakeAuth());

  final List<Map<String, dynamic>> llamadasSearch = [];
  SearchResults searchResult = const SearchResults.empty();

  @override
  Future<SearchResults> search(
    String query, {
    List<String> types = const ['track', 'playlist'],
    int limit = 10,
    int offset = 0,
  }) async {
    llamadasSearch.add({
      'query': query,
      'types': types,
      'limit': limit,
      'offset': offset,
    });
    return searchResult;
  }
}

const _track1 = Track(
  id: 't1',
  uri: 'spotify:track:t1',
  name: 'Track Uno',
  artists: 'Artista A',
  album: 'Album 1',
  artSmall: null,
  artMedium: null,
  durationMs: 180000,
  isLocal: false,
  popularity: 40,
);

const _track2 = Track(
  id: 't2',
  uri: 'spotify:track:t2',
  name: 'Track Dos (Hit)',
  artists: 'Artista B',
  album: 'Album 2',
  artSmall: null,
  artMedium: null,
  durationMs: 210000,
  isLocal: false,
  popularity: 95,
);

const _playlist1 = Playlist(
  id: 'p1',
  uri: 'spotify:playlist:p1',
  name: 'Lofi Beats',
  owner: 'Spotify',
  ownerId: 'spotify',
  art: null,
  trackCount: 150,
);

const _playlist2 = Playlist(
  id: 'p2',
  uri: 'spotify:playlist:p2',
  name: 'Lofi Chill',
  owner: 'Usuario',
  ownerId: 'user1',
  art: null,
  trackCount: 45,
);

void main() {
  late _MockSpotifyApi api;
  late _FakeConfig config;
  late PlayerController player;
  late LikedStore likes;

  setUp(() {
    api = _MockSpotifyApi();
    config = _FakeConfig();
    player = PlayerController(api, config);
    likes = LikedStore(api: api, auth: _FakeAuth());
  });

  tearDown(() {
    player.dispose();
    likes.dispose();
  });

  Widget crearApp({void Function(Playlist)? onAbrirPlaylist, bool autofocus = false}) {
    return MaterialApp(
      home: Scaffold(
        body: SearchScreen(
          api: api,
          player: player,
          playlists: const [],
          likes: likes,
          onAbrirPlaylist: onAbrirPlaylist,
          autofocus: autofocus,
        ),
      ),
    );
  }

  Future<void> buscar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField), texto);
    await tester.pump(const Duration(milliseconds: 400));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets('muestra estado inicial con barra de búsqueda y los 4 chips de filtro', (tester) async {
    await tester.pumpWidget(crearApp());

    expect(find.text('Escribe para buscar en Spotify.'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Todo'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Canciones'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Playlists'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Más escuchadas'), findsOneWidget);

    final todoChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Todo'));
    expect(todoChip.selected, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en filtro Todo busca canciones y playlists y las muestra en secciones', (tester) async {
    api.searchResult = const SearchResults(
      tracks: ApiPage(items: [_track1], hasMore: false, rawCount: 1),
      playlists: ApiPage(items: [_playlist1], hasMore: false, rawCount: 1),
    );

    await tester.pumpWidget(crearApp());
    await buscar(tester, 'lofi');

    expect(api.llamadasSearch.length, 1);
    expect(api.llamadasSearch.first['types'], ['track', 'playlist']);
    expect(api.llamadasSearch.first['query'], 'lofi');

    expect(find.text('Playlists'), findsWidgets);
    expect(find.text('Lofi Beats'), findsOneWidget);
    expect(find.text('Canciones'), findsWidgets);
    expect(find.text('Track Uno'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('al pulsar en una playlist llama a onAbrirPlaylist', (tester) async {
    Playlist? abierta;
    api.searchResult = const SearchResults(
      tracks: ApiPage.empty(),
      playlists: ApiPage(items: [_playlist1], hasMore: false, rawCount: 1),
    );

    await tester.pumpWidget(crearApp(onAbrirPlaylist: (pl) => abierta = pl));
    await buscar(tester, 'lofi');

    await tester.tap(find.text('Lofi Beats'));
    await tester.pumpAndSettle();

    expect(abierta, isNotNull);
    expect(abierta!.id, 'p1');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('filtro Playlists pide solo playlists y muestra sus resultados', (tester) async {
    api.searchResult = const SearchResults(
      tracks: ApiPage(items: [_track1], hasMore: false, rawCount: 1),
      playlists: ApiPage(items: [_playlist1, _playlist2], hasMore: false, rawCount: 2),
    );

    await tester.pumpWidget(crearApp());

    await tester.tap(find.widgetWithText(ChoiceChip, 'Playlists'));
    await tester.pumpAndSettle();

    await buscar(tester, 'lofi');

    expect(api.llamadasSearch.last['types'], ['playlist']);
    expect(find.byType(PlaylistSearchTile), findsNWidgets(2));
    expect(find.byType(TrackTile), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('filtro Canciones pide solo canciones y muestra sus resultados', (tester) async {
    api.searchResult = const SearchResults(
      tracks: ApiPage(items: [_track1, _track2], hasMore: false, rawCount: 2),
      playlists: ApiPage(items: [_playlist1], hasMore: false, rawCount: 1),
    );

    await tester.pumpWidget(crearApp());

    await tester.tap(find.widgetWithText(ChoiceChip, 'Canciones'));
    await tester.pumpAndSettle();

    await buscar(tester, 'rock');

    expect(api.llamadasSearch.last['types'], ['track']);
    expect(find.byType(TrackTile), findsNWidgets(2));
    expect(find.byType(PlaylistSearchTile), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('filtro Más escuchadas ordena las canciones por popularidad descendente', (tester) async {
    api.searchResult = const SearchResults(
      tracks: ApiPage(items: [_track1, _track2], hasMore: false, rawCount: 2),
    );

    await tester.pumpWidget(crearApp());

    await tester.tap(find.widgetWithText(ChoiceChip, 'Más escuchadas'));
    await tester.pumpAndSettle();

    await buscar(tester, 'hits');

    final tiles = tester.widgetList<TrackTile>(find.byType(TrackTile)).toList();
    expect(tiles.length, 2);
    expect(tiles[0].track.name, 'Track Dos (Hit)');
    expect(tiles[0].leadingNumber, 1);
    expect(tiles[1].track.name, 'Track Uno');
    expect(tiles[1].leadingNumber, 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('botón Ver más resultados pagina con offset incrementado', (tester) async {
    api.searchResult = const SearchResults(
      tracks: ApiPage(items: [_track1], hasMore: true, rawCount: 10),
    );

    await tester.pumpWidget(crearApp());

    await tester.tap(find.widgetWithText(ChoiceChip, 'Canciones'));
    await tester.pumpAndSettle();

    await buscar(tester, 'chill');

    expect(find.text('Ver más resultados'), findsOneWidget);

    await tester.tap(find.text('Ver más resultados'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(api.llamadasSearch.length, 2);
    expect(api.llamadasSearch.last['offset'], 10);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el botón de limpiar vacía el campo y resetea los resultados', (tester) async {
    api.searchResult = const SearchResults(
      tracks: ApiPage(items: [_track1], hasMore: false, rawCount: 1),
    );

    await tester.pumpWidget(crearApp());
    await buscar(tester, 'algo');

    expect(find.byType(TrackTile), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.byType(TrackTile), findsNothing);
    expect(find.text('Escribe para buscar en Spotify.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
