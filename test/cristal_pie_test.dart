import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/cristal.dart';

void main() {
  testWidgets(
    'con altura acotada el pie del cristal llega abajo, no se queda arriba',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: construirThemeData(temaLiquidGlass),
          home: const Center(
            child: SizedBox(
              width: 244,
              height: 400,
              child: PanelDeCristal(
                child: Column(
                  children: [
                    Expanded(child: SizedBox.expand()),
                    Text('pie'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();

      final caja = t.getRect(find.byType(PanelDeCristal));
      final pie = t.getRect(find.text('pie'));
      expect(pie.bottom, closeTo(caja.bottom, 2));
    },
  );
}
