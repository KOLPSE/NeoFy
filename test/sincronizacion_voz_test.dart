import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/detector_voz.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/sincronizacion_voz.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/ui/letra_sincronizada.dart';
import 'package:neofy/ui/lyrics_view.dart';

class _FuenteVozFalsa implements FuenteDeteccionVoz {
  final _estado = ValueNotifier(const EstadoVoz(disponible: true));
  bool iniciada = false;

  @override
  ValueListenable<EstadoVoz> get estado => _estado;

  @override
  bool get disponible => true;

  @override
  Future<void> iniciar() async {
    iniciada = true;
  }

  @override
  Future<void> detener() async {
    iniciada = false;
  }

  @override
  void dispose() {
    _estado.dispose();
  }
}

class _ConfigFalsa extends AppConfig {
  int guardados = 0;

  @override
  Future<void> save() async => guardados++;
}

class _AuthFalsa extends SpotifyAuth {
  _AuthFalsa(super.config);

  @override
  Future<String> accessToken() async => 'token';
}

List<double> _seno(double freqHz, double amplitud, int muestras, int sr) => [
  for (var i = 0; i < muestras; i++)
    amplitud * math.sin(2 * math.pi * freqHz * i / sr),
];

void main() {
  group('AnalizadorVozPcm', () {
    test('detecta voz en banda vocal y descarta silencio o subgraves puros', () {
      const sr = 48000;
      const frame = 960; // 20 ms
      final analizador = AnalizadorVozPcm(
        sampleRate: sr,
        confirmacionMs: 60,
        retencionMs: 120,
      );

      final silencio = List<double>.filled(frame, 0);
      for (var i = 0; i < 5; i++) {
        expect(analizador.analizarMono(silencio).hayVoz, isFalse);
      }

      // Solo subgraves (65 Hz) no debe activar detección de voz.
      final subgrave = _seno(65, 0.35, frame, sr);
      for (var i = 0; i < 6; i++) {
        expect(analizador.analizarMono(subgrave).hayVoz, isFalse);
      }

      // Banda vocal (850 Hz) tras confirmación temporal sí activa voz.
      final vocal = _seno(850, 0.12, frame, sr);
      var detectada = false;
      for (var i = 0; i < 5; i++) {
        detectada = analizador.analizarMono(vocal).hayVoz;
      }
      expect(detectada, isTrue);

      // Tras retención de silencio vuelve a false.
      var estadoFinal = true;
      for (var i = 0; i < 10; i++) {
        estadoFinal = analizador.analizarMono(silencio).hayVoz;
      }
      expect(estadoFinal, isFalse);
    });

    test('descarta ruido de percusión e instrumental estéreo panoramizado', () {
      const sr = 48000;
      const frame = 960; // 20 ms
      final analizador = AnalizadorVozPcm(
        sampleRate: sr,
        confirmacionMs: 60,
        retencionMs: 120,
      );

      // Ruido blanco / platillos / caja no debe activar detección de voz.
      final rng = math.Random(42);
      for (var f = 0; f < 10; f++) {
        final ruido = [for (var i = 0; i < frame; i++) (rng.nextDouble() * 2 - 1) * 0.25];
        expect(analizador.analizarMono(ruido).hayVoz, isFalse);
      }

      // Instrumental estéreo (guitarras/sintes panoramizados en L y R) sin voz
      // centrada tampoco debe disparar falsos positivos.
      for (var f = 0; f < 12; f++) {
        final mid = List<double>.filled(frame, 0);
        final side = List<double>.filled(frame, 0);
        for (var i = 0; i < frame; i++) {
          final t = (f * frame + i) / sr;
          final izq = 0.22 * math.sin(2 * math.pi * 440 * t) +
              0.18 * math.sin(2 * math.pi * 660 * t);
          final der = 0.22 * math.sin(2 * math.pi * 554 * t) +
              0.18 * math.sin(2 * math.pi * 880 * t);
          mid[i] = (izq + der) * 0.5;
          side[i] = (izq - der) * 0.5;
        }
        expect(analizador.analizarEstereo(mid, side).hayVoz, isFalse);
      }

      // Al entrar una voz centrada (misma fase en L y R) sobre el mismo
      // instrumental estéreo, sí debe activarse.
      var detectada = false;
      for (var f = 0; f < 8; f++) {
        final mid = List<double>.filled(frame, 0);
        final side = List<double>.filled(frame, 0);
        for (var i = 0; i < frame; i++) {
          final t = (f * frame + i) / sr;
          final voz = 0.28 * math.sin(2 * math.pi * 320 * t) +
              0.14 * math.sin(2 * math.pi * 640 * t);
          final izq = voz + 0.08 * math.sin(2 * math.pi * 440 * t);
          final der = voz + 0.08 * math.sin(2 * math.pi * 554 * t);
          mid[i] = (izq + der) * 0.5;
          side[i] = (izq - der) * 0.5;
        }
        detectada = analizador.analizarEstereo(mid, side).hayVoz;
      }
      expect(detectada, isTrue);

      // Si el cantante se calla pero el instrumental estéreo sigue, vuelve a false.
      var sigue = true;
      for (var f = 0; f < 12; f++) {
        final mid = List<double>.filled(frame, 0);
        final side = List<double>.filled(frame, 0);
        for (var i = 0; i < frame; i++) {
          final t = (f * frame + i) / sr;
          final izq = 0.22 * math.sin(2 * math.pi * 440 * t);
          final der = 0.22 * math.sin(2 * math.pi * 554 * t);
          mid[i] = (izq + der) * 0.5;
          side[i] = (izq - der) * 0.5;
        }
        sigue = analizador.analizarEstereo(mid, side).hayVoz;
      }
      expect(sigue, isFalse);
    });
  });

  group('ControladorSincronizacionPorVoz', () {
    test('retiene el paso a la siguiente palabra si no se detecta voz', () {
      final lineas = LineaDeLetra.leer({
        'syncedLyrics': '[00:01.00]<00:01.00>Hola <00:02.00>mundo<00:03.00>',
      }, 6000);
      final ctrl = ControladorSincronizacionPorVoz(margenEsperaVozMs: 100);

      // Comienza cantando en t=1000 ms.
      final t1 = ctrl.actualizar(
        posicionBaseMs: 1000,
        reproduciendo: true,
        hayVoz: true,
        lineas: lineas,
        modo: ModoVisualizacionLetra.palabras,
      );
      expect(t1, 1000);

      // Se calla en 1800..2200: supera el margen y la frontera de "mundo" (2000) queda retenida.
      ctrl.actualizar(
        posicionBaseMs: 1850,
        reproduciendo: true,
        hayVoz: false,
        lineas: lineas,
        modo: ModoVisualizacionLetra.palabras,
      );
      final retenido = ctrl.actualizar(
        posicionBaseMs: 2250,
        reproduciendo: true,
        hayVoz: false,
        lineas: lineas,
        modo: ModoVisualizacionLetra.palabras,
      );
      expect(retenido, lessThanOrEqualTo(2000));
      expect(ctrl.desfaseAdaptativoMs, lessThan(0));

      // Al volver la voz, avanza hacia la siguiente palabra.
      final reanudado = ctrl.actualizar(
        posicionBaseMs: 2350,
        reproduciendo: true,
        hayVoz: true,
        lineas: lineas,
        modo: ModoVisualizacionLetra.palabras,
      );
      expect(reanudado, greaterThan(retenido));
    });

    test('adelanta el ritmo si detecta voz sostenida antes de la línea', () {
      final lineas = LineaDeLetra.leer({
        'syncedLyrics': '[00:03.00]Ya empieza',
      }, 8000);
      final ctrl = ControladorSincronizacionPorVoz(
        retardoAdelantoVozMs: 100,
        velocidadCorreccion: 0.5,
      );

      ctrl.actualizar(
        posicionBaseMs: 1500,
        reproduciendo: true,
        hayVoz: true,
        lineas: lineas,
        modo: ModoVisualizacionLetra.letras,
      );
      final adelantado = ctrl.actualizar(
        posicionBaseMs: 1650,
        reproduciendo: true,
        hayVoz: true,
        lineas: lineas,
        modo: ModoVisualizacionLetra.letras,
      );
      expect(adelantado, greaterThan(1650));
      expect(ctrl.desfaseAdaptativoMs, greaterThan(0));
    });
  });

  group('UI y configuración', () {
    testWidgets(
      'el panel de sincronización permite elegir palabras/letras y voz',
      (tester) async {
        final config = _ConfigFalsa();
        final player = PlayerController(SpotifyApi(_AuthFalsa(config)), config);
        final fuente = _FuenteVozFalsa();
        const track = Track(
          uri: 'spotify:track:test1',
          id: 'test1',
          name: 'Tema de prueba',
          artists: 'Artista',
          album: 'Álbum',
          durationMs: 120000,
          artMedium: null,
          artSmall: null,
          isLocal: false,
        );
        final cliente = MockClient((req) async {
          return http.Response(
            jsonEncode({
              'syncedLyrics':
                  '[00:01.00]<00:01.00>Hola <00:02.00>mundo<00:03.00>',
              'plainLyrics': 'Hola mundo',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LyricsView(
                track: track,
                player: player,
                onClose: () {},
                fuenteVoz: fuente,
                cliente: cliente,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Ajustar sincronización'));
        await tester.pumpAndSettle();

        expect(find.text('Sincronización de esta canción'), findsOneWidget);
        expect(find.text('Por letras'), findsOneWidget);
        expect(find.text('Por palabras'), findsOneWidget);
        expect(find.text('Sincronizar con voz'), findsOneWidget);

        await tester.tap(find.text('Por palabras'));
        await tester.pump();
        expect(config.modoLetraPorPalabras, isTrue);

        await tester.tap(find.byType(Switch));
        await tester.pump();
        expect(config.sincronizacionPorVoz, isTrue);
        expect(fuente.iniciada, isTrue);
        expect(find.text('Esperando voz'), findsOneWidget);

        fuente._estado.value = const EstadoVoz(hayVoz: true, nivelVoz: 0.7);
        await tester.pump();
        expect(find.text('Voz detectada'), findsOneWidget);

        player.dispose();
        fuente.dispose();
        cliente.close();
      },
    );

    if (Platform.isWindows) {
      test('CapturaVozWasapi inicia y detiene el loopback sin errores', () async {
        final captura = CapturaVozWasapi();
        await captura.iniciar();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await captura.detener();
        captura.dispose();
      });
    }
  });
}
