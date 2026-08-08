// Sonda para la pantalla de artista: ¿se pueden LEER sus canciones?
//
//   dart run tool/probe_artist.dart
//
// Que un artista se pueda REPRODUCIR (playContext con su uri, que es lo que
// hace hoy la portada) no implica que se puedan leer sus canciones. En este
// proyecto esa distincion ya ha mordido varias veces: en Modo Desarrollo,
// `/v1/tracks?ids=` da 403 y el contenido de una playlist ajena tambien,
// aunque las dos cosas suenen perfectamente.
//
// Antes de construir una pantalla encima hay que saber cual de estas vias
// existe de verdad:
//
//   1. /artists/{id}/top-tracks   lo natural: las 10 mas populares
//   2. /artists/{id}              para el nombre y la foto
//   3. /artists/{id}/albums       plan B: sus discos...
//   4. /albums/{id}/tracks        ...y las canciones de cada uno, que segun
//                                 ARQUITECTURA.md si se dejan leer
//
// ⚠️ Ejecutar con la app CERRADA: renueva el token, y Spotify rota el refresh
// token en cada renovacion. Este script lo guarda de vuelta en tokens.json,
// igual que probe_top.dart; sin eso, la app se queda sin sesion.
//
// ignore_for_file: avoid_print  — es una herramienta de diagnostico.
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

/// Cuenta lo que paso, distinguiendo los dos 403 que este proyecto ya conoce:
/// "Insufficient client scope" es una ruta viva a la que le falta permiso, y
/// "Forbidden" a secas es una ruta muerta en Modo Desarrollo.
void informe(String etiqueta, http.Response r) {
  final cuerpo = utf8.decode(r.bodyBytes);
  var nota = '';
  if (r.statusCode == 403) {
    nota = cuerpo.contains('Insufficient client scope')
        ? '  (falta scope: la ruta existe)'
        : '  (Forbidden a secas: capado en Modo Desarrollo)';
  }
  print('  ${r.statusCode}  $etiqueta$nota');
  if (r.statusCode >= 400) {
    print('        ${cuerpo.replaceAll('\n', ' ').trim()}');
  }
}

Future<void> main() async {
  final dir = appDataDir();
  final fichero = File(p.join(dir.path, 'tokens.json'));
  if (!fichero.existsSync()) {
    print('No hay sesion guardada en ${fichero.path}. Abre la app y entra una vez.');
    exit(1);
  }
  final guardado = jsonDecode(fichero.readAsStringSync()) as Map<String, dynamic>;
  final refresh = guardado['refresh_token'] as String?;
  final config = await AppConfig.load();
  if (refresh == null || config.clientId.isEmpty) {
    print('Falta el refresh token o el Client ID.');
    exit(1);
  }

  // --- Renovar, y devolver el token rotado a su sitio ------------------------
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
  // ⚠️ Esto es lo que evita dejar la app sin sesion: Spotify rota el refresh
  // token en cada renovacion y el viejo deja de valer.
  guardado['refresh_token'] = (tok['refresh_token'] as String?) ?? refresh;
  guardado['access_token'] = _token;
  guardado['expires_at'] = DateTime.now()
      .add(Duration(seconds: (tok['expires_in'] as num?)?.toInt() ?? 3600))
      .toIso8601String();
  fichero.writeAsStringSync(jsonEncode(guardado));
  print('Token renovado y guardado de vuelta.\n');

  // --- Un artista de verdad, de los que ya salen en la portada --------------
  final top = await get('/me/top/artists', {'limit': '1'});
  if (top.statusCode != 200) {
    print('No se pudo leer /me/top/artists: ${top.statusCode}');
    exit(1);
  }
  final artistas =
      (jsonDecode(utf8.decode(top.bodyBytes))['items'] as List<dynamic>);
  if (artistas.isEmpty) {
    print('La cuenta no tiene artistas top todavia.');
    exit(1);
  }
  final a = artistas.first as Map<String, dynamic>;
  final id = a['id'] as String;
  print('Artista de prueba: ${a['name']}  ($id)\n');

  // --- Las cuatro vias ------------------------------------------------------
  print('1. Las canciones mas populares del artista');
  final t1 = await get('/artists/$id/top-tracks', {'market': 'from_token'});
  informe('/artists/$id/top-tracks?market=from_token', t1);
  if (t1.statusCode == 200) {
    final tracks = jsonDecode(utf8.decode(t1.bodyBytes))['tracks'] as List<dynamic>?;
    print('        ${tracks?.length ?? 0} canciones');
    for (final t in (tracks ?? const []).take(3)) {
      final m = t as Map<String, dynamic>;
      print('        - ${m['name']}  (${m['duration_ms']} ms)');
    }
  }
  // Sin market, por si el parametro fuera el problema y no la ruta.
  final t1b = await get('/artists/$id/top-tracks');
  informe('/artists/$id/top-tracks  (sin market)', t1b);

  print('\n2. La ficha del artista');
  informe('/artists/$id', await get('/artists/$id'));

  print('\n3. Sus discos');
  final t3 = await get('/artists/$id/albums',
      {'include_groups': 'album,single', 'limit': '5'});
  informe('/artists/$id/albums', t3);
  String? albumId;
  if (t3.statusCode == 200) {
    final items = jsonDecode(utf8.decode(t3.bodyBytes))['items'] as List<dynamic>?;
    print('        ${items?.length ?? 0} discos');
    if (items != null && items.isNotEmpty) {
      albumId = (items.first as Map<String, dynamic>)['id'] as String?;
    }
  }

  print('\n4. Las canciones de uno de sus discos');
  if (albumId == null) {
    print('  --  no hay disco con el que probar');
  } else {
    final t4 = await get('/albums/$albumId/tracks', {'limit': '5'});
    informe('/albums/$albumId/tracks', t4);
    if (t4.statusCode == 200) {
      final items =
          jsonDecode(utf8.decode(t4.bodyBytes))['items'] as List<dynamic>?;
      print('        ${items?.length ?? 0} canciones');
      // Lo que hace falta para el total: que venga la duracion de cada una.
      final primera = (items?.firstOrNull) as Map<String, dynamic>?;
      print('        duration_ms presente: ${primera?['duration_ms'] != null}');
    }
  }

  print('\nListo. La via que conteste 200 es sobre la que se puede construir.');
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
