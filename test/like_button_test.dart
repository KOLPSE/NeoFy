import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/ui/like_button.dart';
import 'package:neofy/ui/now_playing_bar.dart';
import 'package:neofy/ui/track_tile.dart';

const _pista = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Una canción con un título razonablemente largo',
  artists: 'Un artista, Otro artista',
  album: 'Un álbum',
  artSmall: null,
  artMedium: null,
  durationMs: 185000,
  isLocal: false,
);

class _FakeConfig extends AppConfig {
  _FakeConfig() : super(initialVolume: 60);

  @override
  Future<void> save() async {}
}

/// Los scopes de verdad solo se rellenan al canjear un token, así que se
/// sobrescribe la consulta: es justo lo que distingue una sesión antigua.
class _FakeAuth extends SpotifyAuth {
  _FakeAuth({this.concede = true}) : super(AppConfig());
  final bool concede;

  @override
  bool hasScope(String scope) => concede;
}

class _FakeApi extends SpotifyApi {
  _FakeApi(super.auth);

  final List<String> llamadas = [];
  List<bool> respuestaContains = const [false];
  bool falla = false;

  @override
  Future<List<bool>> savedContains(List<String> uris) async {
    llamadas.add('contains ${uris.join(",")}');
    return respuestaContains;
  }

  @override
  Future<void> saveTracks(List<String> uris) async {
    llamadas.add('save ${uris.join(",")}');
    if (falla) throw ApiException(403, 'Insufficient client scope');
  }

  @override
  Future<void> removeSavedTracks(List<String> uris) async {
    llamadas.add('remove ${uris.join(",")}');
    if (falla) throw ApiException(403, 'Insufficient client scope');
  }
}

/// El corazón relleno: el `Icon` rojo que va bajo el recorte del líquido.
final _corazonRojo = find.byWidgetPredicate(
  (w) => w is Icon && w.icon == Icons.favorite && w.color == kColorFavorito,
);

final _corazonVacio = find.byWidgetPredicate(
  (w) => w is Icon && w.icon == Icons.favorite_border,
);

