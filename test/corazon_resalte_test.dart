import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/corazon_animado.dart';

Widget _envoltorio({required bool lleno}) {
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
                    const Flexible(child: Text('Una canción')),
                    const SizedBox(width: 6),
                    CorazonAnimado(
                      lleno: lleno,
                      tooltip: 'Favoritos',
                      onTap: () {},
                      caja: 24,
                    ),
                  ],
                ),
                const Text('Un artista'),
              ],
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    ),
  );
}

Color _colorDelBorde(WidgetTester t) {
  final icono = t.widget<Icon>(find.byIcon(Icons.favorite_border));
  return icono.color!;
}

Color _colorDelRelleno(WidgetTester t) {
  final icono = t.widget<Icon>(find.byIcon(Icons.favorite));
  return icono.color!;
}

Future<TestGesture> _raton(WidgetTester t) async {
  final raton = await t.createGesture(kind: PointerDeviceKind.mouse);
  await raton.addPointer(location: Offset.zero);
  addTearDown(raton.removePointer);
  await t.pump();
  return raton;
}

void main() {
  tearDown(() => modoRendimiento.value = false);

  testWidgets('sin ratón encima, el corazón vacío va en gris', (t) async {
    await t.pumpWidget(_envoltorio(lleno: false));
    await t.pump();

    expect(_colorDelBorde(t), isNot(kColorFavorito));
  });

  testWidgets('con el ratón encima se pone rojo', (t) async {
    await t.pumpWidget(_envoltorio(lleno: false));
    final gris = _colorDelBorde(t);

    final raton = await _raton(t);
    await raton.moveTo(t.getCenter(find.byType(CorazonAnimado)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    expect(_colorDelBorde(t), kColorFavorito,
        reason: 'el resaltado es la señal de que se puede pulsar');
    expect(_colorDelBorde(t), isNot(gris));
  });

  testWidgets('al quitar el ratón vuelve al gris', (t) async {
    await t.pumpWidget(_envoltorio(lleno: false));
    final gris = _colorDelBorde(t);

    final raton = await _raton(t);
    await raton.moveTo(t.getCenter(find.byType(CorazonAnimado)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(_colorDelBorde(t), kColorFavorito);

    await raton.moveTo(const Offset(5, 5));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    expect(_colorDelBorde(t), gris);
  });

  testWidgets('si ya está en favoritos, el relleno también se aclara',
      (t) async {
    await t.pumpWidget(_envoltorio(lleno: true));
    await t.pump(const Duration(seconds: 2));
    expect(_colorDelRelleno(t), kColorFavorito);

    final raton = await _raton(t);
    await raton.moveTo(t.getCenter(find.byType(CorazonAnimado)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    expect(_colorDelRelleno(t), kColorFavoritoResaltado,
        reason: 'con el corazón lleno el borde no se ve, así que la señal '
            'tiene que darla el relleno');
  });

  testWidgets('con movimiento apagado el cambio es instantáneo, no gradual',
      (t) async {
    modoRendimiento.value = true;
    await t.pumpWidget(_envoltorio(lleno: false));

    final raton = await _raton(t);
    await raton.moveTo(t.getCenter(find.byType(CorazonAnimado)));
    await t.pump();

    expect(_colorDelBorde(t), kColorFavorito,
        reason: 'sin animación se pinta rojo en el primer fotograma');
  });
}
