import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/ui/now_playing_bar.dart';

class _ConfiguracionFalsa extends AppConfig {
  _ConfiguracionFalsa() : super(initialVolume: 60);

  @override
  Future<void> save() async {}
}

class _ApiFalsaInteligente extends SpotifyApi {
  _ApiFalsaInteligente() : super(SpotifyAuth(AppConfig()));

  final List<String> llamadas = [];
  List<Device> dispositivos = const [];
  bool lanzarErrorEnArtistas = false;
  bool lanzarErrorGlobal = false;

  List<Artist> artistasTopMock = const [
    Artist(id: 'artista1', uri: 'spotify:artist:1', name: 'Artista Uno', art: null),
    Artist(id: 'artista2', uri: 'spotify:artist:2', name: 'Artista Dos', art: null),
  ];

  Map<String, List<Track>> pistasTopArtistaMock = {
    'artista1': const [
      Track(id: 'rec1', uri: 'spotify:track:rec1', name: 'Recomendada 1', artists: 'Artista Uno', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
      Track(id: 'rec2', uri: 'spotify:track:rec2', name: 'Recomendada 2', artists: 'Artista Uno', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
    ],
    'artista2': const [
      Track(id: 'rec3', uri: 'spotify:track:rec3', name: 'Recomendada 3', artists: 'Artista Dos', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
    ],
  };

  List<Track> pistasTopMock = const [
    Track(id: 'top1', uri: 'spotify:track:top1', name: 'Conocida 1', artists: 'Artista Top', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
  ];

  List<Track> recientesMock = const [
    Track(id: 'recplayed1', uri: 'spotify:track:recplayed1', name: 'Conocida 2', artists: 'Artista Rec', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
  ];

  @override
  Future<List<Device>> devices() async => dispositivos;

  @override
  Future<void> setShuffle(bool on) async {
    llamadas.add('setShuffle $on');
  }

  @override
  Future<void> play({
    String? deviceId,
    String? contextUri,
    List<String>? uris,
    int? offsetPosition,
    String? offsetUri,
    int? positionMs,
  }) async {
    if (lanzarErrorGlobal) throw ApiException(500, 'Error en play');
    llamadas.add('play uris=$uris context=$contextUri offset=${offsetUri ?? offsetPosition} pos=$positionMs');
  }

  @override
  Future<List<Artist>> topArtists({String timeRange = 'short_term', int limit = 20}) async {
    llamadas.add('topArtists');
    if (lanzarErrorEnArtistas || lanzarErrorGlobal) {
      throw ApiException(500, 'Error de red en API de Spotify');
    }
    return artistasTopMock;
  }

  @override
  Future<List<Track>> artistTopTracks(String id) async {
    llamadas.add('artistTopTracks $id');
    if (lanzarErrorGlobal) throw ApiException(500, 'Error de red');
    return pistasTopArtistaMock[id] ?? const [];
  }

  @override
  Future<List<Track>> topTracks({String timeRange = 'short_term', int limit = 20}) async {
    llamadas.add('topTracks');
    if (lanzarErrorGlobal) throw ApiException(500, 'Error de red');
    return pistasTopMock;
  }

  @override
  Future<List<Track>> recentlyPlayed({int limit = 20}) async {
    llamadas.add('recentlyPlayed');
    if (lanzarErrorGlobal) throw ApiException(500, 'Error de red');
    return recientesMock;
  }

  @override
  Future<ApiPage<Track>> savedTracks({int limit = 50, int offset = 0}) async {
    llamadas.add('savedTracks');
    return const ApiPage(items: [], hasMore: false, rawCount: 0);
  }
}

void main() {
  group('Aleatorio Inteligente - Lógica del Controlador', () {
    late _ApiFalsaInteligente api;
    late _ConfiguracionFalsa config;
    late PlayerController reproductor;

    setUp(() {
      api = _ApiFalsaInteligente();
      config = _ConfiguracionFalsa();
      reproductor = PlayerController(api, config);
    });

    tearDown(() {
      reproductor.dispose();
    });

    test('constante de proporción es 60% conocidas (0.60)', () {
      expect(PlayerController.kProporcionConocidasModoInteligente, 0.60);
    });

    test('comienza en modo apagado', () {
      expect(reproductor.modoAleatorio, ModoAleatorio.apagado);
      expect(reproductor.esAleatorioInteligente, isFalse);
    });

    test('ciclo de 3 estados: apagado -> estándar -> inteligente -> apagado', () async {
      await reproductor.ciclarModoAleatorio();
      expect(reproductor.modoAleatorio, ModoAleatorio.estandar);
      expect(reproductor.state.shuffle, isTrue);
      expect(reproductor.esAleatorioInteligente, isFalse);
      expect(api.llamadas.contains('setShuffle true'), isTrue);

      api.llamadas.clear();
      await reproductor.ciclarModoAleatorio();
      expect(reproductor.modoAleatorio, ModoAleatorio.inteligente);
      expect(reproductor.esAleatorioInteligente, isTrue);
      expect(api.llamadas.contains('setShuffle false'), isTrue);
      expect(api.llamadas.any((l) => l.startsWith('play uris=')), isTrue);

      api.llamadas.clear();
      await reproductor.ciclarModoAleatorio();
      expect(reproductor.modoAleatorio, ModoAleatorio.apagado);
      expect(reproductor.esAleatorioInteligente, isFalse);
      expect(api.llamadas.contains('setShuffle false'), isTrue);
    });

    test('reproducir un contexto o pista apaga el aleatorio inteligente', () async {
      await reproductor.ciclarModoAleatorio();
      await reproductor.ciclarModoAleatorio();
      expect(reproductor.modoAleatorio, ModoAleatorio.inteligente);

      await reproductor.playContext('spotify:playlist:123');
      expect(reproductor.esAleatorioInteligente, isFalse);

      await reproductor.ciclarModoAleatorio();
      await reproductor.ciclarModoAleatorio();
      expect(reproductor.modoAleatorio, ModoAleatorio.inteligente);

      await reproductor.playTrack('spotify:track:999');
      expect(reproductor.esAleatorioInteligente, isFalse);
    });

    test('constante de tope para canciones top es 10', () {
      expect(PlayerController.kMaxPistasTopEnAleatorio, 10);
    });

    test('excluye canciones recientes del historial de las conocidas y recomendadas', () async {
      api.recientesMock = const [
        Track(id: 'recplayed1', uri: 'spotify:track:recplayed1', name: 'Reciente', artists: 'Art', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
      ];
      api.pistasTopMock = const [
        Track(id: 'recplayed1', uri: 'spotify:track:recplayed1', name: 'Reciente', artists: 'Art', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
        Track(id: 'top_valida', uri: 'spotify:track:top_valida', name: 'Válida', artists: 'Art', album: 'Alb', artSmall: null, artMedium: null, durationMs: 200000, isLocal: false),
      ];

      api.llamadas.clear();
      await reproductor.activarAleatorioInteligente();

      final llamadaPlay = api.llamadas.firstWhere((l) => l.startsWith('play uris='));
      expect(llamadaPlay.contains('spotify:track:recplayed1'), isFalse);
      expect(llamadaPlay.contains('spotify:track:top_valida'), isTrue);
    });

    test('muestrea la biblioteca por offsets cuando no está completamente cargada', () async {
      api.llamadas.clear();
      await reproductor.activarAleatorioInteligente();

      expect(api.llamadas.any((l) => l.contains('savedTracks')), isTrue);
    });

    test('si ocurre un error al armar la cola, la interfaz desactiva el aleatorio inteligente', () async {
      api.lanzarErrorGlobal = true;
      await reproductor.ciclarModoAleatorio();
      await reproductor.ciclarModoAleatorio();

      expect(reproductor.esAleatorioInteligente, isFalse);
      expect(reproductor.modoAleatorio, ModoAleatorio.apagado);
    });

    test('conserva la posición actual en ms al activar aleatorio inteligente en reproducción', () async {
      reproductor.state = Playback(
        track: const Track(
          id: 'sonando',
          uri: 'spotify:track:sonando',
          name: 'Canción Actual',
          artists: 'Artista',
          album: 'Disco',
          artSmall: null,
          artMedium: null,
          durationMs: 200000,
          isLocal: false,
        ),
        isPlaying: true,
        progressMs: 45000,
        deviceId: 'dev',
        deviceName: 'NeoFy',
        volumePercent: 50,
        shuffle: false,
        repeat: 'off',
        contextUri: null,
      );
      reproductor.progressMs.value = 45000;

      api.llamadas.clear();
      await reproductor.activarAleatorioInteligente();

      final llamadaPlay = api.llamadas.firstWhere((l) => l.startsWith('play uris='));
      expect(llamadaPlay.contains('pos=45000'), isTrue);
      expect(llamadaPlay.contains('spotify:track:sonando'), isTrue);
    });

    test('calcularOffsetsEstratificados calcula 3 bandas estratificadas no solapadas sin desbordar ni fijar en 0', () {
      final casos = [3, 26, 50, 51, 75, 100, 5000];
      for (final total in casos) {
        final offsets = PlayerController.calcularOffsetsEstratificados(total, tamanoVentana: 25);
        final maxPermitido = (total - 25).clamp(0, total);

        for (final offset in offsets) {
          expect(offset >= 0, isTrue, reason: 'Offset no puede ser negativo para total=$total');
          expect(offset <= maxPermitido, isTrue, reason: 'Offset $offset supera el máximo $maxPermitido para total=$total');
        }

        expect(offsets.length, 3);
        if (total > 50) {
          expect(offsets[0] <= offsets[1], isTrue);
          expect(offsets[1] <= offsets[2], isTrue);
        }
      }

      var alcanzadoOffset75 = false;
      for (var i = 0; i < 200; i++) {
        final offsets = PlayerController.calcularOffsetsEstratificados(100, tamanoVentana: 25);
        if (offsets[2] == 75) {
          alcanzadoOffset75 = true;
          break;
        }
      }
      expect(alcanzadoOffset75, isTrue, reason: 'En total=100 la última canción (índice 99, offset 75) debe ser alcanzable');

      final muestra0 = PlayerController.calcularOffsetsEstratificados(1000, tamanoVentana: 25);
      final muestra1 = PlayerController.calcularOffsetsEstratificados(1000, tamanoVentana: 25);
      expect(muestra0[0] != 0 || muestra1[0] != 0 || muestra0[1] != muestra1[1], isTrue);
    });
  });

  group('Aleatorio Inteligente - UI NowPlayingBar', () {
    late _ApiFalsaInteligente api;
    late _ConfiguracionFalsa config;
    late PlayerController reproductor;

    setUp(() {
      api = _ApiFalsaInteligente();
      config = _ConfiguracionFalsa();
      reproductor = PlayerController(api, config);
    });

    testWidgets('botón de aleatorio cicla entre los 3 estados en español y sus tooltips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NowPlayingBar(
              player: reproductor,
              librespot: LibrespotManager(config),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Aleatorio: Apagado'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle), findsOneWidget);

      await tester.tap(find.byTooltip('Aleatorio: Apagado'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Aleatorio'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle), findsOneWidget);

      await tester.tap(find.byTooltip('Aleatorio'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Aleatorio inteligente'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

      await tester.tap(find.byTooltip('Aleatorio inteligente'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Aleatorio: Apagado'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle), findsOneWidget);

      reproductor.dispose();
      await tester.pump(const Duration(seconds: 15));
    });
  });
}
