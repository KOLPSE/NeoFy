import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/ui/art_image.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  const url = 'https://ejemplo.invalido/neofy-test/portada.png';
  final fichero = File(p.join(
      cacheDir().path, 'art', '${sha1.convert(url.codeUnits)}.img'));

  setUp(() {
    fichero.parent.createSync(recursive: true);
    fichero.writeAsBytesSync(_png);
  });

  tearDown(() {
    if (fichero.existsSync()) fichero.deleteSync();
  });

  testWidgets('pinta desde fichero, nunca desde bytes en memoria',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ArtImage(url: url, size: 40)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });

    final imagen = tester.widget<Image>(find.byType(Image));

    final resize = imagen.image as ResizeImage;

    expect(resize.imageProvider, isA<FileImage>());
    expect(resize.imageProvider, isNot(isA<MemoryImage>()));
  });

  group('elige la variante por píxeles reales, no por tamaño lógico', () {
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
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('los mismos 56 px al 200 % ya no caben: pide la grande',
        (tester) async {
      await montar(tester, 2.0, 56);
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
