import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/onda_de_progreso.dart';

Widget _barra({
  required Tema tema,
  required bool enMarcha,
  double valor = 400,
}) {
  return MaterialApp(
    theme: construirThemeData(tema),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: BarraDeProgreso(
            valor: valor,
            maximo: 1000,
            enMarcha: enMarcha,
            onCambio: (_) {},
            onFinDelCambio: (_) {},
          ),
        ),
      ),
    ),
  );
}

double _fraccionPintada(WidgetTester t) {
  final pintado = t.widget<CustomPaint>(
    find.descendant(
      of: find.byType(BarraDeProgreso),
      matching: find.byType(CustomPaint),
    ),
  );
  return (pintado.painter! as PintorDeOnda).fraccion;
}

void main() {
  tearDown(() => modoRendimiento.value = false);

  group('la envolvente de la onda', () {
    test('es cero justo en el cabezal, para que empalme con la pista', () {
      expect(envolventeDeLaOnda(0), 0);
      expect(envolventeDeLaOnda(-5), 0);
      expect(envolventeDeLaOnda(1), lessThan(0.1),
          reason: 'si no llega plana al cabezal, corta a media altura y '
              'no conecta con lo que queda por escuchar');
    });

    test('es cero por detrás del alcance: la cola vieja va lisa', () {
      expect(envolventeDeLaOnda(kAlcanceDeLaOnda), 0);
      expect(envolventeDeLaOnda(kAlcanceDeLaOnda + 500), 0);
      expect(envolventeDeLaOnda(kAlcanceDeLaOnda - 1), lessThan(0.1));
    });

    test('solo ondula en el tramo de delante', () {
      expect(envolventeDeLaOnda(kApagadoJuntoAlPulgar), greaterThan(0.9));
      expect(envolventeDeLaOnda(60), greaterThan(0.5));
    });

    test('nunca se sale de 0..1', () {
      for (var d = -20.0; d < kAlcanceDeLaOnda + 40; d += 0.5) {
        final v = envolventeDeLaOnda(d);
        expect(v, inInclusiveRange(0, 1), reason: 'con atrás=$d');
      }
    });
  });

  testWidgets('los temas de línea siguen usando el Slider de siempre',
      (t) async {
    await t.pumpWidget(_barra(tema: temaOscuro, enMarcha: true));
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('los temas de onda no usan Slider, pintan la onda', (t) async {
    await t.pumpWidget(_barra(tema: temaMaterialOscuro, enMarcha: true));
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('en pausa no queda ninguna animación corriendo', (t) async {
    await t.pumpWidget(_barra(tema: temaMaterialOscuro, enMarcha: true));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.hasRunningAnimations, isTrue,
        reason: 'sonando, la onda viaja');

    await t.pumpWidget(_barra(tema: temaMaterialOscuro, enMarcha: false));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));

    expect(
      t.hasRunningAnimations,
      isFalse,
      reason: 'en pausa no puede quedar nada girando de fondo',
    );
  });

  testWidgets('el modo rendimiento apaga la onda aunque esté sonando',
      (t) async {
    modoRendimiento.value = true;
    await t.pumpWidget(_barra(tema: temaMaterialOscuro, enMarcha: true));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));

    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('al acabar la canción, la barra vuelve andando, no de golpe',
      (t) async {
    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 999));
    await t.pump(const Duration(milliseconds: 100));
    expect(_fraccionPintada(t), greaterThan(0.99),
        reason: 'queda 1 ms: la barra ya está al final, interpolando');

    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 0));
    await t.pump(const Duration(milliseconds: 16));

    expect(
      _fraccionPintada(t),
      greaterThan(0.5),
      reason: 'un fotograma después todavía tiene que estar volviendo; si ya '
          'estuviera en cero es que saltó de golpe',
    );

    await t.pump(const Duration(milliseconds: 900));
    expect(_fraccionPintada(t), closeTo(0, 0.02),
        reason: 'y tiene que llegar hasta el principio');
  });

  testWidgets('un salto hacia atrás normal no dispara el rebobinado',
      (t) async {
    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: false, valor: 600));
    await t.pump(const Duration(milliseconds: 400));

    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: false, valor: 100));
    await t.pump(const Duration(milliseconds: 16));

    expect(
      _fraccionPintada(t),
      closeTo(0.1, 0.001),
      reason: 'solo se rebobina al terminar la canción, no cada vez que el '
          'usuario retrocede',
    );
  });

  testWidgets('al 100 % el pulgar no traspasa el final', (t) async {
    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: false, valor: 1000));
    await t.pump(const Duration(milliseconds: 400));

    final pintado = t.widget<CustomPaint>(
      find.descendant(
        of: find.byType(BarraDeProgreso),
        matching: find.byType(CustomPaint),
      ),
    );
    final ancho = pintado.size.width;
    final cabezal =
        kAnchoDelPulgar / 2 + (ancho - kAnchoDelPulgar) * _fraccionPintada(t);

    expect(
      cabezal + kAnchoDelPulgar / 2,
      lessThanOrEqualTo(ancho),
      reason: 'el borde derecho del pulgar tiene que caber dentro del área '
          'pintada, o se sale por encima del tiempo total',
    );
  });

  testWidgets('sonando, la barra avanza sola aunque el valor no cambie',
      (t) async {
    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 0));
    await t.pump();
    expect(_fraccionPintada(t), closeTo(0, 0.001));

    await t.pump(const Duration(milliseconds: 250));

    expect(
      _fraccionPintada(t),
      closeTo(0.25, 0.02),
      reason: 'el reproductor solo avisa cada ~250 ms; si la barra espera '
          'ese aviso se ve a tirones. Tiene que interpolar a tiempo real',
    );
  });

  testWidgets('un recálculo pequeño no hace saltar la barra', (t) async {
    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 0));
    await t.pump(const Duration(milliseconds: 250));
    final antes = _fraccionPintada(t);

    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 200));
    await t.pump();

    expect(
      (_fraccionPintada(t) - antes).abs(),
      lessThan(0.03),
      reason: '200 ms de diferencia es el tick del reproductor, no un seek: '
          'colocar la barra ahí de golpe es el tirón que se veía',
    );
  });

  testWidgets('un seek de verdad sí coloca la barra al momento', (t) async {
    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 0));
    await t.pump(const Duration(milliseconds: 100));

    await t.pumpWidget(
        _barra(tema: temaMaterialOscuro, enMarcha: true, valor: 800));
    await t.pump();

    expect(
      _fraccionPintada(t),
      closeTo(0.8, 0.02),
      reason: 'un salto de 800 ms supera la holgura: es un seek, no un tick',
    );
  });

  testWidgets('tocar la barra pide un salto a esa posición', (t) async {
    final saltos = <double>[];
    await t.pumpWidget(
      MaterialApp(
        theme: construirThemeData(temaMaterialOscuro),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: BarraDeProgreso(
                valor: 0,
                maximo: 1000,
                enMarcha: false,
                onCambio: (_) {},
                onFinDelCambio: saltos.add,
              ),
            ),
          ),
        ),
      ),
    );

    final caja = t.getRect(find.byType(BarraDeProgreso));
    final x = caja.left + caja.width * 0.25;
    await t.tapAt(Offset(x, caja.center.dy));
    await t.pump();

    final anchoUtil = caja.width - kMargenLateral * 2;
    final esperado = (x - caja.left - kMargenLateral) / anchoUtil * 1000;

    expect(saltos, hasLength(1));
    expect(
      saltos.single,
      closeTo(esperado, 0.5),
      reason: 'el margen lateral tiene que descontarse de la posición, o '
          'la canción salta a un sitio distinto del que has tocado',
    );
  });
}
