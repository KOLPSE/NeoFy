// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';

const _nombrePrueba = '· prueba neofy ·';

late String _token;

Future<http.Response> req(String method, String path,
    [Map<String, String>? q, Object? cuerpo]) {
  final uri = Uri.https('api.spotify.com', '/v1$path', q);
  final r = http.Request(method, uri)..headers['Authorization'] = 'Bearer $_token';
  if (cuerpo != null) {
    r.headers['Content-Type'] = 'application/json';
    r.body = jsonEncode(cuerpo);
  }
  return http.Client().send(r).then(http.Response.fromStream);
}

void informe(String etiqueta, http.Response r) {
  final cuerpo = r.body.length > 200 ? '${r.body.substring(0, 200)}…' : r.body;
  print('    $etiqueta → HTTP ${r.statusCode}  ${cuerpo.replaceAll(RegExp(r'\s+'), ' ')}');
}

Future<void> main() async {
  final f = File(p.join(appDataDir().path, 'tokens.json'));
  if (!f.existsSync()) {
    print('No hay sesión guardada. Inicia sesión en la app.');
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
    print('No se pudo renovar el token: ${res.body}');
    exit(1);
  }
  _token = (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;

  final me = jsonDecode((await req('GET', '/me')).body) as Map<String, dynamic>;
  final userId = me['id'] as String;
  print('Cuenta: $userId');

  print('\n[1] Crear una playlist');
  final creada = await req('POST', '/me/playlists', null, {
    'name': _nombrePrueba,
    'public': false,
    'description': 'Creada por probe_home.dart; se borra sola.',
  });
  informe('POST /me/playlists', creada);
  informe('POST /users/{id}/playlists',
      await req('POST', '/users/$userId/playlists', null, {'name': _nombrePrueba}));

  String? id;
  if (creada.statusCode < 300) {
    id = (jsonDecode(creada.body) as Map<String, dynamic>)['id'] as String?;
    print('    id = $id');
  }

  print('\n[2] Borrarla (que en Spotify es "dejar de seguirla")');
  if (id == null) {
    print('    No se creó nada; no hay qué borrar.');
  } else {
    final candidatas = <List<Object?>>[
      ['DELETE', '/playlists/$id/followers', null],
      ['DELETE', '/me/playlists', {'uris': 'spotify:playlist:$id'}],
      ['DELETE', '/playlists/$id', null],
    ];
    for (final c in candidatas) {
      final r = await req(c[0]! as String, c[1]! as String,
          c[2] as Map<String, String>?);
      informe('${c[0]} ${c[1]}', r);
      if (r.statusCode < 300) break;
    }
    final sigue = await req('GET', '/playlists/$id/followers/contains',
        {'ids': userId});
    informe('¿la sigo aún?', sigue);
  }

  print('\n[3] ¿Qué hay para una portada de "hecho para ti"?');
  informe('GET /browse/featured-playlists',
      await req('GET', '/browse/featured-playlists', {'limit': '3'}));
  informe('GET /browse/new-releases',
      await req('GET', '/browse/new-releases', {'limit': '3'}));
  informe('GET /browse/categories',
      await req('GET', '/browse/categories', {'limit': '3'}));
  informe('GET /me/top/tracks', await req('GET', '/me/top/tracks', {'limit': '3'}));
  informe('GET /me/top/artists', await req('GET', '/me/top/artists', {'limit': '3'}));
  informe('GET /me/player/recently-played',
      await req('GET', '/me/player/recently-played', {'limit': '3'}));
  informe('GET /recommendations',
      await req('GET', '/recommendations', {'limit': '3', 'seed_genres': 'rock'}));
  informe('GET /search "Daily Mix"',
      await req('GET', '/search', {'q': 'Daily Mix', 'type': 'playlist', 'limit': '3'}));
  informe('GET /me/library/home', await req('GET', '/me/library/home', null));
  informe('GET /me/home', await req('GET', '/me/home', null));

  print('\n[4] ¿Salen las listas de Spotify en mis playlists?');
  final mias = await req('GET', '/me/playlists', {'limit': '50'});
  if (mias.statusCode == 200) {
    final items = (jsonDecode(mias.body) as Map<String, dynamic>)['items'] as List<dynamic>;
    for (final raw in items) {
      final pl = raw as Map<String, dynamic>;
      final owner = (pl['owner'] as Map<String, dynamic>?)?['id'];
      if (owner != userId) {
        print('    [$owner] ${pl['name']}  (${pl['uri']})');
      }
    }
    print('    ${items.length} playlists en total.');
  } else {
    informe('GET /me/playlists', mias);
  }
  exit(0);
}
