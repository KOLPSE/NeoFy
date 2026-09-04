import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/desplegable_en_sitio.dart';

Widget _app({required Widget child}) {
  return MaterialApp(
    theme: construirThemeData(temaMaterialOscuro),
    home: Scaffold(body: child),
  );
}

Widget _fila({VoidCallback? onQuitar}) {
  return DesplegableEnSitio(
    opciones: [
      OpcionEnSitio(
        icono: Icons.remove_circle_outline,
        texto: 'Quitar de tu biblioteca',
        onTap: onQuitar ?? () {},
        destructiva: true,
        confirmacion: '¿Quitar «Favoritas» de tu biblioteca?',
        textoConfirmar: 'Quitar',
      ),
    ],
    constructor: (context, disparador) => ListTile(
      dense: true,
      leading: const Icon(Icons.album),
      title: const Text('Favoritas'),
      subtitle: const Text('12 canciones'),
      trailing: disparador,
    ),
  );
}

void main() {
  setUp(() => menusEnElemento.value = true);
  tearDown(() => menusEnElemento.value = true);

  testWidgets('cerrado, se ve el tile y no las opciones', (t) async {
    await t.pumpWidget(_app(child: _fila()));

    expect(find.text('Favoritas'), findsOneWidget);
    expect(find.text('12 canciones'), findsOneWidget);
    expect(find.text('Quitar de tu biblioteca'), findsNothing);
  });

  testWidgets('al abrir, las opciones ocupan logo, nombre y subtítulo',
      (t) async {
    await t.pumpWidget(_app(child: _fila()));

    await t.tap(find.byTooltip('Opciones'));
    await t.pumpAndSettle();

    expect(find.text('Favoritas'), findsNothing);
    expect(find.text('12 canciones'), findsNothing);
    expect(find.byIcon(Icons.album), findsNothing);
    expect(find.text('Quitar de tu biblioteca'), findsOneWidget);
  });

  testWidgets('el aviso de borrar sale en el mismo hueco, no en un diálogo',
      (t) async {
    var quitada = false;
    await t.pumpWidget(_app(child: _fila(onQuitar: () => quitada = true)));

    await t.tap(find.byTooltip('Opciones'));
    await t.pumpAndSettle();
    await t.tap(find.text('Quitar de tu biblioteca'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('¿Quitar «Favoritas» de tu biblioteca?'), findsOneWidget);
    expect(quitada, isFalse);

    await t.tap(find.text('Quitar'));
    await t.pumpAndSettle();

    expect(quitada, isTrue);
    expect(find.text('Favoritas'), findsOneWidget);
  });

  testWidgets('con la preferencia apagada vuelve el menú flotante', (t) async {
    menusEnElemento.value = false;
    await t.pumpWidget(_app(child: _fila()));

    expect(find.byType(PopupMenuButton<int>), findsOneWidget);
    expect(find.text('Favoritas'), findsOneWidget);
  });
}
