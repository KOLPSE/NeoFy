// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';

Future<void> main() async {
  final f = File(p.join(appDataDir().path, 'tokens.json'));
  if (!f.existsSync()) {
    print('No hay sesión guardada en ${appDataDir().path}. Inicia sesión en la app.');
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
    print('No se pudo renovar el token (${res.statusCode}): ${res.body}');
    exit(1);
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final token = body['access_token'] as String;
  print('Permisos de la sesión: ${body['scope']}');

  Future<http.Response> req(String method, String path, Map<String, String>? q,
      [Object? cuerpo]) {
    final uri = Uri.https('api.spotify.com', '/v1$path', q);
    final r = http.Request(method, uri)..headers['Authorization'] = 'Bearer $token';
    if (cuerpo != null) {
      r.headers['Content-Type'] = 'application/json';
      r.body = jsonEncode(cuerpo);
    }
    return http.Client().send(r).then(http.Response.fromStream);
  }

  void informe(String etiqueta, http.Response r) {
    final cuerpo = r.body.length > 160 ? '${r.body.substring(0, 160)}…' : r.body;
    print('    $etiqueta → HTTP ${r.statusCode}  ${cuerpo.replaceAll(RegExp(r'\s+'), ' ')}');
  }

  print('\n[1] Una canción guardada, para tener un id real con el que probar');
  final saved = await req('GET', '/me/tracks', {'limit': '1'});
  if (saved.statusCode != 200) {
    informe('GET /me/tracks', saved);
    exit(1);
  }
  final items = (jsonDecode(saved.body) as Map<String, dynamic>)['items'] as List<dynamic>;
  if (items.isEmpty) {
    print('    La biblioteca está vacía; no hay id con el que sondear.');
    exit(1);
  }
  final t = (items.first as Map<String, dynamic>);
  final track = (t['track'] ?? t['item']) as Map<String, dynamic>;
  final id = track['id'] as String;
  print('    Usaré "${track['name']}" ($id), que ya está en favoritos.');

  final uri = 'spotify:track:$id';

  print('\n[2] ¿Cómo se consulta si una canción está guardada?');
  informe('GET /me/tracks/contains?ids=', await req('GET', '/me/tracks/contains', {'ids': id}));
  informe('GET /me/library/contains?uris=', await req('GET', '/me/library/contains', {'uris': uri}));
  informe('GET /me/library/contains?uris= (x2)',
      await req('GET', '/me/library/contains', {'uris': '$uri,$uri'}));
  informe('GET /me/library/contains?uris=id suelto',
      await req('GET', '/me/library/contains', {'uris': id}));

  print('\n[3] ¿Cómo se guarda? (PUT idempotente sobre una ya guardada)');
  print('    400 = la forma no es esa; 403 = forma correcta, falta el permiso.');
  informe('PUT /me/library?uris=', await req('PUT', '/me/library', {'uris': uri}));
  informe('PUT /me/library body {uris:[]}',
      await req('PUT', '/me/library', null, {'uris': [uri]}));
  informe('PUT /me/tracks?ids=', await req('PUT', '/me/tracks', {'ids': id}));

  print('\n[4] DELETE no se sondea a propósito: borraría un favorito de verdad.');
  exit(0);
}
