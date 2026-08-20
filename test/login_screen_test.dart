import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/yt_auth.dart';
import 'package:neofy/ui/login_screen.dart';

class _ConfigDeMentira extends AppConfig {
  _ConfigDeMentira({super.clientId});

  int guardados = 0;

  @override
  Future<void> save() async => guardados++;
}

const _idValido = '0123456789abcdef0123456789abcdef';

void main() {
  Future<_ConfigDeMentira> montar(WidgetTester tester, {String clientId = ''}) async {
    final config = _ConfigDeMentira(clientId: clientId);
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        auth: SpotifyAuth(config),
        config: config,
        onLoggedIn: () async {},
        ytAuth: YtAuth(),
      ),
    ));
    return config;
  }

  testWidgets('sin Client ID salen los pasos y no se puede entrar todavía',
      (tester) async {
    await montar(tester);

    expect(find.text('Abrir el panel'), findsOneWidget);
    expect(find.text('http://127.0.0.1:$kRedirectPort/callback'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Iniciar sesión con Spotify'),
    );
    expect(boton.onPressed, isNull);
  });

  testWidgets('al desloguearse con Client ID guardado se puede volver a los pasos',
      (tester) async {
    await montar(tester, clientId: _idValido);

    expect(find.textContaining('Client ID guardado'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Iniciar sesión con Spotify'),
    );
    expect(boton.onPressed, isNotNull);

    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Abrir el panel'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      _idValido,
    );
  });

  testWidgets('un Client ID a medias no se guarda y lo dice', (tester) async {
    final config = await montar(tester);

    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.ensureVisible(find.text('Guardar y continuar'));
    await tester.tap(find.text('Guardar y continuar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('32 caracteres hexadecimales'), findsOneWidget);
    expect(config.guardados, 0);
    expect(config.clientId, '');
  });

  testWidgets('uno bueno se guarda y deja pasar al login', (tester) async {
    final config = await montar(tester);

    await tester.enterText(find.byType(TextField), '  $_idValido  ');
    await tester.ensureVisible(find.text('Guardar y continuar'));
    await tester.tap(find.text('Guardar y continuar'));
    await tester.pumpAndSettle();

    expect(config.clientId, _idValido);
    expect(config.guardados, 1);
    expect(find.textContaining('Client ID guardado'), findsOneWidget);

    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Iniciar sesión con Spotify'),
    );
    expect(boton.onPressed, isNotNull);
  });

  testWidgets('se puede olvidar el guardado para enlazar otra app', (tester) async {
    final config = await montar(tester, clientId: _idValido);

    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Olvidar el Client ID guardado'));
    await tester.tap(find.text('Olvidar el Client ID guardado'));
    await tester.pumpAndSettle();

    expect(config.clientId, '');
    expect(config.guardados, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '');
    expect(find.textContaining('Client ID guardado'), findsNothing);
  });

  test('el resumen del Client ID no lo enseña entero', () {
    expect(resumenDeClientId(_idValido), '012345…cdef');
    expect(resumenDeClientId('corto'), 'corto');
  });
}
