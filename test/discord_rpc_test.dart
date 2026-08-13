import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/discord_rpc.dart';
import 'package:neofy/core/models.dart';

Track _track({
  String id = '4cOdK2wGLETKBW3PvgPWqT',
  String name = 'Never Gonna Give You Up',
  String artists = 'Rick Astley',
  String album = 'Whenever You Need Somebody',
  String? artSmall = 'https://i.scdn.co/image/pequena',
  String? artMedium = 'https://i.scdn.co/image/mediana',
  int durationMs = 213573,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: name,
      artists: artists,
      album: album,
      artSmall: artSmall,
      artMedium: artMedium,
      durationMs: durationMs,
      isLocal: false,
    );

void main() {
  group('DiscordRpc.construirActividad', () {
    test('con pista y siguiente pista: details es el nombre, state lleva el artista y "Siguiente: …"', () {
      final pistaActual = _track(name: 'Bohemian Rhapsody', artists: 'Queen');
      final siguientePista = _track(name: 'Don\'t Stop Me Now', artists: 'Queen');

      final actividad = DiscordRpc.construirActividad(
        track: pistaActual,
        siguiente: siguientePista,
        sonando: true,
        progresoMs: 30000,
      );

      expect(actividad['details'], 'Bohemian Rhapsody');
      expect(actividad['state'], 'Queen · Siguiente: Don\'t Stop Me Now');
    });

    test('sin siguiente pista todavía: state solo lleva el artista, sin "Siguiente:"', () {
      final pistaActual = _track(name: 'Billie Jean', artists: 'Michael Jackson');

      final actividad = DiscordRpc.construirActividad(
        track: pistaActual,
        siguiente: null,
        sonando: true,
        progresoMs: 15000,
      );

      expect(actividad['details'], 'Billie Jean');
      expect(actividad['state'], 'Michael Jackson');
      expect(actividad['state'], isNot(contains('Siguiente:')));
    });

    test('el botón de GitHub siempre está presente con la URL correcta', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: true,
        progresoMs: 0,
      );

      final buttons = actividad['buttons'] as List<dynamic>;
      expect(buttons, isNotEmpty);
      expect(buttons.first['label'], 'GitHub');
      expect(buttons.first['url'], 'https://github.com/KOLPSE/NeoFy');
    });

    test('timestamps.start es coherente con el progreso pasado', () {
      final ahora = DateTime.now();
      const progresoMs = 45000;

      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: true,
        progresoMs: progresoMs,
        ahora: ahora,
      );

      final timestamps = actividad['timestamps'] as Map<String, dynamic>?;
      expect(timestamps, isNotNull);
      final start = timestamps!['start'] as int;
      expect(start, ahora.millisecondsSinceEpoch - progresoMs);
      expect(start, lessThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('timestamps.end es start + duración, para que salga la barra de progreso', () {
      final ahora = DateTime.now();
      const progresoMs = 45000;
      const duracionMs = 213573;

      final actividad = DiscordRpc.construirActividad(
        track: _track(durationMs: duracionMs),
        siguiente: null,
        sonando: true,
        progresoMs: progresoMs,
        ahora: ahora,
      );

      final timestamps = actividad['timestamps'] as Map<String, dynamic>?;
      expect(timestamps, isNotNull);
      final start = timestamps!['start'] as int;
      final end = timestamps['end'] as int;
      expect(end, start + duracionMs);
    });

    test('cuando está en pausa, no incluye timestamps para no avanzar el tiempo', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: false,
        progresoMs: 45000,
      );

      expect(actividad['timestamps'], isNull);
    });

    test('large_image es la carátula real de la pista cuando está sonando', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(album: 'Whenever You Need Somebody'),
        siguiente: null,
        sonando: true,
        progresoMs: 0,
      );

      final assets = actividad['assets'] as Map<String, dynamic>;
      expect(assets['large_image'], 'https://i.scdn.co/image/mediana');
      expect(assets['large_text'], 'Whenever You Need Somebody');
    });

    test('al pausar, large_image es el logo de NeoFy aunque la pista tenga carátula', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(artMedium: 'https://i.scdn.co/image/mediana'),
        siguiente: null,
        sonando: false,
        progresoMs: 45000,
      );

      final assets = actividad['assets'] as Map<String, dynamic>;
      expect(assets['large_image'], 'logo');
    });

    test('sin carátula (tema local), large_image se cae al logo subido', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(artSmall: null, artMedium: null),
        siguiente: null,
        sonando: true,
        progresoMs: 0,
      );

      final assets = actividad['assets'] as Map<String, dynamic>;
      expect(assets['large_image'], 'logo');
    });

    test('small_image es siempre el logo de NeoFy, la esquina no depende de la carátula', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: true,
        progresoMs: 0,
      );

      final assets = actividad['assets'] as Map<String, dynamic>;
      expect(assets['small_image'], 'logo');
      expect(assets['small_text'], 'NeoFy');
    });

    test('tipo de actividad 2 (Escuchando), no 0 (Jugando)', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: true,
        progresoMs: 0,
      );

      expect(actividad['type'], 2);
    });
  });

  group('DiscordRpc.construirPayloadSetActivity', () {
    test('construye estructura válida para SET_ACTIVITY con actividad', () {
      final payload = DiscordRpc.construirPayloadSetActivity(
        pid: 1234,
        nonce: 'nonce-1',
        activity: {'details': 'Test'},
      );

      expect(payload['cmd'], 'SET_ACTIVITY');
      expect(payload['nonce'], 'nonce-1');
      expect(payload['args'], {
        'pid': 1234,
        'activity': {'details': 'Test'},
      });
    });

    test('permite activity null para limpiar la presencia', () {
      final payload = DiscordRpc.construirPayloadSetActivity(
        pid: 1234,
        nonce: 'nonce-2',
        activity: null,
      );

      expect(payload['cmd'], 'SET_ACTIVITY');
      expect(payload['nonce'], 'nonce-2');
      expect(payload['args'], {
        'pid': 1234,
        'activity': null,
      });
    });
  });

  group('DiscordRpc.empaquetar', () {
    test('empaqueta opcode y longitud little endian con payload UTF-8', () {
      const jsonStr = '{"v":1}';
      final bytes = DiscordRpc.empaquetar(0, jsonStr);

      expect(bytes.length, 8 + utf8.encode(jsonStr).length);

      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, Endian.little), 0); // Opcode HANDSHAKE
      expect(data.getUint32(4, Endian.little), utf8.encode(jsonStr).length);

      final payloadDecoded = utf8.decode(bytes.sublist(8));
      expect(payloadDecoded, jsonStr);
    });
  });

  group('DiscordRpc: no reenviar por deriva de posición', () {
    test('la misma pista no reenvía aunque cambie el progreso; una pista nueva sí', () async {
      final transporte = _FakeTransport();
      final rpc = DiscordRpc(transporte: transporte);
      Future<List<Track>> colaVacia() async => const [];

      rpc.start('123456');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pista = _track();
      rpc.actualizarActividad(
          track: pista, sonando: true, progresoMs: 1000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      final tras1a = transporte.envios;
      expect(tras1a, greaterThan(0));

      // Misma pista, solo se desvía el progreso: antes esto reenviaba y se
      // comía la ventana de 15 s de Discord justo cuando hacía falta de
      // verdad. Ahora no debe mandar nada.
      rpc.actualizarActividad(
          track: pista, sonando: true, progresoMs: 9000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, tras1a);

      // Cambio de pista de verdad: sí tiene que mandar, sin esperar a nada.
      final otraPista = _track(id: 'otra-cancion', name: 'Otra canción');
      rpc.actualizarActividad(
          track: otraPista, sonando: true, progresoMs: 0, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, greaterThan(tras1a));

      await rpc.stop();
    });
  });

  group('DiscordRpc: timeout y comportamiento en pausa', () {
    test('al pausar, se limpia la presencia tras el timeout de pausa', () async {
      final transporte = _FakeTransport();
      final rpc = DiscordRpc(
        transporte: transporte,
        timeoutPausa: const Duration(milliseconds: 30),
      );
      Future<List<Track>> colaVacia() async => const [];

      rpc.start('123456');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pista = _track();
      // Empieza reproduciendo
      rpc.actualizarActividad(
          track: pista, sonando: true, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      // Se pausa la reproducción
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 2);

      // Comprobar que en pausa mandó large_image: logo
      final payloadPausa = jsonDecode(transporte.payloads.last) as Map<String, dynamic>;
      final activityPausa = (payloadPausa['args'] as Map<String, dynamic>)['activity'] as Map<String, dynamic>;
      expect((activityPausa['assets'] as Map<String, dynamic>)['large_image'], 'logo');

      // Aún no ha pasado el timeout (30 ms)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transporte.envios, 2);

      // Se cumple el timeout: se apaga enviando activity: null
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(transporte.envios, 3);
      final payloadLimpio = jsonDecode(transporte.payloads.last) as Map<String, dynamic>;
      expect((payloadLimpio['args'] as Map<String, dynamic>)['activity'], isNull);

      await rpc.stop();
    });

    test('si vuelve a sonar antes del timeout de pausa, el temporizador se cancela', () async {
      final transporte = _FakeTransport();
      final rpc = DiscordRpc(
        transporte: transporte,
        timeoutPausa: const Duration(milliseconds: 40),
      );
      Future<List<Track>> colaVacia() async => const [];

      rpc.start('123456');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pista = _track();
      rpc.actualizarActividad(
          track: pista, sonando: true, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      // Se pausa
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 2);

      // Antes del timeout (40 ms), se reanuda a los 15 ms
      await Future<void>.delayed(const Duration(milliseconds: 15));
      rpc.actualizarActividad(
          track: pista, sonando: true, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 3);

      // Esperamos otros 50 ms (más de los 40 ms de la pausa inicial): NO debe apagarse
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transporte.envios, 3);
      final payloadActual = jsonDecode(transporte.payloads.last) as Map<String, dynamic>;
      expect((payloadActual['args'] as Map<String, dynamic>)['activity'], isNotNull);

      await rpc.stop();
    });

    test('actualizaciones intermedias durante la pausa no reinician el temporizador', () async {
      final transporte = _FakeTransport();
      final rpc = DiscordRpc(
        transporte: transporte,
        timeoutPausa: const Duration(milliseconds: 50),
      );
      Future<List<Track>> colaVacia() async => const [];

      rpc.start('123456');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pista = _track();
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      // A los 20 ms y 35 ms llegan actualizaciones de sondeo mientras sigue en pausa
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      await Future<void>.delayed(const Duration(milliseconds: 15));
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      // A los 55 ms totales desde la primera pausa (20 ms más tarde), debe haberse apagado
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(transporte.envios, 2);
      final payloadLimpio = jsonDecode(transporte.payloads.last) as Map<String, dynamic>;
      expect((payloadLimpio['args'] as Map<String, dynamic>)['activity'], isNull);

      await rpc.stop();
    });

    test('cuando track pasa a null, se cancela el timer de pausa y se limpia', () async {
      final transporte = _FakeTransport();
      final rpc = DiscordRpc(
        transporte: transporte,
        timeoutPausa: const Duration(milliseconds: 40),
      );
      Future<List<Track>> colaVacia() async => const [];

      rpc.start('123456');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pista = _track();
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      // Track pasa a null de inmediato
      rpc.actualizarActividad(
          track: null, sonando: false, progresoMs: 0, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 2);
      final payloadLimpio = jsonDecode(transporte.payloads.last) as Map<String, dynamic>;
      expect((payloadLimpio['args'] as Map<String, dynamic>)['activity'], isNull);

      // Esperar más allá del timeout para asegurar que ningún timer residual intente hacer nada
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(transporte.envios, 2);

      await rpc.stop();
    });

    test('stop() cancela el timer de pausa y no envía nada tras expirar', () async {
      final transporte = _FakeTransport();
      final rpc = DiscordRpc(
        transporte: transporte,
        timeoutPausa: const Duration(milliseconds: 40),
      );
      Future<List<Track>> colaVacia() async => const [];

      rpc.start('123456');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pista = _track();
      rpc.actualizarActividad(
          track: pista, sonando: false, progresoMs: 10000, obtenerCola: colaVacia);
      await Future<void>.delayed(Duration.zero);
      expect(transporte.envios, 1);

      // Se detiene el RPC
      await rpc.stop();
      final enviosTrasStop = transporte.envios;

      // Esperar a que pase el timeout: no debe haber más envíos
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(transporte.envios, enviosTrasStop);
    });
  });
}

class _FakeTransport implements DiscordTransport {
  bool _conectado = false;
  int envios = 0;
  final List<String> payloads = [];

  @override
  bool get conectado => _conectado;

  @override
  Future<bool> conectar(String clientId) async {
    _conectado = true;
    return true;
  }

  @override
  Future<bool> enviar(int opcode, String jsonStr) async {
    envios++;
    payloads.add(jsonStr);
    return true;
  }

  @override
  Future<void> desconectar() async {
    _conectado = false;
  }
}
