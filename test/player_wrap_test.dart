import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/ultima_reproduccion.dart';

class _FakeConfig extends AppConfig {
  _FakeConfig() : super(initialVolume: 60);

  int guardados = 0;

  @override
  Future<void> save() async => guardados++;
}

class _FakeApi extends SpotifyApi {
  _FakeApi() : super(SpotifyAuth(AppConfig()));

  final List<String> llamadas = [];
  bool nextProhibido = false;
  bool traspasoProhibido = false;

  Playback? estadoRemoto;

  List<Device> dispositivos = const [];

  @override
  Future<List<Device>> devices() async {
    llamadas.add('devices');
    return dispositivos;
  }

  @override
  Future<void> transfer(String deviceId, {bool play = false}) async {
    llamadas.add('transfer $deviceId play=$play');
    if (traspasoProhibido) throw ApiException(404, 'Device not found');
  }

  @override
  Future<Playback?> playbackState() async {
    llamadas.add('playbackState');
    return estadoRemoto;
  }

  @override
  Future<void> pause() async => llamadas.add('pause');

  @override
  Future<void> setVolume(int percent, {String? deviceId}) async =>
      llamadas.add('volume $percent');

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
    String? offsetUri,
    int? positionMs,
  }) async {
    llamadas.add('play ${contextUri ?? uris} offset=${offsetUri ?? offsetPosition}'
        '${positionMs == null ? '' : ' pos=$positionMs'}');
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
      expect(player.lastError, isNull);
    });

    test('una canción suelta no tiene lista a la que volver', () async {
      player.state = _sonando(canSkipNext: false, contextUri: null);
      await player.next();

      expect(api.llamadas, ['next']);
    });
  });

  group('tiras de la portada', () {
    test('al pulsar una se manda la tira entera, no solo esa canción', () async {
      await player.playLista(
        const ['spotify:track:a', 'spotify:track:b', 'spotify:track:c'],
        desde: 1,
      );

      expect(api.llamadas,
          ['play [spotify:track:a, spotify:track:b, spotify:track:c] offset=1']);
    });

    test('al final de la tira, siguiente vuelve a la primera', () async {
      await player.playLista(const ['spotify:track:a', 'spotify:track:b']);
      api.llamadas.clear();

      player.state = _sonando(canSkipNext: false, contextUri: null);
      await player.next();

      expect(api.llamadas, ['play [spotify:track:a, spotify:track:b] offset=0']);
    });

    test('poner una cancion suelta despues olvida la tira', () async {
      await player.playLista(const ['spotify:track:a', 'spotify:track:b']);
      await player.playTrack('spotify:track:z');
      api.llamadas.clear();

      player.state = _sonando(canSkipNext: false, contextUri: null);
      await player.next();

      expect(api.llamadas, ['next']);
    });

    test('poner una playlist despues tambien la olvida', () async {
      await player.playLista(const ['spotify:track:a']);
      await player.playContext('spotify:playlist:abc');
      api.llamadas.clear();

      player.state = _sonando(canSkipNext: false, contextUri: null);
      await player.next();

      expect(api.llamadas, ['play spotify:playlist:abc offset=0']);
    });
  });

  test('el contexto sobrevive a que la reproducción se acabe', () async {
    await player.playContext('spotify:user:usuario:collection');
    api.llamadas.clear();

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
      expect(player.state.track, isNotNull);
    });

    test('si ya estaba parado no se toca nada', () async {
      api.estadoRemoto = _sonando(isPlaying: false);
      await player.ensurePausedAtStartup();

      expect(api.llamadas, ['playbackState']);
    });

    test('lo que ha puesto el usuario no se pausa, aunque librespot tarde',
        () async {
      player.ourDeviceId = 'dev';
      await player.playContext('spotify:playlist:abc');
      api.llamadas.clear();

      api.estadoRemoto = _sonando();
      await player.ensurePausedAtStartup();

      expect(api.llamadas, isEmpty);
    });
  });

  group('reinicio del audio', () {
    Device neofy(String id) =>
        Device(id: id, name: kDeviceName, isActive: false, volumePercent: 50);

    test('no se pilla el dispositivo del librespot que acabamos de matar',
        () async {
      api.dispositivos = [neofy('viejo')];
      expect(
        await player.resolveDevice(transfer: false, distintoDe: 'viejo'),
        isFalse,
      );

      api.dispositivos = [neofy('viejo'), neofy('nuevo')];
      expect(
        await player.resolveDevice(transfer: false, distintoDe: 'viejo'),
        isTrue,
      );
      expect(player.ourDeviceId, 'nuevo');
    });

    test('la canción se retoma donde iba, no donde crea Spotify', () async {
      player.state = _sonando();
      player.progressMs.value = 42000;
      final antes = player.instantanea();

      player.ourDeviceId = 'nuevo';
      await player.retomar(antes);

      expect(api.llamadas, ['transfer nuevo play=true', 'seek 42000']);
    });

    test('lo que estaba en pausa no se pone a sonar solo', () async {
      player.state = _sonando(isPlaying: false);
      player.progressMs.value = 42000;
      final antes = player.instantanea();

      player.ourDeviceId = 'nuevo';
      await player.retomar(antes);

      expect(api.llamadas, ['transfer nuevo play=false']);
    });

    test('si el traspaso no cuaja, se rearranca la lista por esa canción',
        () async {
      api.traspasoProhibido = true;
      player.state = _sonando();
      player.progressMs.value = 42000;
      final antes = player.instantanea();

      player.ourDeviceId = 'nuevo';
      await player.retomar(antes);

      expect(api.llamadas, [
        'transfer nuevo play=true',
        'play spotify:playlist:abc offset=spotify:track:1 pos=42000',
      ]);
    });

    test('una canción suelta se rearranca sola, sin contexto', () async {
      api.traspasoProhibido = true;
      player.state = _sonando(contextUri: null);
      player.progressMs.value = 1000;
      final antes = player.instantanea();

      player.ourDeviceId = 'nuevo';
      await player.retomar(antes);

      expect(api.llamadas, [
        'transfer nuevo play=true',
        'play [spotify:track:1] offset=null pos=1000',
      ]);
    });
  });

  group('lo último que sonó se recuerda entre sesiones', () {
    UltimaReproduccion guardada({
      String? contextUri = 'spotify:playlist:abc',
      List<String>? uris,
    }) =>
        UltimaReproduccion(
          track: _sonando().track!,
          posicionMs: 56000,
          contextUri: contextUri,
          uris: uris,
        );

    void abrirCon(UltimaReproduccion ultima) {
      player.restaurar(ultima);
      player.ourDeviceId = 'dev';
    }

    test('al abrir, la barra enseña la canción parada donde se dejó', () {
      abrirCon(guardada());

      expect(player.state.track?.name, 'Última');
      expect(player.state.isPlaying, isFalse);
      expect(player.progressMs.value, 56000);
      expect(player.contextUri, 'spotify:playlist:abc');
      expect(api.llamadas, isEmpty);
    });

    test('el play la retoma donde iba, sin tener que buscarla', () async {
      abrirCon(guardada());
      await player.togglePlay();

      expect(api.llamadas,
          ['play spotify:playlist:abc offset=spotify:track:1 pos=56000']);
      expect(player.state.isPlaying, isTrue);
      expect(player.hayAlgoPorRetomar, isFalse);
    });

    test('una canción suelta se retoma sin contexto', () async {
      abrirCon(guardada(contextUri: null));
      await player.togglePlay();

      expect(api.llamadas, ['play [spotify:track:1] offset=null pos=56000']);
    });

    test('una tira sin contexto se retoma con el resto de la cola', () async {
      abrirCon(guardada(
        contextUri: null,
        uris: const ['spotify:track:1', 'spotify:track:2'],
      ));
      await player.togglePlay();

      expect(api.llamadas,
          ['play [spotify:track:1, spotify:track:2] offset=null pos=56000']);
    });

    test('siguiente no salta al vacío: arranca lo guardado', () async {
      abrirCon(guardada());
      await player.next();

      expect(api.llamadas,
          ['play spotify:playlist:abc offset=spotify:track:1 pos=56000']);
    });

    test('mover la barra antes de darle al play cambia por dónde empieza',
        () async {
      abrirCon(guardada());
      await player.seek(90000);

      expect(api.llamadas, isEmpty);
      expect(player.progressMs.value, 90000);

      await player.togglePlay();
      expect(api.llamadas,
          ['play spotify:playlist:abc offset=spotify:track:1 pos=90000']);
    });

    test('poner otra cosa olvida lo guardado', () async {
      abrirCon(guardada());
      await player.playContext('spotify:album:otro');
      api.llamadas.clear();

      expect(player.hayAlgoPorRetomar, isFalse);
      await player.next();
      expect(api.llamadas, ['next', 'play null offset=null']);
    });

    test('el 204 de /me/player no borra lo restaurado de la barra', () async {
      abrirCon(guardada());
      api.estadoRemoto = null;

      player.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(api.llamadas, contains('playbackState'));
      expect(player.state.track?.name, 'Última');
      expect(player.progressMs.value, 56000);
    });

    test('si Spotify sí sabe qué suena, manda Spotify', () async {
      abrirCon(guardada());
      api.estadoRemoto = _sonando();

      player.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(player.hayAlgoPorRetomar, isFalse);
      expect(player.state.progressMs, 1000);
    });

    test('lo que se apunta para la próxima sesión es lo que suena ahora', () {
      player.state = _sonando();
      player.progressMs.value = 42000;

      final apunte = player.paraRecordar();
      expect(apunte, isNotNull);
      expect(apunte!.track.uri, 'spotify:track:1');
      expect(apunte.posicionMs, 42000);
      expect(apunte.contextUri, 'spotify:playlist:abc');
    });

    test('sin nada sonando no se apunta nada', () {
      expect(player.paraRecordar(), isNull);
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
      expect(player.state.volumePercent, isNull);
      expect(player.volumeShown, 73);
    });

    test('con reproducción manda lo que diga Spotify', () async {
      player.state = _sonando();
      expect(player.volumeShown, 50);
    });

    test('silenciar guarda el volumen y el slider no se va a cero', () async {
      player.state = _sonando();
      await player.alternarMute();

      expect(player.muteado, isTrue);
      expect(player.volumeShown, 50);
      expect(api.llamadas, contains('volume 0'));
    });

    test('volver a pulsar restaura el volumen de antes', () async {
      player.state = _sonando();
      await player.alternarMute();
      await player.alternarMute();

      expect(player.muteado, isFalse);
      expect(player.volumeShown, 50);
      expect(api.llamadas, contains('volume 50'));
    });

    test('mover el volumen mientras está silenciado lo reactiva', () async {
      player.state = _sonando();
      await player.alternarMute();
      await player.setVolume(80);

      expect(player.muteado, isFalse);
      expect(player.volumeShown, 80);
    });
  });
}
