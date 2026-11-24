import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/resource_monitor.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/updater.dart';
import 'package:neofy/ui/settings_dialog.dart';

class _ConfigDePrueba extends AppConfig {
  _ConfigDePrueba({super.canalActualizacion});

  @override
  Future<void> save() async {}
}

Future<void> _sinAccion() async {}

void main() {
  testWidgets(
    'PanelAjustes permite alternar entre Estable y Preview en diálogo y página',
    (t) async {
      addTearDown(() => modoPreview.value = kEsCompilacionPreview);
      final config = _ConfigDePrueba(
        canalActualizacion: CanalActualizacion.estable,
      );
      final settings = Settings(config);
      final ram = ResourceMonitor(pidsDeSidecars: () => const []);
      final cliente = MockClient((_) async => http.Response('', 404));
      final updater = Updater(
        cliente: cliente,
        instalaSolo: true,
        canalInicial: CanalActualizacion.estable,
        versionActual: '1.6.0',
      );
      final cambios = <CanalActualizacion>[];
      settings.onCambioCanalActualizacion = (canal) {
        cambios.add(canal);
        updater.cambiarCanal(canal);
      };
      addTearDown(() {
        settings.dispose();
        ram.dispose();
        updater.dispose();
      });

      Widget envolver(Widget hijo) => MaterialApp(
        home: Scaffold(body: Center(child: hijo)),
      );

      await t.pumpWidget(
        envolver(
          PanelAjustes(
            monitor: ram,
            settings: settings,
            updater: updater,
            onSalirParaActualizar: _sinAccion,
            trackUri: null,
            apariencia: const [],
            audio: const [],
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Estable'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('NeoFy 1.6.0'), findsOneWidget);

      await t.ensureVisible(find.text('Preview'));
      await t.tap(find.text('Preview'));
      await t.pumpAndSettle();

      expect(settings.canalActualizacion, CanalActualizacion.preview);
      expect(settings.enModoPreview, isTrue);
      expect(modoPreview.value, isTrue);
      expect(cambios, [CanalActualizacion.preview]);
      expect(find.text('NeoFy (PREVIEW) 1.6.0'), findsOneWidget);

      await t.pumpWidget(
        envolver(
          PanelAjustes(
            monitor: ram,
            settings: settings,
            updater: updater,
            onSalirParaActualizar: _sinAccion,
            trackUri: null,
            apariencia: const [],
            audio: const [],
            enPagina: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('NeoFy (PREVIEW) 1.6.0'), findsOneWidget);

      await t.ensureVisible(find.text('Estable'));
      await t.tap(find.text('Estable'));
      await t.pumpAndSettle();

      expect(settings.canalActualizacion, CanalActualizacion.estable);
      expect(settings.enModoPreview, isFalse);
      expect(modoPreview.value, isFalse);
      expect(cambios, [CanalActualizacion.preview, CanalActualizacion.estable]);
      expect(find.text('NeoFy 1.6.0'), findsOneWidget);
    },
  );

  testWidgets(
    'volver a Estable desde una compilación Preview muestra botón Instalar',
    (t) async {
      addTearDown(() => modoPreview.value = kEsCompilacionPreview);
      const pkgEstable =
          'https://git.neogex.xyz/api/v4/projects/10/packages/generic/neofy/1.6.0/NeoFy-1.6.0-windows-x64.exe';
      final config = _ConfigDePrueba(
        canalActualizacion: CanalActualizacion.preview,
      );
      final settings = Settings(config);
      final ram = ResourceMonitor(pidsDeSidecars: () => const []);
      final cliente = MockClient((request) async {
        if (request.url == Updater.uriUltimaRelease) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.6.0',
              'description': 'Estable 1.6.0',
              'assets': {
                'links': [
                  {'name': 'Instalador Windows x64 (.exe)', 'url': pkgEstable},
                ],
              },
            }),
            200,
          );
        }
        return http.Response('', 404);
      });
      final updater = Updater(
        cliente: cliente,
        instalaSolo: true,
        canalInicial: CanalActualizacion.preview,
        versionActual: '1.6.0.105',
      );
      settings.onCambioCanalActualizacion = (canal) {
        updater.cambiarCanal(canal);
      };
      addTearDown(() {
        settings.dispose();
        ram.dispose();
        updater.dispose();
      });

      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PanelAjustes(
              monitor: ram,
              settings: settings,
              updater: updater,
              onSalirParaActualizar: _sinAccion,
              trackUri: null,
              apariencia: const [],
              audio: const [],
              enPagina: true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      await t.ensureVisible(find.text('Estable'));
      await t.tap(find.text('Estable'));
      await t.pumpAndSettle();

      expect(updater.esCambioAEstable, isTrue);
      expect(find.text('Versión estable disponible: 1.6.0'), findsOneWidget);
      expect(find.text('Instalar'), findsOneWidget);
    },
  );
}