void main() {
  late _FakeApi api;
  late LikedStore store;

  LikedStore crear({bool concede = true}) {
    final auth = _FakeAuth(concede: concede);
    api = _FakeApi(auth);
    store = LikedStore(api: api, auth: auth);
    // Cancela el agrupador pendiente: si no, el test acaba con un Timer vivo.
    addTearDown(store.dispose);
    return store;
  }

  Future<void> montar(WidgetTester tester, LikedStore likes) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackTile(track: _pista, actions: const TrackActions(), likes: likes),
          ],
        ),
      ),
    ));
  }

  // El invariante de siempre: `liked_screen.dart` deduce por aritmética qué
  // fila está mirando el usuario y para eso el alto tiene que ser exacto. Un
  // botón nuevo en la fila es justo lo que podría romperlo.
  testWidgets('la fila con corazón sigue midiendo 64 px', (tester) async {
    await montar(tester, crear());
    // Hasta que no vence el agrupador de consultas queda un Timer vivo, y el
    // framework de test lo considera una fuga.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(find.byType(TrackTile)).height, 64);

    // Y lleno tampoco crece: el corazón relleno es del mismo tamaño.
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TrackTile)).height, 64);
  });

  testWidgets('sin store no se pinta corazón', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TrackTile(track: _pista, actions: TrackActions())),
    ));
    expect(find.byType(LikeButton), findsNothing);
  });

  testWidgets('empieza vacío y se rellena cuando la API dice que está guardada',
      (tester) async {
    final likes = crear();
    api.respuestaContains = const [true];
    await montar(tester, likes);

    // Antes de la respuesta no se sabe: corazón vacío, sin rojo.
    expect(_corazonRojo, findsNothing);

    // Las consultas se agrupan 120 ms para no mandar una por fila.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(api.llamadas, ['contains spotify:track:1']);
    expect(_corazonRojo, findsOneWidget);
    // El contorno sigue debajo: es lo que da el borde al corazón medio lleno.
    expect(_corazonVacio, findsOneWidget);
  });

  testWidgets('al pulsar se guarda, y el rojo va subiendo', (tester) async {
    final likes = crear();
    await montar(tester, likes);
    await tester.pump(const Duration(milliseconds: 200));
    api.llamadas.clear();

    await tester.tap(find.byType(LikeButton));
    await tester.pump();

    // ⚠️ La API pide la uri completa: un id suelto da 400 "Invalid Spotify URI".
    expect(api.llamadas, ['save spotify:track:1']);

    // A mitad de la animación el corazón está pintándose, pero aún no lleno.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_corazonRojo, findsOneWidget);

    await tester.pumpAndSettle();
    expect(likes.isSaved(_pista.uri), isTrue);
  });

  testWidgets('volver a pulsar lo quita', (tester) async {
    final likes = crear();
    api.respuestaContains = const [true];
    await montar(tester, likes);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    api.llamadas.clear();

    await tester.tap(find.byType(LikeButton));
    await tester.pumpAndSettle();

    expect(api.llamadas, ['remove spotify:track:1']);
    expect(likes.isSaved(_pista.uri), isFalse);
    expect(_corazonRojo, findsNothing);
  });

  testWidgets('si la petición falla, el corazón se deshace', (tester) async {
    final likes = crear();
    api.falla = true;
    await montar(tester, likes);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(LikeButton));
    await tester.pumpAndSettle();

    // El pintado optimista se revierte: no se queda diciendo que está guardada
    // una canción que Spotify no guardó.
    expect(likes.isSaved(_pista.uri), isFalse);
    expect(_corazonRojo, findsNothing);
    expect(find.textContaining('Spotify no dejó cambiar'), findsOneWidget);
  });

  testWidgets('sin el permiso no se llama a la API: se ofrece reautorizar',
      (tester) async {
    final likes = crear(concede: false);
    await montar(tester, likes);
    await tester.pump(const Duration(milliseconds: 200));
    api.llamadas.clear();

    await tester.tap(find.byType(LikeButton));
    await tester.pumpAndSettle();

    expect(api.llamadas, isEmpty);
    expect(find.textContaining('sin permiso para editar favoritos'), findsOneWidget);
  });

  group('LikedStore', () {
    testWidgets('seedSaved evita preguntar por lo que ya se sabe', (tester) async {
      final likes = crear();
      likes.seedSaved(['spotify:track:1']);
      await montar(tester, likes);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Ni una consulta: la biblioteca ya dijo que estaban todas guardadas.
      expect(api.llamadas, isEmpty);
      expect(_corazonRojo, findsOneWidget);
    });
  });

  group('NowPlayingBar con LikeButton', () {
    testWidgets('muestra LikeButton cuando hay pista y likes', (tester) async {
      final likes = crear();
      final config = _FakeConfig();
      final player = PlayerController(api, config);
      player.state = Playback(
        track: _pista,
        isPlaying: true,
        progressMs: 10000,
        deviceId: 'dev',
        deviceName: 'NeoFy',
        volumePercent: 50,
        shuffle: false,
        repeat: 'off',
        contextUri: null,
      );
      addTearDown(player.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NowPlayingBar(
            player: player,
            librespot: LibrespotManager(config),
            likes: likes,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(LikeButton), findsOneWidget);
    });

    testWidgets('no muestra LikeButton cuando no hay pista', (tester) async {
      final likes = crear();
      final config = _FakeConfig();
      final player = PlayerController(api, config);
      addTearDown(player.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NowPlayingBar(
            player: player,
            librespot: LibrespotManager(config),
            likes: likes,
          ),
        ),
      ));

      expect(find.byType(LikeButton), findsNothing);
    });

    testWidgets('no muestra LikeButton cuando likes es null', (tester) async {
      final config = _FakeConfig();
      final player = PlayerController(_FakeApi(_FakeAuth()), config);
      player.state = Playback(
        track: _pista,
        isPlaying: true,
        progressMs: 10000,
        deviceId: 'dev',
        deviceName: 'NeoFy',
        volumePercent: 50,
        shuffle: false,
        repeat: 'off',
        contextUri: null,
      );
      addTearDown(player.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NowPlayingBar(
            player: player,
            librespot: LibrespotManager(config),
            likes: null,
          ),
        ),
      ));

      expect(find.byType(LikeButton), findsNothing);
    });
  });
}
