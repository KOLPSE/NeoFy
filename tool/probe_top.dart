// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';

Future<void> main() async {
  final f = File(p.join(appDataDir().path, 'tokens.json'));
  if (!f.existsSync()) {
    print('No hay sesión guardada.');
    exit(1);
  }
  final stored = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final config = await AppConfig.load();

  final res = await http.post(
    Uri.parse('https://accounts.spotify.com/api/token'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': stored['refresh_token'] as String,
      'client_id': config.clientId,
    },
  );
  if (res.statusCode != 200) {
    print('No se pudo renovar (${res.statusCode}): ${res.body}');
    exit(1);
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final token = body['access_token'] as String;

  final nuevo = body['refresh_token'] as String?;
  if (nuevo != null && nuevo != stored['refresh_token']) {
    stored['refresh_token'] = nuevo;
    stored['scope'] = body['scope'] ?? stored['scope'];
    f.writeAsStringSync(jsonEncode(stored));
    print('Refresh token rotado y guardado.');
  }
  print('Permisos: ${body['scope']}\n');

  Future<void> mirar(String etiqueta, String path, Map<String, String> q) async {
    final uri = Uri.https('api.spotify.com', '/v1$path', q);
    final r = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    final ra = r.headers['retry-after'];
    var resumen = '';
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final items = (j['items'] as List<dynamic>?) ?? const [];
      resumen = '${items.length} elementos';
      if (items.isNotEmpty) {
        final primero = items.first as Map<String, dynamic>;
        final t = (primero['track'] ?? primero['item'] ?? primero)
            as Map<String, dynamic>;
        resumen += '  (p.ej. "${t['name']}")';
      }
    } else {
      resumen = r.body.replaceAll(RegExp(r'\s+'), ' ');
      if (ra != null) resumen += '  [Retry-After: $ra s]';
    }
    print('$etiqueta → HTTP ${r.statusCode}  $resumen');
  }

  await mirar('recently-played', '/me/player/recently-played', {'limit': '20'});
  await mirar('top/tracks    ', '/me/top/tracks', {'limit': '20', 'time_range': 'short_term'});
  await mirar('top/artists   ', '/me/top/artists', {'limit': '20', 'time_range': 'short_term'});
  exit(0);
}
