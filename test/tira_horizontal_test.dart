import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/ui/tira_horizontal.dart';

Widget _conTira({required int tarjetas, double ancho = 300}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: ancho,
          child: TiraHorizontal(
            alto: 100,
            itemCount: tarjetas,
            itemBuilder: (context, i) =>
                SizedBox(width: 120, child: Center(child: Text('tarjeta $i'))),
          ),
        ),
      ),
    ),
  );
}

Future<void> _rueda(WidgetTester tester, Finder sobre, double dy) async {
  final puntero = TestPointer(1, PointerDeviceKind.mouse);
  final centro = tester.getCenter(sobre);
  await tester.sendEventToBinding(puntero.hover(centro));
  await tester.sendEventToBinding(puntero.scroll(Offset(0, dy)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('si todo cabe, no hay flechas que estorben', (tester) async {
    await tester.pumpWidget(_conTira(tarjetas: 1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('con contenido de sobra aparece la flecha de la derecha',
      (tester) async {
    await tester.pumpWidget(_conTira(tarjetas: 20));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('la rueda del ratón mueve la tira en horizontal', (tester) async {
    await tester.pumpWidget(_conTira(tarjetas: 20));
    await tester.pumpAndSettle();

    await _rueda(tester, find.byType(TiraHorizontal), 200);

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('tocando el extremo, la rueda sigue bajando por la página',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            TiraHorizontal(
              alto: 100,
              itemCount: 1,
              itemBuilder: (context, i) => const SizedBox(width: 120),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await _rueda(tester, find.byType(TiraHorizontal), 200);

    expect(scroll.offset, greaterThan(0));
  });
}
