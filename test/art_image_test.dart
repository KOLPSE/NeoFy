import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/ui/art_image.dart';

/// Un PNG de 1x1 válido. Hace falta que decodifique de verdad para que el
/// widget llegue a construir el `Image`.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  // La caché nombra los ficheros por el sha1 de la URL. Se planta uno a mano
  // para que no haga falta red: `flutter test` la tiene mockeada a 400.
  const url = 'https://ejemplo.invalido/neofy-test/portada.png';
  final fichero = File(p.join(
      appDataDir().path, 'art', '${sha1.convert(url.codeUnits)}.img'));

  setUp(() {
    fichero.parent.createSync(recursive: true);
    fichero.writeAsBytesSync(_png);
  });

  tearDown(() {
    if (fichero.existsSync()) fichero.deleteSync();
  });

  testWidgets('pinta desde fichero, nunca desde bytes en memoria',
      (tester) async {
    // `runAsync` hace falta porque la caché toca disco de verdad: fuera de él,
    // el reloj falso de `flutter_test` no deja completar la E/S.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ArtImage(url: url, size: 40)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });

    final imagen = tester.widget<Image>(find.byType(Image));

    // `cacheWidth` envuelve al proveedor en un ResizeImage: es lo que evita
    // guardar el bitmap a resolución completa.
    final resize = imagen.image as ResizeImage;

    // ⚠️ El fondo del asunto: con `MemoryImage` el `Uint8List` con el JPEG
    // entero se queda vivo como clave dentro del imageCache de Flutter, así
    // que por cada carátula se guardaban el bitmap decodificado **y** el
    // fichero comprimido. Con `FileImage` la clave es una ruta.
    expect(resize.imageProvider, isA<FileImage>());
    expect(resize.imageProvider, isNot(isA<MemoryImage>()));
  });

  group('elige la variante por píxeles reales, no por tamaño lógico', () {
    // Solo existe en disco la variante pequeña; si el widget se bajara la
    // grande, el fichero no estaría y saldría el hueco. Eso es lo que se mide.
    Future<void> montar(WidgetTester tester, double dpr, double size) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: dpr),
            child: Scaffold(
              body: ArtImage(
                url: url,
                urlGrande: 'https://ejemplo.invalido/no-existe-en-disco.jpg',
                size: size,
              ),
            ),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });
    }

    testWidgets('56 px al 100 % caben en la de 64: usa la pequeña',
        (tester) async {
      await montar(tester, 1.0, 56);
      // La barra de reproducción es este caso: antes se bajaba la de 300
      // (hasta 78 KB) para pintar 56 píxeles.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('los mismos 56 px al 200 % ya no caben: pide la grande',
        (tester) async {
      await montar(tester, 2.0, 56);
      // Pide la grande, que en este test no existe en disco: sale el hueco.
      // Lo que importa es que NO se conforme con la pequeña y se vea blanda.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('una tarjeta de 128 px pide la grande hasta al 100 %',
        (tester) async {
      await montar(tester, 1.0, 128);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('modo rendimiento', () {
    tearDown(() => modoRendimiento.value = false);

    testWidgets('no baja ni una imagen: pinta el mosaico', (tester) async {
      modoRendimiento.value = true;
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ArtImage(url: url, size: 40)),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });

      // El fichero SI existe en disco, asi que sin modo rendimiento saldria la
      // imagen. Que no salga es justo la prueba de que no se pide nada.
      expect(find.byType(Image), findsNothing);
      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('encenderlo repinta las caratulas ya montadas', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ArtImage(url: url, size: 40)),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });
      expect(find.byType(Image), findsOneWidget);

      // Sin este repintado, las filas que ya estuvieran en pantalla seguirian
      // con su bitmap en memoria hasta que el usuario hiciera scroll.
      modoRendimiento.value = true;
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('el color sale de la url: el mismo disco, el mismo tono',
        (tester) async {
      modoRendimiento.value = true;
      Future<Gradient?> tonoDe(String u) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ArtImage(url: u, size: 40)),
        ));
        await tester.pump();
        final d = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
        return d
            .map((w) => (w.decoration as BoxDecoration).gradient)
            .firstWhere((g) => g != null, orElse: () => null);
      }

      final uno = await tonoDe('https://ejemplo/a.jpg');
      final otraVez = await tonoDe('https://ejemplo/a.jpg');
      final distinto = await tonoDe('https://ejemplo/b.jpg');

      expect(uno, isNotNull);
      expect(uno, equals(otraVez));
      expect(uno, isNot(equals(distinto)));
    });
  });

  testWidgets('sin url se queda en el hueco, sin reventar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ArtImage(url: null, size: 40)),
    ));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
