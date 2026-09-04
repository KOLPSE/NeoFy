import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/tema_store.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/personalizacion_tema.dart';
import 'package:neofy/ui/temas_dialog.dart';

class _FakeConfig extends AppConfig {
  _FakeConfig({super.tema, super.temaColores});

  @override
  Future<void> save() async {}
}

OutlinedButton _botonCrear(WidgetTester t) {
  return t.widget<OutlinedButton>(
    find.ancestor(
      of: find.text('Crear una plantilla'),
      matching: find.byType(OutlinedButton),
    ),
  );
}

Future<void> _abrirSelector(
  WidgetTester t, {
  required String tema,
  Map<String, Map<String, String>>? colores,
}) async {
  final config = _FakeConfig(tema: tema, temaColores: colores);
  final temas = TemaStore(config);
  final settings = Settings(config);
  addTearDown(temas.dispose);

  await t.pumpWidget(
    MaterialApp(
      theme: construirThemeData(temaMaterialOscuro),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => mostrarSelectorDeTemas(context, temas, settings),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('en Material salen los colores y se puede crear la plantilla',
      (t) async {
    await _abrirSelector(t, tema: 'material-oscuro');

    expect(find.text('Acento'), findsOneWidget);
    expect(find.text('Fondo'), findsOneWidget);
    expect(find.text('Paneles'), findsOneWidget);
    expect(_botonCrear(t).onPressed, isNotNull);
  });

  testWidgets('fuera de Material no hay colores y no se crea plantilla',
      (t) async {
    await _abrirSelector(t, tema: 'liquid-glass');

    expect(find.text('Acento'), findsNothing);
    expect(_botonCrear(t).onPressed, isNull);
  });

  testWidgets('un tema de la comunidad tampoco abre el editor de color',
      (t) async {
    await _abrirSelector(t, tema: 'mi-tema');

    expect(find.text('Acento'), findsNothing);
    expect(_botonCrear(t).onPressed, isNull);
  });

  testWidgets('un color propio con Temas abierto no tira la app',
      (t) async {
    final config = _FakeConfig(tema: 'material-oscuro');
    final temas = TemaStore(config);
    final settings = Settings(config);
    addTearDown(temas.dispose);

    await t.pumpWidget(
      AnimatedBuilder(
        animation: temas,
        builder: (context, _) => MaterialApp(
          theme: temas.themeDataOscuro,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    mostrarSelectorDeTemas(context, temas, settings),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();

    final propio = find.byTooltip('Color propio…').first;
    await t.ensureVisible(propio);
    await t.tap(propio);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '#1DB954');
    await t.tap(find.text('Aplicar'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.text('Color propio'), findsNothing);
    expect(find.text('Acento'), findsOneWidget);
    expect(temas.retoquesDe('material-oscuro')['primario'], '#1DB954');
  });

  testWidgets('los retoques de Material se ven en el editor', (t) async {
    final config = _FakeConfig(
      tema: 'material-oscuro',
      temaColores: {
        'material-oscuro': {'primario': '#1DB954'},
      },
    );
    final temas = TemaStore(config);
    addTearDown(temas.dispose);

    await t.pumpWidget(
      MaterialApp(
        theme: construirThemeData(temaMaterialOscuro),
        home: Scaffold(
          body: PersonalizacionTema(
            temas: temas,
            settings: Settings(config),
          ),
        ),
      ),
    );
    await t.pump();

    expect(find.text('Acento'), findsOneWidget);
    expect(temas.porId('material-oscuro')!.colores.primario,
        const Color(0xFF1DB954));
  });
}
