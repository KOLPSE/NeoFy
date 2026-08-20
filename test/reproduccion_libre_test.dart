import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/puente_yt.dart';
import 'package:neofy/core/reproduccion_libre.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/yt_auth.dart';
import 'package:neofy/core/yt_models.dart';
import 'package:neofy/core/yt_music_api.dart';
import 'package:neofy/core/yt_player.dart';

class _FakeYtAuth extends YtAuth {
  @override
  bool get isLoggedIn => true;
}

class _FakeYtMusicApi extends YtMusicApi {
  _FakeYtMusicApi({YtAuth? auth}) : super(auth ?? _FakeYtAuth());
}

class _FakePuenteYt extends PuenteYt {
  _FakePuenteYt({YtMusicApi? api, this.sinResultadosPara = const {}}) : super(api ?? _FakeYtMusicApi());

  final Set<String> sinResultadosPara;

  @override
  Future<YtTrack?> equivalenteDe(Track t) async {
    if (sinResultadosPara.contains(t.id) || sinResultadosPara.contains(t.name)) {
      return null;
    }
    return YtTrack(
      videoId: 'yt_${t.id}',
      titulo: t.name,
      artista: t.artists,
      duracion: Duration(milliseconds: t.durationMs),
    );
  }
}

class _FakeYtPlayer extends YtPlayer {
  _FakeYtPlayer() : super(volumenInicial: 70);

  bool _sonandoState = false;
  Duration _posicionState = Duration.zero;
  final Duration _duracionState = const Duration(minutes: 3);

  final _posicionCtrl = StreamController<Duration>.broadcast();
  final _sonandoCtrl = StreamController<bool>.broadcast();

  @override
  Stream<Duration> get cambiosDePosicion => _posicionCtrl.stream;

  @override
  Stream<bool> get cambiosDeSonando => _sonandoCtrl.stream;

  void emitirPosicion(Duration d) {
    _posicionState = d;
    _posicionCtrl.add(d);
  }

  @override
  bool get disponible => true;

  @override
  bool get sonando => _sonandoState;

  @override
  Duration get posicion => _posicionState;

  @override
  Duration get duracion => _duracionState;

  @override
  Future<void> reproducirPista(YtTrack t) async {
    _sonandoState = true;
    _posicionState = Duration.zero;
    cola = [t];
    indice = 0;
    _sonandoCtrl.add(true);
    notifyListeners();
  }

  @override
  Future<void> alternar() async {
    _sonandoState = !_sonandoState;
    _sonandoCtrl.add(_sonandoState);
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _sonandoState = false;
    _sonandoCtrl.add(false);
    notifyListeners();
  }

  @override
  Future<void> seek(Duration d) async {
    _posicionState = d;
    _posicionCtrl.add(d);
    notifyListeners();
  }

  @override
  Future<void> setVolumen(int v) async {
    volumen = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _posicionCtrl.close();
    _sonandoCtrl.close();
    super.dispose();
  }
}

class _FakeSpotifyApi extends SpotifyApi {
  _FakeSpotifyApi() : super(SpotifyAuth(AppConfig()));

  final List<String> llamadas = [];

  @override
  Future<List<Track>> tracks(List<String> ids) async {
    llamadas.add('tracks $ids');
    return ids.map((id) => Track(
      id: id,
      uri: 'spotify:track:$id',
      name: 'Track $id',
      artists: 'Artista $id',
      album: 'Álbum $id',
      artSmall: null,
      artMedium: null,
      durationMs: 200000,
      isLocal: false,
    )).toList();
  }

  @override
  Future<ApiPage<Track>> playlistItems(String id, {int limit = 50, int offset = 0}) async {
    llamadas.add('playlistItems $id');
    return ApiPage(
      items: [
        Track(id: 'pl_1', uri: 'spotify:track:pl_1', name: 'PL 1', artists: 'Art PL', album: 'Alb', artSmall: null, artMedium: null, durationMs: 180000, isLocal: false),
      ],
      hasMore: false,
      rawCount: 1,
    );
  }

  @override
  Future<ApiPage<Track>> savedTracks({int limit = 50, int offset = 0}) async {
    llamadas.add('savedTracks');
    return ApiPage(
      items: [
        Track(id: 'saved_1', uri: 'spotify:track:saved_1', name: 'Saved 1', artists: 'Art Saved', album: 'Alb', artSmall: null, artMedium: null, durationMs: 190000, isLocal: false),
      ],
      hasMore: false,
      rawCount: 1,
    );
  }

  @override
  Future<List<Track>> artistTopTracks(String id, {int discosDeRespaldo = 6}) async {
    llamadas.add('artistTopTracks $id');
    return [
      Track(id: 'art_1', uri: 'spotify:track:art_1', name: 'Art 1', artists: 'Artiste', album: 'Alb', artSmall: null, artMedium: null, durationMs: 210000, isLocal: false),
    ];
  }

  @override
  Future<List<Track>> albumTracks(String id) async {
    llamadas.add('albumTracks $id');
    return [
      Track(id: 'alb_1', uri: 'spotify:track:alb_1', name: 'Alb 1', artists: 'Band', album: 'Alb', artSmall: null, artMedium: null, durationMs: 220000, isLocal: false),
    ];
  }
}

