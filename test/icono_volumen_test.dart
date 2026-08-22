import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/icono_de_volumen.dart';

Widget _env({required double volumen, required bool muteado}) {
  return MaterialApp(
    theme: construirThemeData(temaMaterialOscuro),
    home: Scaffold(
      body: IconoDeVolumen(volumen: volumen, muteado: muteado),
    ),
  );
}

PintorDeVolumen _pintor(WidgetTester t) {
  final paint = t.widget<CustomPaint>(
    find.descendant(
      of: find.byType(IconoDeVolumen),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as PintorDeVolumen;
}

void main() {
  testWidgets('silenciado y a cero pintan el mismo estado, no otro icono',
      (t) async {
    await t.pumpWidget(_env(volumen: 80, muteado: true));
    expect(_pintor(t).nivel, 0);

    await t.pumpWidget(_env(volumen: 0, muteado: false));
    expect(_pintor(t).nivel, 0);
  });

  testWidgets('al cambiar el volumen el dibujo se mueve, no se sustituye',
      (t) async {
    await t.pumpWidget(_env(volumen: 10, muteado: false));
    final bajo = _pintor(t).nivel;

    await t.pumpWidget(_env(volumen: 90, muteado: false));
    await t.pump(const Duration(milliseconds: 50));
    final aMitad = _pintor(t).nivel;
    await t.pump(const Duration(milliseconds: 400));
    final alto = _pintor(t).nivel;

    expect(bajo, lessThan(1));
    expect(alto, greaterThan(bajo));
    expect(aMitad, inExclusiveRange(bajo, alto + 0.01));
  });
}
