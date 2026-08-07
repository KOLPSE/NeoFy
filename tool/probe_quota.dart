// ¿Hasta dónde llega el 429 de cuota? ¿Solo a unos endpoints o a todo?
//
//   dart run tool/probe_quota.dart      (con la app CERRADA)
//
// Hace las **mínimas** peticiones posibles: cada una de más cuenta para
// mantener viva la penalización. Guarda el refresh token rotado, como todas las
// sondas de esta carpeta.
//
// ignore_for_file: avoid_print  — es una herramienta de diagnóstico.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';

Future<void> main() async {
  final f = File(p.join(appDataDir().path, 'tokens.json'));
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
    f.writeAsStringSync(jsonEncode(stored));
  }
  print('Client ID en uso: ${config.clientId}\n');

  Future<void> mirar(String etiqueta, String path) async {
    final r = await http.get(Uri.https('api.spotify.com', '/v1$path'),
        headers: {'Authorization': 'Bearer $token'});
    final ra = r.headers['retry-after'];
    final cuerpo = r.body.isEmpty
        ? '(vacío)'
        : r.body.substring(0, r.body.length > 90 ? 90 : r.body.length)
            .replaceAll(RegExp(r'\s+'), ' ');
    print('$etiqueta → ${r.statusCode}${ra == null ? "" : "  [Retry-After: $ra s]"}  $cuerpo');
  }

  // Los cuatro que hacen falta para que la app sea usable.
  await mirar('GET /me                 ', '/me');
  await mirar('GET /me/player          ', '/me/player');
  await mirar('GET /me/player/devices  ', '/me/player/devices');
  await mirar('GET /me/playlists?50    ', '/me/playlists?limit=50');
  await mirar('GET /me/tracks?limit=1  ', '/me/tracks?limit=1');
  await mirar('GET /search             ', '/search?q=daft%20punk&type=track&limit=3');
  await mirar('GET /me/player/queue    ', '/me/player/queue');
  exit(0);
}
