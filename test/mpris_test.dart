import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/mpris.dart';

Track _track({
  String id = '4cOdK2wGLETKBW3PvgPWqT',
  String artists = 'Rick Astley',
  int durationMs = 213573,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: 'Never Gonna Give You Up',
      artists: artists,
      album: 'Whenever You Need Somebody',
      artSmall: 'https://i.scdn.co/image/pequena',
      artMedium: 'https://i.scdn.co/image/mediana',
      durationMs: durationMs,
      isLocal: false,
    );

EstadoDelSistema _estado({Track? track, bool sonando = true}) => EstadoDelSistema(
      track: track,
      sonando: sonando,
      posicionMs: 42000,
      puedeSaltar: true,
      puedeVolver: true,
      volumen: 70,
    );

void main() {
  group('estado de reproduccion', () {
    test('sin cancion es Stopped, no Paused', () {
      expect(_estado(track: null, sonando: false).estadoDeReproduccion,
          'Stopped');
      expect(_estado(track: null).estadoDeReproduccion, 'Stopped');
    });

    test('con cancion distingue Playing de Paused', () {
      expect(_estado(track: _track()).estadoDeReproduccion, 'Playing');
      expect(_estado(track: _track(), sonando: false).estadoDeReproduccion,
          'Paused');
    });
  });

  group('metadatos', () {
    test('los artistas van como lista, no como la cadena de la fila', () {
      final datos = metadatosMpris(_track(artists: 'Daft Punk, Pharrell'));
      expect(datos['xesam:artist'], ['Daft Punk', 'Pharrell']);
    });

    test('sin artistas la lista va vacia, no con una cadena en blanco', () {
      final datos = metadatosMpris(_track(artists: ''));
      expect(datos['xesam:artist'], isEmpty);
    });

    test('la duracion pasa de milisegundos a microsegundos', () {
      expect(metadatosMpris(_track(durationMs: 213573))['mpris:length'],
          213573 * 1000);
    });

    test('el trackid es una ruta de objeto valida', () {
      expect(metadatosMpris(_track())['mpris:trackid'],
          '/xyz/neogex/neofy/track/4cOdK2wGLETKBW3PvgPWqT');
    });

    test('una pista sin id no genera una ruta invalida', () {
      final ruta = metadatosMpris(_track(id: ''))['mpris:trackid'] as String;
      expect(ruta, '/xyz/neogex/neofy/desconocida');
      expect(ruta.endsWith('/'), isFalse);
    });

    test('un videoId de YouTube no deja una ruta invalida', () {
      final ruta = metadatosMpris(_track(id: 'dQw4w9WgX-Q'))['mpris:trackid'] as String;
      expect(ruta, '/xyz/neogex/neofy/track/dQw4w9WgX_Q');
      expect(RegExp(r'^(/[A-Za-z0-9_]+)+$').hasMatch(ruta), isTrue);
    });

    test('sin cancion no hay metadatos que dar', () {
      expect(metadatosMpris(null), isEmpty);
    });

    test('la caratula se omite si no esta ya en disco', () {
      expect(metadatosMpris(_track()).containsKey('mpris:artUrl'), isFalse);
    });
  });

  group('caratula: se prueban las dos variantes', () {
    final dir = Directory(p.join(cacheDir().path, 'art'));

    File ficheroDe(String url) =>
        File(p.join(dir.path, '${sha1.convert(url.codeUnits)}.img'));

    setUp(() => dir.createSync(recursive: true));

    test('vale la pequena cuando la mediana no esta bajada', () {
      final f = ficheroDe('https://i.scdn.co/image/pequena');
      f.writeAsBytesSync([1, 2, 3]);
      addTearDown(() => f.existsSync() ? f.deleteSync() : null);

      final url = metadatosMpris(_track())['mpris:artUrl'] as String?;
      expect(url, isNotNull);
      expect(url, startsWith('file:'));
      expect(url, contains(sha1.convert('https://i.scdn.co/image/pequena'.codeUnits).toString()));
    });

    test('se prefiere la mediana cuando estan las dos', () {
      final pequena = ficheroDe('https://i.scdn.co/image/pequena');
      final mediana = ficheroDe('https://i.scdn.co/image/mediana');
      pequena.writeAsBytesSync([1]);
      mediana.writeAsBytesSync([1]);
      addTearDown(() {
        if (pequena.existsSync()) pequena.deleteSync();
        if (mediana.existsSync()) mediana.deleteSync();
      });

      expect(
        metadatosMpris(_track())['mpris:artUrl'] as String?,
        contains(sha1.convert('https://i.scdn.co/image/mediana'.codeUnits).toString()),
      );
    });
  });
}
