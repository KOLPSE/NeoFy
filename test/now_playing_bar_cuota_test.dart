import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/now_playing_bar.dart';
import 'package:neofy/ui/onda_de_progreso.dart';

const _aviso =
    'Spotify ha agotado la cuota de buscar y navegar '
    '(la reproducción sigue funcionando). Vuelve sobre las 15:48 '
    '(en 19 h 7 min). Es el límite del Modo Desarrollo y se recupera solo.';

class _ConfiguracionFalsa extends AppConfig {
  _ConfiguracionFalsa() : super(initialVolume: 60);

  @override
  Future<void> save() async {}
}

class _ApiConCuota extends SpotifyApi {
  _ApiConCuota() : super(SpotifyAuth(AppConfig()));

  String? cuota = _aviso;

  @override
  String? get avisoDeCuota => cuota;
}

void main() {
  testWidgets(
    'Nocturno centra el progreso bajo el transporte en ventana mínima',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(820, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final config = _ConfiguracionFalsa();
      final player = PlayerController(_ApiConCuota()..cuota = null, config)
        ..premiumChecked = true
        ..isPremium = true
        ..ourDeviceId = 'dev';
      addTearDown(player.dispose);
      final barra = NowPlayingBar(
        player: player,
        librespot: LibrespotManager(config),
      );

      Future<void> mostrar(Tema tema) => tester.pumpWidget(
        MaterialApp(
          theme: construirThemeData(tema),
          home: Scaffold(bottomNavigationBar: barra),
        ),
      );

      final progreso = find.byType(BarraDeProgreso);
      await mostrar(temaNeoFyNocturno);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(progreso).width, greaterThan(240));
      final reproducir = tester.getCenter(find.byTooltip('Reproducir'));
      expect(tester.getCenter(progreso).dx, closeTo(reproducir.dx, 12));
      expect(tester.getCenter(progreso).dy, greaterThan(reproducir.dy));
    },
  );

  testWidgets('el aviso de cuota se puede ignorar con la X', (tester) async {
    final api = _ApiConCuota();
    final config = _ConfiguracionFalsa();
    final player = PlayerController(api, config)
      ..premiumChecked = true
      ..isPremium = true
      ..ourDeviceId = 'dev'
      ..lastError = _aviso;
    addTearDown(player.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NowPlayingBar(
          player: player,
          librespot: LibrespotManager(config),
        ),
      ),
    ));

    expect(find.textContaining('agotado la cuota'), findsOneWidget);
    expect(find.byTooltip('Ignorar'), findsOneWidget);

    await tester.tap(find.byTooltip('Ignorar'));
    await tester.pump();

    expect(find.textContaining('agotado la cuota'), findsNothing);
    expect(find.byTooltip('Ignorar'), findsNothing);
  });

  testWidgets('otros avisos no llevan botón de ignorar', (tester) async {
    final api = _ApiConCuota()..cuota = null;
    final config = _ConfiguracionFalsa();
    final player = PlayerController(api, config)
      ..premiumChecked = true
      ..isPremium = true
      ..ourDeviceId = 'dev'
      ..lastError = 'El reproductor no contestó.';
    addTearDown(player.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NowPlayingBar(
          player: player,
          librespot: LibrespotManager(config),
        ),
      ),
    ));

    expect(find.text('El reproductor no contestó.'), findsOneWidget);
    expect(find.byTooltip('Ignorar'), findsNothing);
  });
}
