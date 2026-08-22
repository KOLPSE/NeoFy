import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/movimiento.dart';

Widget _envoltorio({required Tema tema, required bool abierto}) {
  return MaterialApp(
    theme: construirThemeData(tema),
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Plegable(
              key: const ValueKey('plegable'),
              abierto: abierto,
              contenidoAbierto: const Text('LA LISTA'),
              contenidoCerrado: const Text('PLEGADO'),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('plegado, el contenido abierto no está en el árbol', (t) async {
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: false));

    expect(find.text('PLEGADO'), findsOneWidget);
    expect(
      find.text('LA LISTA'),
      findsNothing,
      reason: 'si se construye plegada, con mil playlists se paga por nada',
    );
  });

  testWidgets('abierto del todo, el contenido plegado desaparece', (t) async {
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: true));
    await t.pump(const Duration(seconds: 2));

    expect(find.text('LA LISTA'), findsOneWidget);
    expect(find.text('PLEGADO'), findsNothing);
  });

  testWidgets('durante la transición conviven los dos, y acaba asentando',
      (t) async {
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: false));
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: true));

    await t.pump(const Duration(milliseconds: 16));
    expect(find.text('LA LISTA'), findsOneWidget);
    expect(find.text('PLEGADO'), findsOneWidget,
        reason: 'se cruzan, no se cortan de golpe');

    await t.pump(const Duration(seconds: 2));
    expect(find.text('PLEGADO'), findsNothing);
  });

  testWidgets('es un acordeón: la altura del contenido crece de verdad',
      (t) async {
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: false));
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: true));
    await t.pump(const Duration(milliseconds: 16));

    expect(find.byType(SizeTransition), findsOneWidget);
    expect(
      t.widget<SizeTransition>(find.byType(SizeTransition)).sizeFactor.value,
      lessThan(1),
      reason: 'como max-height en CSS: el hueco crece, no aparece de golpe',
    );
  });

  testWidgets('el hueco recorta el overflow, como overflow:hidden',
      (t) async {
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: false));
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: true));
    await t.pump(const Duration(milliseconds: 40));

    expect(
      find.ancestor(of: find.text('LA LISTA'), matching: find.byType(ClipRect)),
      findsWidgets,
      reason: 'equivale a overflow: hidden del desplegable CSS',
    );
  });

  testWidgets('van apiladas, no en columna: la lista tapa a la fijada',
      (t) async {
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: false));
    await t.pumpWidget(_envoltorio(tema: temaMaterialOscuro, abierto: true));
    await t.pump(const Duration(milliseconds: 40));

    if (find.text('PLEGADO').evaluate().isEmpty) return;

    expect(
      t.getTopLeft(find.text('PLEGADO')).dy,
      closeTo(t.getTopLeft(find.text('LA LISTA')).dy, 1),
      reason: 'si estuvieran en columna, la fijada bajaría al crecer la '
          'lista y se vería aplastada debajo',
    );
  });

  testWidgets('con movimiento "ninguno" el cambio es instantáneo', (t) async {
    const quieto = Tema(
      id: 'quieto',
      nombre: 'Quieto',
      brillo: BrilloDeTema.oscuro,
      movimiento: Movimiento(esquema: EsquemaDeMovimiento.ninguno),
      colores: Paleta(
        primario: Color(0xFF1DB954),
        sobrePrimario: Color(0xFF000000),
        fondo: Color(0xFF121212),
        superficie: Color(0xFF1C1C1C),
        panel: Color(0xFF0A0A0A),
        texto: Color(0xFFF2F2F2),
        textoTenue: Color(0xFFA8A8A8),
        borde: Color(0xFF2A2A2A),
        error: Color(0xFFFF6B6B),
      ),
    );

    await t.pumpWidget(_envoltorio(tema: quieto, abierto: false));
    await t.pumpWidget(_envoltorio(tema: quieto, abierto: true));
    await t.pump();

    expect(find.text('LA LISTA'), findsOneWidget);
    expect(find.text('PLEGADO'), findsNothing,
        reason: 'sin movimiento no hay cruce: se cambia y ya');
  });
}
