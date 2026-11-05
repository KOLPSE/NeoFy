import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/neoreport.dart';

void main() {
  const key = 'nr_neofy_test_only';
  Future<Map<String, String>> installation() async => {
    'installId': 'installation-test',
    'installationCredential': 'credential-test',
  };

  test(
    'envía los datos y la pista en meta y devuelve el enlace de Discord',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/ingest');
        expect(request.headers['Authorization'], 'Bearer $key');
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['installId'], 'installation-test');
        expect(payload.containsKey('trackUri'), isFalse);
        expect(
          payload['meta']['trackUri'],
          'https://open.spotify.com/track/abc123',
        );
        expect(payload['title'], 'Error');
        return http.Response(
          jsonEncode({
            'linkUrl': 'https://report.neogex.xyz/reports/1',
            'linkCodeUrl': 'https://report.neogex.xyz/link?code=CODE',
          }),
          201,
        );
      });
      final report = NeoReport(
        cliente: client,
        clave: key,
        obtenerInstalacion: installation,
      );
      final uri = await report.enviar(
        title: ' Error ',
        body: 'detalle',
        category: 'bug',
        trackUri: 'spotify:track:abc123',
      );
      expect(uri.path, '/link');
    },
  );

  test(
    'conserva la clave idempotente al reintentar tras un fallo de red',
    () async {
      String? firstKey;
      var count = 0;
      final client = MockClient((request) async {
        count++;
        if (count == 1) {
          firstKey = request.headers['Idempotency-Key'];
          throw http.ClientException('sin conexión');
        }
        expect(request.headers['Idempotency-Key'], firstKey);
        return http.Response(
          jsonEncode({'linkUrl': 'https://report.neogex.xyz/reports/1'}),
          201,
        );
      });
      final report = NeoReport(
        cliente: client,
        clave: key,
        obtenerInstalacion: installation,
      );
      Future<Uri> send() => report.enviar(
        title: 'Error',
        body: 'detalle',
        category: 'bug',
        trackUri: null,
      );
      await expectLater(send(), throwsA(isA<http.ClientException>()));
      expect((await send()).path, '/reports/1');
    },
  );
}
