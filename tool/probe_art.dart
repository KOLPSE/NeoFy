// Sonda del camino de descarga y cacheo de carátulas.
//
//   dart run tool/probe_art.dart [url]
//
// Existe porque `flutter test` sustituye HttpClient por un mock que devuelve
// 400: la descarga real no se puede ejercitar desde un test. Este script sí,
// y compara `package:http` a pelo contra ArtCache para localizar en cuál de
// los dos está el problema. Encontró el interbloqueo de `whenComplete` que
// dejaba todas las carátulas en blanco.
//
// ignore_for_file: avoid_print  — es una herramienta de diagnóstico; imprimir
// por consola es exactamente lo que tiene que hacer.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/art_cache.dart';

const _ejemplo = 'https://i.scdn.co/image/ab67616d00004851dcef04ac3fb21aaf6f91a49b';

Future<void> main(List<String> args) async {
  final url = args.isEmpty ? _ejemplo : args.first;

  print('Carpeta de datos: ${appDataDir().path}');
  print('URL: $url');

  print('\n[1] package:http directo...');
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    print('    HTTP ${res.statusCode}, ${res.bodyBytes.length} bytes');
  } catch (e) {
    print('    FALLO: $e');
  }

  print('\n[2] ArtCache.bytes()...');
  try {
    final bytes = await ArtCache.bytes(url).timeout(const Duration(seconds: 20));
    if (bytes == null) {
      print('    RESULTADO: null (descarga fallida o estado != 200)');
    } else {
      final head =
          bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('    RESULTADO: ${bytes.length} bytes, cabecera: $head');
    }
  } catch (e) {
    print('    FALLO: $e');
  }

  print('\n[3] estado de la caché en disco');
  final artDir = Directory(p.join(appDataDir().path, 'art'));
  print('    existe: ${artDir.existsSync()}');
  if (artDir.existsSync()) {
    final files = artDir.listSync();
    print('    ficheros: ${files.length}');
    for (final f in files.take(5)) {
      print('      ${p.basename(f.path)}  ${f.statSync().size} bytes');
    }
  }
  exit(0);
}
