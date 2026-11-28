import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/metadata_sidecar.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:path/path.dart' as p;

class _ApiDePrueba extends SpotifyApi {
  _ApiDePrueba() : super(SpotifyAuth(AppConfig()));

  Future<Playback?> Function()? alConsultarPlayback;

  @override
  Future<Playback?> playbackState() async {
    final cb = alConsultarPlayback;
    if (cb != null) return cb();
    return null;
  }
}

Track _pista(int i) => Track(
      id: 'id_$i',
      uri: 'spotify:track:id_$i',
      name: 'Canción número $i con título de prueba para superar umbral',
      artists: 'Artista $i',
      album: 'Álbum $i',
      artSmall: 'https://i.scdn.co/image/small_$i',
      artMedium: 'https://i.scdn.co/image/medium_$i',
      durationMs: 180000 + i,
      isLocal: false,
    );

Playback _reproduccion({
  int progressMs = 1000,
  bool isPlaying = true,
  String uri = 'spotify:track:uno',
}) =>
    Playback(
      track: Track(
        id: 'uno',
        uri: uri,
        name: 'Pista Uno',
        artists: 'Artista',
        album: 'Disco',
        artSmall: null,
        artMedium: null,
        durationMs: 200000,
        isLocal: false,
      ),
      isPlaying: isPlaying,
      progressMs: progressMs,
      deviceId: 'dev',
      deviceName: 'NeoFy',
      volumePercent: 50,
      shuffle: false,
      repeat: 'off',
      contextUri: 'spotify:playlist:test',
      canSkipNext: true,
      canSkipPrevious: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataSidecar bajo demanda', () {
    test('por defecto no arranca ni se marca disponible', () async {
      final sidecar = MetadataSidecar();
      addTearDown(sidecar.dispose);

      expect(sidecar.ready, isFalse);
      expect(sidecar.puedeUsarse, isFalse);
      expect(await sidecar.asegurarListo(), isFalse);
      await sidecar.detenerSiInactivo(inmediato: true);
      expect(sidecar.pid, isNull);
    });

    test('respeta puedeArrancar antes de lanzar proceso', () async {
      var habilitado = false;
      final sidecar = MetadataSidecar(puedeArrancar: () => habilitado);
      addTearDown(sidecar.dispose);

      expect(sidecar.puedeUsarse, isFalse);
      expect(await sidecar.asegurarListo(), isFalse);

      habilitado = true;
      expect(sidecar.puedeUsarse, isTrue);
    });
  });

  group('PlayerController sondeo y visibilidad', () {
    test('omite notifyListeners cuando el poll solo avanza el progreso',
        () async {
      final api = _ApiDePrueba();
      final controller = PlayerController(api, AppConfig());
      addTearDown(controller.dispose);

      var notificaciones = 0;
      controller.addListener(() => notificaciones++);

      var llamada = 0;
      var pollActual = Completer<void>();
      api.alConsultarPlayback = () async {
        llamada++;
        try {
          if (llamada == 1) {
            return _reproduccion(progressMs: 1000, isPlaying: true);
          }
          if (llamada == 2) {
            return _reproduccion(progressMs: 4200, isPlaying: true);
          }
          return _reproduccion(progressMs: 4500, isPlaying: false);
        } finally {
          Future<void>.microtask(() {
            if (!pollActual.isCompleted) pollActual.complete();
          });
        }
      };

      controller.start();
      await pollActual.future;
      expect(notificaciones, 1);

      pollActual = Completer<void>();
      controller.setWindowVisible(false);
      controller.setWindowVisible(true);
      await pollActual.future;
      expect(notificaciones, 1);
      expect(controller.progressMs.value, closeTo(4200, 100));

      pollActual = Completer<void>();
      controller.setWindowVisible(false);
      controller.setWindowVisible(true);
      await pollActual.future;
      expect(notificaciones, 2);
      expect(controller.state.isPlaying, isFalse);
    });
  });

  group('LikedStore carga ligera y descarga de RAM', () {
    test('cargarUrisDesdeDisco carga URIs sin inflar la lista de pistas',
        () async {
      final dir = Directory.systemTemp.createTempSync('neofy_likes_uris_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final pistas = [for (var i = 0; i < 400; i++) _pista(i)];
      final json = jsonEncode({
        'total': pistas.length,
        'pistas': [for (final t in pistas) t.aLocal()],
      });
      expect(json.length, greaterThan(64 * 1024));
      await File(p.join(dir.path, 'biblioteca.json')).writeAsString(json);

      final auth = SpotifyAuth(AppConfig());
      final store = LikedStore(
        api: SpotifyApi(auth),
        auth: auth,
        directorio: dir,
      );
      addTearDown(store.dispose);

      await store.cargarUrisDesdeDisco();

      expect(store.tieneUrisDeBiblioteca, isTrue);
      expect(store.bibliotecaCompleta, isFalse);
      expect(store.biblioteca, isEmpty);
      expect(store.totalBiblioteca, 400);
      expect(store.isSaved('spotify:track:id_0'), isTrue);
      expect(store.isSaved('spotify:track:id_399'), isTrue);
      expect(store.urisGuardadas.length, 400);
    });

    test('liberarMemoriaDeBiblioteca vacía pistas conservando los likes',
        () async {
      final dir = Directory.systemTemp.createTempSync('neofy_likes_free_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final pistas = [for (var i = 0; i < 350; i++) _pista(i)];
      await File(p.join(dir.path, 'biblioteca.json')).writeAsString(jsonEncode({
        'total': pistas.length,
        'pistas': [for (final t in pistas) t.aLocal()],
      }));

      final auth = SpotifyAuth(AppConfig());
      final store = LikedStore(
        api: SpotifyApi(auth),
        auth: auth,
        directorio: dir,
      );
      addTearDown(store.dispose);

      await store.cargarDesdeDisco();
      expect(store.bibliotecaCompleta, isTrue);
      expect(store.biblioteca, hasLength(350));

      expect(store.liberarMemoriaDeBiblioteca(), isTrue);

      expect(store.biblioteca, isEmpty);
      expect(store.bibliotecaCompleta, isFalse);
      expect(store.tieneUrisDeBiblioteca, isTrue);
      expect(store.isSaved('spotify:track:id_10'), isTrue);

      await store.cargarBiblioteca();
      expect(store.biblioteca, hasLength(350));
      expect(store.bibliotecaCompleta, isTrue);
    });
  });
}