Track _track(String id, {String name = 'Song', String artist = 'Artist', int durationMs = 200000}) {
  return Track(
    id: id,
    uri: 'spotify:track:$id',
    name: '$name $id',
    artists: artist,
    album: 'Album',
    artSmall: null,
    artMedium: null,
    durationMs: durationMs,
    isLocal: false,
  );
}

void main() {
  late _FakeSpotifyApi api;
  late _FakePuenteYt puente;
  late _FakeYtPlayer ytPlayer;
  late PlayerController controller;
  late ReproduccionLibre libre;

  setUp(() {
    YtPlayer.libmpvDisponible = false;
    api = _FakeSpotifyApi();
    puente = _FakePuenteYt(sinResultadosPara: {'t_no_existe'});
    ytPlayer = _FakeYtPlayer();
    controller = PlayerController(api, AppConfig());
    controller.currentUserId = 'user123';
    libre = ReproduccionLibre(
      puente: puente,
      ytPlayer: ytPlayer,
      api: api,
      controller: controller,
    );
    controller.libre = libre;
    addTearDown(() {
      libre.dispose();
      controller.dispose();
      YtPlayer.libmpvDisponible = true;
    });
  });

  group('ReproduccionLibre - Cola y reproducción', () {
    test('ponerLista reproduce la primera pista y sintetiza el Playback', () async {
      final pistas = [_track('t1'), _track('t2')];
      await libre.ponerLista(pistas, desde: 0);

      expect(controller.state.track?.id, 't1');
      expect(controller.state.isPlaying, isTrue);
      expect(controller.state.canSkipNext, isTrue);
      expect(controller.state.canSkipPrevious, isFalse);
    });

    test('siguiente avanza la cola y actualiza el estado', () async {
      final pistas = [_track('t1'), _track('t2')];
      await libre.ponerLista(pistas, desde: 0);
      await libre.siguiente();

      expect(controller.state.track?.id, 't2');
      expect(controller.state.canSkipNext, isFalse);
      expect(controller.state.canSkipPrevious, isTrue);
    });

    test('una canción no encontrada en YouTube se salta y reporta lastError', () async {
      final pistas = [_track('t1'), _track('t_no_existe'), _track('t3')];
      await libre.ponerLista(pistas, desde: 0);
      await libre.siguiente();

      expect(controller.lastError, contains('No se encontró'));
      expect(controller.state.track?.id, 't3');
    });
  });

  group('ReproduccionLibre - Reparto de URIs de contexto', () {
    test('playContext con playlist', () async {
      await libre.playContext('spotify:playlist:pl123');

      expect(api.llamadas, contains('playlistItems pl123'));
      expect(controller.state.track?.id, 'pl_1');
      expect(controller.contextUri, 'spotify:playlist:pl123');
    });

    test('playContext con Canciones que te gustan', () async {
      final likedUri = SpotifyApi.likedContextUri('user123');
      await libre.playContext(likedUri);

      expect(api.llamadas, contains('savedTracks'));
      expect(controller.state.track?.id, 'saved_1');
    });

    test('playContext con artista', () async {
      await libre.playContext('spotify:artist:art123');

      expect(api.llamadas, contains('artistTopTracks art123'));
      expect(controller.state.track?.id, 'art_1');
    });

    test('playContext con álbum', () async {
      await libre.playContext('spotify:album:alb123');

      expect(api.llamadas, contains('albumTracks alb123'));
      expect(controller.state.track?.id, 'alb_1');
    });

    test('playContext con contexto no soportado reporta error', () async {
      await libre.playContext('spotify:unknown:xxx');

      expect(controller.lastError, contains('Contexto de reproducción no soportado'));
    });
  });

  group('Tarea 3 - Arreglos de la Vía Libre', () {
    test('al dispararse alAcabarLaCola se avanza a la siguiente canción de Spotify', () async {
      final pistas = [_track('t1'), _track('t2')];
      await libre.ponerLista(pistas, desde: 0);

      expect(controller.state.track?.id, 't1');
      expect(ytPlayer.alAcabarLaCola, isNotNull);

      await ytPlayer.alAcabarLaCola!();

      expect(controller.state.track?.id, 't2');
    });

    test('un tic de posición no provoca notifyListeners en PlayerController', () async {
      final pistas = [_track('t1')];
      await libre.ponerLista(pistas, desde: 0);

      var notificaciones = 0;
      controller.addListener(() {
        notificaciones++;
      });

      ytPlayer.emitirPosicion(const Duration(seconds: 15));
      await pumpEventQueue();

      expect(controller.progressMs.value, 15000);
      expect(notificaciones, 0);
    });

    test('con alAcabarLaCola == null YtPlayer se comporta como antes al acabar la cola', () async {
      final playerSinHook = YtPlayer(volumenInicial: 50);
      addTearDown(playerSinHook.dispose);

      expect(playerSinHook.alAcabarLaCola, isNull);
      await playerSinHook.siguiente(automatico: true);
      expect(playerSinHook.actual, isNull);
    });
  });
}
