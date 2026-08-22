import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/titulo_desplazable.dart';

const _largo =
    'Bohemian Rhapsody - Remastered 2011 Deluxe Edition en directo desde Wembley';

Widget _envoltorio(String texto, {double ancho = 160, Tema? tema}) {
  return MaterialApp(
    theme: construirThemeData(tema ?? temaMaterialOscuro),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: ancho,
          child: TituloDesplazable(texto: texto),
        ),
      ),
    ),
  );
}

double _desplazamiento(WidgetTester t) {
  final trans = t.widgetList<Transform>(
    find.descendant(
      of: find.byType(TituloDesplazable),
      matching: find.byType(Transform),
    ),
  );
  if (trans.isEmpty) return 0;
  return -trans.first.transform.getTranslation().x;
}

Future<void> _entrar(WidgetTester t) async {
  final raton = await t.createGesture(kind: PointerDeviceKind.mouse);
  await raton.addPointer(location: Offset.zero);
  addTearDown(raton.removePointer);
  await t.pump();
  await raton.moveTo(t.getCenter(find.byType(TituloDesplazable)));
  await t.pump();
}

bool sinExcepciones() =>
    TestWidgetsFlutterBinding.instance.takeException() == null;

Widget _comoEnLaBarra(String texto) {
  return MaterialApp(
    theme: construirThemeData(temaMaterialOscuro),
    home: Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: TituloDesplazable(texto: texto)),
                    const SizedBox(width: 6),
                    const Icon(Icons.favorite, size: 20),
                  ],
                ),
                TituloDesplazable(texto: 'Un artista con nombre larguísimo'),
              ],
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    ),
  );
}

void main() {
  tearDown(() => modoRendimiento.value = false);

  testWidgets('montado como en la barra real no desborda ni revienta',
      (t) async {
    await t.pumpWidget(_comoEnLaBarra(_largo));
    await t.pump();
    expect(sinExcepciones(), isTrue);

    final raton = await t.createGesture(kind: PointerDeviceKind.mouse);
    await raton.addPointer(location: Offset.zero);
    addTearDown(raton.removePointer);
    await t.pump();
    await raton.moveTo(t.getCenter(find.byType(TituloDesplazable).first));
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    expect(sinExcepciones(), isTrue,
        reason: 'pasar el ratón por encima no puede tirar el render');

    final caja = t.getSize(find.byType(TituloDesplazable).first);
    expect(caja.height.isFinite, isTrue,
        reason: 'dentro de un Column con mainAxisSize.min la altura que '
            'llega es ilimitada; el título no puede heredarla');
    expect(caja.height, lessThan(100));
  });

  testWidgets('un nombre que cabe no se desplaza ni con el ratón encima',
      (t) async {
    await t.pumpWidget(_envoltorio('Sin Ti'));
    await _entrar(t);
    await t.pump(const Duration(seconds: 2));

    expect(
      find.descendant(
        of: find.byType(TituloDesplazable),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    expect(_desplazamiento(t), 0);
  });

  testWidgets('en reposo, un nombre largo se corta con puntos suspensivos',
      (t) async {
    await t.pumpWidget(_envoltorio(_largo));
    await t.pump();

    final texto = t.widget<Text>(find.text(_largo));
    expect(texto.overflow, TextOverflow.ellipsis);
    expect(_desplazamiento(t), 0);
  });

  testWidgets('con el ratón encima avanza hasta enseñar el final', (t) async {
    await t.pumpWidget(_envoltorio(_largo));
    await _entrar(t);

    await t.pump(const Duration(milliseconds: 300));
    final aMitad = _desplazamiento(t);
    expect(aMitad, greaterThan(0));

    await t.pump(const Duration(seconds: 60));
    final alFinal = _desplazamiento(t);
    expect(alFinal, greaterThan(aMitad));

    await t.pump(const Duration(seconds: 30));
    expect(_desplazamiento(t), closeTo(alFinal, 0.5),
        reason: 'al llegar al final se para; no da vueltas eternamente');
  });

  testWidgets('al quitar el ratón vuelve al principio', (t) async {
    await t.pumpWidget(_envoltorio(_largo));
    final raton = await t.createGesture(kind: PointerDeviceKind.mouse);
    await raton.addPointer(location: Offset.zero);
    addTearDown(raton.removePointer);
    await t.pump();
    await raton.moveTo(t.getCenter(find.byType(TituloDesplazable)));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(_desplazamiento(t), greaterThan(0));

    await raton.moveTo(const Offset(5, 5));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(_desplazamiento(t), 0);
  });

  testWidgets('cambiar de canción devuelve el título al principio', (t) async {
    await t.pumpWidget(_envoltorio(_largo));
    await _entrar(t);
    await t.pump(const Duration(seconds: 2));
    expect(_desplazamiento(t), greaterThan(0));

    await t.pumpWidget(_envoltorio('$_largo (otra)'));
    await t.pump();
    expect(_desplazamiento(t), 0,
        reason: 'la canción nueva no puede empezar a media palabra de la '
            'anterior');
  });

  testWidgets('el modo rendimiento lo deja quieto', (t) async {
    modoRendimiento.value = true;
    await t.pumpWidget(_envoltorio(_largo));
    await _entrar(t);
    await t.pump(const Duration(seconds: 3));

    expect(_desplazamiento(t), 0);
  });
}
