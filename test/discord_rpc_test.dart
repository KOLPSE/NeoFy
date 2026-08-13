import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/discord_rpc.dart';
import 'package:neofy/core/models.dart';

Track _track({
  String id = '4cOdK2wGLETKBW3PvgPWqT',
  String name = 'Never Gonna Give You Up',
  String artists = 'Rick Astley',
  int durationMs = 213573,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: name,
      artists: artists,
      album: 'Whenever You Need Somebody',
      artSmall: 'https://i.scdn.co/image/pequena',
      artMedium: 'https://i.scdn.co/image/mediana',
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

    test('cuando está en pausa, no incluye timestamps para no avanzar el tiempo', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: false,
        progresoMs: 45000,
      );

      expect(actividad['timestamps'], isNull);
    });

    test('assets incluye logo de NeoFy', () {
      final actividad = DiscordRpc.construirActividad(
        track: _track(),
        siguiente: null,
        sonando: true,
        progresoMs: 0,
      );

      final assets = actividad['assets'] as Map<String, dynamic>;
      expect(assets['large_image'], 'logo');
      expect(assets['large_text'], 'NeoFy');
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
}
