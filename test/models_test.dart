import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/ui/now_playing_bar.dart' show formatMs;

void main() {
  group('pickImage', () {
    final images = [
      {'url': 'big', 'width': 640, 'height': 640},
      {'url': 'medium', 'width': 300, 'height': 300},
      {'url': 'small', 'width': 64, 'height': 64},
    ];

    test('elige la más pequeña que llegue al tamaño pedido', () {
      expect(pickImage(images, 64), 'small');
      expect(pickImage(images, 300), 'medium');
      expect(pickImage(images, 640), 'big');
    });

    test('para tamaños intermedios sube al siguiente escalón', () {
      expect(pickImage(images, 65), 'medium');
      expect(pickImage(images, 301), 'big');
    });

    test('si ninguna llega al tamaño pedido, cae en la primera', () {
      expect(pickImage(images, 2000), 'big');
    });

    test('tolera listas vacías o nulas', () {
      expect(pickImage(null, 64), isNull);
      expect(pickImage([], 64), isNull);
    });
  });

  group('Track.fromJson', () {
    test('junta los artistas y coge los dos tamaños de carátula', () {
      final t = Track.fromJson({
        'id': '1',
        'uri': 'spotify:track:1',
        'name': 'Canción',
        'duration_ms': 185000,
        'artists': [
          {'name': 'Uno'},
          {'name': 'Dos'},
        ],
        'album': {
          'name': 'Álbum',
          'images': [
            {'url': 'big', 'width': 640},
            {'url': 'small', 'width': 64},
          ],
        },
      });

      expect(t, isNotNull);
      expect(t!.artists, 'Uno, Dos');
      expect(t.album, 'Álbum');
      expect(t.artSmall, 'small');
      expect(t.durationMs, 185000);
    });

    test('sobrevive a una respuesta incompleta', () {
      final t = Track.fromJson({'uri': 'spotify:track:x'});
      expect(t, isNotNull);
      expect(t!.name, 'Desconocido');
      expect(t.artists, '');
      expect(t.artSmall, isNull);
    });

    test('devuelve null si no hay objeto', () {
      expect(Track.fromJson(null), isNull);
    });
  });

  group('Playlist.fromJson', () {
    test('lee el recuento de la clave items', () {
      final pl = Playlist.fromJson({
        'id': 'abc',
        'uri': 'spotify:playlist:abc',
        'name': 'Synthwave',
        'owner': {'display_name': 'Kurate Music', 'id': 'kurate'},
        'items': {'total': 209},
        'images': [
          {'url': 'https://cdn/x.webp', 'width': null, 'height': null},
        ],
      });

      expect(pl.trackCount, 209);
      expect(pl.name, 'Synthwave');
      expect(pl.owner, 'Kurate Music');
      expect(pl.ownerId, 'kurate');
      expect(pl.art, 'https://cdn/x.webp');
    });

    test('acepta la clave tracks antigua', () {
      final pl = Playlist.fromJson({
        'name': 'Vieja',
        'tracks': {'total': 12},
      });
      expect(pl.trackCount, 12);
    });

    test('sin recuento se queda en 0 en vez de reventar', () {
      expect(Playlist.fromJson({'name': 'X'}).trackCount, 0);
    });
  });

  group('Artist.fromJson', () {
    test('coge la foto de 300, no la de 640', () {
      final a = Artist.fromJson({
        'id': 'a1',
        'uri': 'spotify:artist:a1',
        'name': 'Alguien',
        'images': [
          {'url': 'big', 'width': 640},
          {'url': 'medium', 'width': 300},
          {'url': 'small', 'width': 160},
        ],
      });

      expect(a, isNotNull);
      expect(a!.name, 'Alguien');
      expect(a.uri, 'spotify:artist:a1');
      expect(a.art, 'medium');
    });

    test('sin fotos no revienta', () {
      expect(Artist.fromJson({'name': 'X'})?.art, isNull);
      expect(Artist.fromJson(null), isNull);
    });
  });

  group('Playback.fromJson', () {
    test('lee el dispositivo y el estado', () {
      final pb = Playback.fromJson({
        'is_playing': true,
        'progress_ms': 42000,
        'shuffle_state': true,
        'repeat_state': 'context',
        'device': {'id': 'dev1', 'name': 'NeoFy', 'volume_percent': 70},
        'item': {'uri': 'spotify:track:1', 'name': 'X', 'duration_ms': 1000},
      });

      expect(pb.isPlaying, isTrue);
      expect(pb.progressMs, 42000);
      expect(pb.deviceId, 'dev1');
      expect(pb.volumePercent, 70);
      expect(pb.shuffle, isTrue);
      expect(pb.repeat, 'context');
    });
  });

  group('Playback.copyWith', () {
    const base = Playback(
      track: null,
      isPlaying: true,
      progressMs: 1000,
      deviceId: 'dev',
      deviceName: 'NeoFy',
      volumePercent: 40,
      shuffle: true,
      repeat: 'context',
      contextUri: 'spotify:playlist:1',
    );

    test('cambia solo lo indicado y conserva el resto', () {
      final r = base.copyWith(volumePercent: 90);
      expect(r.volumePercent, 90);
      expect(r.deviceId, 'dev');
      expect(r.deviceName, 'NeoFy');
      expect(r.contextUri, 'spotify:playlist:1');
      expect(r.isPlaying, isTrue);
      expect(r.shuffle, isTrue);
      expect(r.repeat, 'context');
      expect(r.progressMs, 1000);
    });

    test('sin argumentos no cambia nada', () {
      final r = base.copyWith();
      expect(r.volumePercent, 40);
      expect(r.isPlaying, isTrue);
      expect(r.repeat, 'context');
    });

    test('permite bajar el volumen a cero', () {
      expect(base.copyWith(volumePercent: 0).volumePercent, 0);
    });
  });

  group('formatMs', () {
    test('formatea como m:ss', () {
      expect(formatMs(0), '0:00');
      expect(formatMs(9000), '0:09');
      expect(formatMs(65000), '1:05');
      expect(formatMs(185000), '3:05');
      expect(formatMs(3600000), '60:00');
    });
  });
}
