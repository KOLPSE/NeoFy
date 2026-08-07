import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';

/// `save()` escribiría en el `%APPDATA%` de verdad del usuario. Aquí solo
/// interesa que el valor quede guardado en memoria.
class _FakeConfig extends AppConfig {
  _FakeConfig() : super(initialVolume: 60);

  int guardados = 0;

  @override
  Future<void> save() async => guardados++;
}

/// API de mentira: apunta lo que se le pide y no toca la red.
///
/// Hereda de `SpotifyApi` y sobrescribe solo los comandos del reproductor, así
/// que nunca llega a `_request` y el token nunca hace falta.
class _FakeApi extends SpotifyApi {
  _FakeApi() : super(SpotifyAuth(AppConfig()));

  final List<String> llamadas = [];
  bool nextProhibido = false;

  /// Lo que contesta `GET /me/player`.
  Playback? estadoRemoto;

  @override
  Future<Playback?> playbackState() async {
    llamadas.add('playbackState');
    return estadoRemoto;
  }

  @override
  Future<void> pause() async => llamadas.add('pause');

  @override
  Future<void> setVolume(int percent) async => llamadas.add('volume $percent');

  @override
  Future<void> next() async {
    llamadas.add('next');
    if (nextProhibido) throw ApiException(403, 'Player command failed: Restriction violated');
  }

  @override
  Future<void> previous() async => llamadas.add('previous');

  @override
  Future<void> seek(int positionMs) async => llamadas.add('seek $positionMs');

  @override
  Future<void> play({
    String? deviceId,
    String? contextUri,
    List<String>? uris,
    int? offsetPosition,
    int? positionMs,
  }) async {
    llamadas.add('play ${contextUri ?? uris} offset=$offsetPosition');
  }
}

Playback _sonando({
  bool canSkipNext = true,
  bool canSkipPrevious = true,
  bool isPlaying = true,
  String? contextUri = 'spotify:playlist:abc',
}) =>
    Playback(
      track: const Track(
        id: '1',
        uri: 'spotify:track:1',
        name: 'Última',
        artists: 'Alguien',
        album: 'Disco',
        artSmall: null,
        artMedium: null,
        durationMs: 200000,
        isLocal: false,
      ),
      isPlaying: isPlaying,
      progressMs: 1000,
      deviceId: 'dev',
      deviceName: 'NeoFy',
      volumePercent: 50,
      shuffle: false,
      repeat: 'off',
      contextUri: contextUri,
      canSkipNext: canSkipNext,
      canSkipPrevious: canSkipPrevious,
    );

void main() {
  late _FakeApi api;
  late _FakeConfig config;
  late PlayerController player;

  setUp(() {
    api = _FakeApi();
    config = _FakeConfig();
    player = PlayerController(api, config);
    addTearDown(player.dispose);
  });

  group('Playback.fromJson y disallows', () {
    test('la última canción de la lista sale sin siguiente', () {
      final pb = Playback.fromJson({
        'is_playing': true,
        'item': {'uri': 'spotify:track:1', 'name': 'X', 'duration_ms': 1000},
        'context': {'uri': 'spotify:playlist:abc'},
        'actions': {
          'disallows': {'skipping_next': true, 'toggling_repeat_context': true},
        },
      });

      expect(pb.canSkipNext, isFalse);
      // `disallows` solo lista lo prohibido: lo que no aparece está permitido.
      expect(pb.canSkipPrevious, isTrue);
    });

    test('sin bloque actions se asume que se puede saltar', () {
      final pb = Playback.fromJson({'is_playing': true});
      expect(pb.canSkipNext, isTrue);
      expect(pb.canSkipPrevious, isTrue);
    });

    test('la clave de anterior es skipping_prev, abreviada', () {
      final pb = Playback.fromJson({
        'actions': {
          'disallows': {'skipping_prev': true},
        },
      });
      expect(pb.canSkipPrevious, isFalse);
    });
  });

  group('next() al final de la lista', () {
    test('da la vuelta a la primera en vez de parar la música', () async {
      player.state = _sonando(canSkipNext: false);
      await player.next();

      // Ni se le pide el salto a Spotify: pedirlo es lo que dejaba el
      // dispositivo mudo.
      expect(api.llamadas, ['play spotify:playlist:abc offset=0']);
    });

    test('en mitad de la lista sigue siendo un salto normal', () async {
      player.state = _sonando();
      await player.next();

      expect(api.llamadas, ['next']);
    });

    test('si Spotify contesta 403, también da la vuelta', () async {
      api.nextProhibido = true;
      player.state = _sonando();
      await player.next();

      expect(api.llamadas, ['next', 'play spotify:playlist:abc offset=0']);
      // El 403 queda resuelto: no hay por qué enseñarle un error al usuario.
      expect(player.lastError, isNull);
    });

    test('una canción suelta no tiene lista a la que volver', () async {
      player.state = _sonando(canSkipNext: false, contextUri: null);
      await player.next();

      expect(api.llamadas, ['next']);
    });
  });

  test('el contexto sobrevive a que la reproducción se acabe', () async {
    await player.playContext('spotify:user:usuario:collection');
    api.llamadas.clear();

    // Al terminarse la lista, `GET /me/player` contesta 204 y el estado se
    // queda vacío. Aun así hay que saber qué había que reanudar.
    player.state = Playback.empty;
    await player.togglePlay();

    expect(api.llamadas, ['play spotify:user:usuario:collection offset=0']);
  });

  test('previous en la primera canción reinicia en vez de dar error', () async {
    player.state = _sonando(canSkipPrevious: false);
    await player.previous();

    expect(api.llamadas, ['seek 0']);
  });

  group('saltar estando en pausa', () {
    test('siguiente reanuda: nadie salta de canción para no oírla', () async {
      player.state = _sonando(isPlaying: false);
      await player.next();

      // El salto conserva el estado de pausa, así que hay que arrancar aparte.
      expect(api.llamadas, ['next', 'play null offset=null']);
      expect(player.state.isPlaying, isTrue);
    });

    test('anterior también', () async {
      player.state = _sonando(isPlaying: false);
      await player.previous();

      expect(api.llamadas, ['previous', 'play null offset=null']);
    });

    test('sonando ya, no se manda un play de más', () async {
      player.state = _sonando();
      await player.next();

      expect(api.llamadas, ['next']);
    });
  });

  group('arranque', () {
    test('lo que venía sonando de la sesión anterior se pausa', () async {
      api.estadoRemoto = _sonando();
      await player.ensurePausedAtStartup();

      expect(api.llamadas, ['playbackState', 'pause']);
      expect(player.state.isPlaying, isFalse);
      // El estado se conserva: la barra enseña qué había, solo que parado.
      expect(player.state.track, isNotNull);
    });

    test('si ya estaba parado no se toca nada', () async {
      api.estadoRemoto = _sonando(isPlaying: false);
      await player.ensurePausedAtStartup();

      expect(api.llamadas, ['playbackState']);
    });
  });

  group('volumen', () {
    test('se recuerda para la próxima sesión', () async {
      await player.setVolume(37);

      expect(api.llamadas, ['volume 37']);
      expect(config.initialVolume, 37);
      expect(config.guardados, 1);
    });

    test('sin reproducción activa se enseña el último, no un 50 inventado',
        () async {
      config.initialVolume = 73;
      // `GET /me/player` no informa de volumen cuando no hay nada sonando.
      expect(player.state.volumePercent, isNull);
      expect(player.volumeShown, 73);
    });

    test('con reproducción manda lo que diga Spotify', () async {
      player.state = _sonando();
      expect(player.volumeShown, 50);
    });
  });
}
