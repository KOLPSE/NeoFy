import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/ultima_reproduccion.dart';

const _track = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Maldición',
  artists: 'Cochejai, LeClasse, Pardo',
  album: 'Disco',
  artSmall: 'http://img/64',
  artMedium: 'http://img/300',
  durationMs: 163000,
  isLocal: false,
);

void main() {
  Directory dirTemporal() {
    final raiz = Directory('${Directory.systemTemp.path}'
        '/neofy_ultima_${DateTime.now().microsecondsSinceEpoch}');
    if (!raiz.existsSync()) raiz.createSync(recursive: true);
    return raiz;
  }

  test('lo que sonaba sobrevive a cerrar la app', () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = UltimaReproduccionStore(directorio: dir);
    expect(await store.cargar(), isNull);

    await store.guardar(const UltimaReproduccion(
      track: _track,
      posicionMs: 56000,
      contextUri: 'spotify:playlist:abc',
    ));

    final leida = await UltimaReproduccionStore(directorio: dir).cargar();
    expect(leida, isNotNull);
    expect(leida!.track.name, 'Maldición');
    expect(leida.track.artists, 'Cochejai, LeClasse, Pardo');
    expect(leida.track.artMedium, 'http://img/300');
    expect(leida.track.durationMs, 163000);
    expect(leida.posicionMs, 56000);
    expect(leida.contextUri, 'spotify:playlist:abc');
    expect(leida.uris, isNull);
  });

  test('un fichero corrupto no impide arrancar', () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));

    File('${dir.path}/ultima_reproduccion.json').writeAsStringSync('{no es json');
    expect(await UltimaReproduccionStore(directorio: dir).cargar(), isNull);

    File('${dir.path}/ultima_reproduccion.json').writeAsStringSync('{"posicionMs": 10}');
    expect(await UltimaReproduccionStore(directorio: dir).cargar(), isNull);
  });

  group('la cola se guarda desde la canción que sonaba', () {
    test('se recorta lo ya escuchado', () {
      expect(
        UltimaReproduccion.colaDesde(const ['a', 'b', 'c', 'd'], 'c'),
        ['c', 'd'],
      );
    });

    test('si la canción no está en la lista se guarda entera', () {
      expect(
        UltimaReproduccion.colaDesde(const ['a', 'b'], 'z'),
        ['a', 'b'],
      );
    });

    test('una biblioteca enorme no se lleva el fichero por delante', () {
      final gigante = [for (var i = 0; i < 5000; i++) 'spotify:track:$i'];
      final cola = UltimaReproduccion.colaDesde(gigante, 'spotify:track:4000');

      expect(cola, hasLength(UltimaReproduccion.kMaxUris));
      expect(cola!.first, 'spotify:track:4000');
    });

    test('sin lista suelta no hay nada que recordar', () {
      expect(UltimaReproduccion.colaDesde(null, 'a'), isNull);
      expect(UltimaReproduccion.colaDesde(const [], 'a'), isNull);
    });
  });
}
