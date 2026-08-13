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

    test('large_image es la carátula real de la pista, como en Spotify', () {
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
}

class _FakeTransport implements DiscordTransport {
  bool _conectado = false;
  int envios = 0;

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
    return true;
  }

  @override
  Future<void> desconectar() async {
    _conectado = false;
  }
}
