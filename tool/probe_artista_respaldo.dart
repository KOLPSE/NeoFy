// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';

late String _token;

Future<http.Response> get(String path, [Map<String, String>? q]) => http.get(
      Uri.https('api.spotify.com', '/v1$path', q),
      headers: {'Authorization': 'Bearer $_token'},
    );

void informe(String etiqueta, http.Response r) {
  print('  ${r.statusCode}  $etiqueta');
  if (r.statusCode >= 400) {
    print('        ${utf8.decode(r.bodyBytes).replaceAll('\n', ' ').trim()}');
  }
}

Future<void> main(List<String> args) async {
  final dir = appDataDir();
  final fichero = File(p.join(dir.path, 'tokens.json'));
  final guardado = jsonDecode(fichero.readAsStringSync()) as Map<String, dynamic>;
  final refresh = guardado['refresh_token'] as String?;
  final config = await AppConfig.load();
  if (refresh == null || config.clientId.isEmpty) {
    print('Falta el refresh token o el Client ID.');
    exit(1);
  }

  final r = await http.post(
    Uri.https('accounts.spotify.com', '/api/token'),
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
      'client_id': config.clientId,
    },
  );
  if (r.statusCode != 200) {
    print('No se pudo renovar el token: ${r.statusCode} ${r.body}');
    exit(1);
  }
  final tok = jsonDecode(r.body) as Map<String, dynamic>;
  _token = tok['access_token'] as String;
  guardado['refresh_token'] = (tok['refresh_token'] as String?) ?? refresh;
  guardado['access_token'] = _token;
  guardado['expires_at'] = DateTime.now()
      .add(Duration(seconds: (tok['expires_in'] as num?)?.toInt() ?? 3600))
      .toIso8601String();
  fichero.writeAsStringSync(jsonEncode(guardado));
  print('Token renovado y guardado de vuelta.\n');

  final top = await get('/me/top/artists', {'limit': '1'});
  final artistas = (jsonDecode(utf8.decode(top.bodyBytes))['items'] as List<dynamic>);
  final a = artistas.first as Map<String, dynamic>;
  final id = a['id'] as String;
  final nombre = a['name'] as String;
  print('Artista de prueba: $nombre  ($id)\n');

  print('1. Sus discos (una peticion). Donde esta el tope de limit:');
  http.Response? discos;
  for (final n in ['20', '10', '5']) {
    final r = await get('/artists/$id/albums',
        {'include_groups': 'album,single', 'limit': n});
    informe('/artists/$id/albums?limit=$n', r);
    if (r.statusCode == 200 && discos == null) discos = r;
  }
  final ids = <String>[];
  if (discos != null && discos.statusCode == 200) {
    final items = jsonDecode(utf8.decode(discos.bodyBytes))['items'] as List<dynamic>;
    for (final d in items) {
      final m = d as Map<String, dynamic>;
      final did = m['id'] as String?;
      if (did != null) ids.add(did);
    }
    print('        ${ids.length} discos');
  }

  print('\n2. Todos esos discos de golpe: /albums?ids=');
  if (ids.isEmpty) {
    print('  --  sin discos con los que probar');
  } else {
    final lote = await get('/albums', {'ids': ids.take(20).join(',')});
    informe('/albums?ids=(${ids.take(20).length})', lote);
    if (lote.statusCode == 200) {
      final items = jsonDecode(utf8.decode(lote.bodyBytes))['albums'] as List<dynamic>?;
      var canciones = 0;
      var conImagen = 0;
      var conPopularidad = 0;
      for (final d in (items ?? const [])) {
        final m = d as Map<String, dynamic>?;
        if (m == null) continue;
        if ((m['images'] as List<dynamic>?)?.isNotEmpty ?? false) conImagen++;
        if (m['popularity'] != null) conPopularidad++;
        final t = (m['tracks'] as Map<String, dynamic>?)?['items'] as List<dynamic>?;
        canciones += t?.length ?? 0;
      }
      print('        ${items?.length ?? 0} discos, $canciones canciones, '
          '$conImagen con imagen, $conPopularidad con popularity');
    }
  }

  print('\n3. La otra via: buscar por artista');
  final busq = await get('/search',
      {'q': 'artist:"$nombre"', 'type': 'track', 'limit': '10'});
  informe('/search?q=artist:"$nombre"&type=track', busq);
  if (busq.statusCode == 200) {
    final items = (jsonDecode(utf8.decode(busq.bodyBytes))['tracks']
        as Map<String, dynamic>?)?['items'] as List<dynamic>?;
    var delArtista = 0;
    for (final t in (items ?? const [])) {
      final m = t as Map<String, dynamic>;
      final aut = (m['artists'] as List<dynamic>?) ?? const [];
      if (aut.any((x) => (x as Map)['id'] == id)) delArtista++;
    }
    print('        ${items?.length ?? 0} canciones, $delArtista son suyas de verdad');
    for (final t in (items ?? const []).take(3)) {
      final m = t as Map<String, dynamic>;
      print('        - ${m['name']}  (popularity ${m['popularity']})');
    }
  }

  print('\nListo.');
}
