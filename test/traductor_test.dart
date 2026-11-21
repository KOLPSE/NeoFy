import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/traductor.dart';
import 'package:neofy/ui/texto_traducido.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('T muestra el texto en español si el idioma objetivo es es', (tester) async {
    final traductor = Traductor(
      localeEfectivo: () => 'es_ES',
      simulado: true,
    );
    addTearDown(traductor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TraductorScope(
          notifier: traductor,
          child: const Scaffold(body: T('Ajustes')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ajustes'), findsOneWidget);
  });

  testWidgets('BiografiaTraducida muestra el texto de entrada en modo simulado',
      (tester) async {
    const ingles =
        'The Chainsmokers mix indie, dance, and pop into a chart-topping sound.';
    final traductor = Traductor(
      localeEfectivo: () => 'es_ES',
      simulado: true,
    );
    addTearDown(traductor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TraductorScope(
          notifier: traductor,
          child: Scaffold(
            body: BiografiaTraducida(texto: ingles),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Chainsmokers'), findsOneWidget);
  });

  test('Temas en inglés no cae en Topics', () {
    expect(traduccionUiFijada('en', 'Temas'), 'Themes');
    expect(traduccionUiFijada('en', 'Tema'), 'Theme');
  });

  test('biografia en simulado elige la mejor candidata por locale', () async {
    const ingles = 'Known for platinum singles and festival sets.';
    const espanol = 'Conocido por sus sencillos de platino y sus actuaciones.';
    final traductor = Traductor(
      localeEfectivo: () => 'es_ES',
      simulado: true,
    );
    addTearDown(traductor.dispose);

    final bio = await traductor.biografia(
      ingles,
      alternativas: [ingles, espanol],
    );
    expect(bio, espanol);
  });

  test('claveBiografia es estable y descarta claves antiguas por hashCode', () async {
    final claveA = Traductor.claveBiografia('es', 'Texto de biografía');
    final claveB = Traductor.claveBiografia('es', 'Texto de biografía');
    expect(claveA, claveB);
    expect(claveA, matches(RegExp(r'^bio\|es\|[0-9a-f]{16}$')));

    final dir = Directory.systemTemp.createTempSync('neofy_traductor_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fichero = File(p.join(dir.path, 'traducciones.json'));
    fichero.writeAsStringSync(jsonEncode({
      'bio|es|123456789': 'obsoleta',
      'ui|en|Ajustes': 'Settings',
    }));

    final traductor = Traductor(
      localeEfectivo: () => 'en_US',
      directorio: dir,
    );
    addTearDown(traductor.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(traductor.cacheUi('Ajustes'), 'Settings');
  });
}
