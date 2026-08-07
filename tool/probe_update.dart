// Sonda del actualizador: ¿ve la app la última release, y trae instalador?
//
//   dart run tool/probe_update.dart [version-instalada]
//
// Replica exactamente lo que hace `core/updater.dart` contra la API de verdad.
// Existe porque `flutter test` no puede hacer red —sustituye HttpClient por un
// mock que devuelve 400—, así que la parte que habla con GitHub no se puede
// ejercitar desde un test. La comparación de versiones sí tiene tests.
//
// ignore_for_file: avoid_print  — es una herramienta de diagnóstico.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _repo = 'KOLPSE/NeoFy';

/// La misma regla que `Updater.esMasNueva`: por tramos numéricos, nunca como
/// texto. "0.10.0" es posterior a "0.9.0" aunque alfabéticamente diga lo
/// contrario.
bool esMasNueva(String candidata, String actual) {
  List<int> tramos(String v) =>
      v.split(RegExp(r'[.+-]')).map((t) => int.tryParse(t) ?? 0).toList();
  final a = tramos(candidata);
  final b = tramos(actual);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

Future<void> main(List<String> args) async {
  final instalada = args.isEmpty ? '0.1.0' : args.first;
  print('Simulando una instalación en la versión $instalada\n');

  final res = await http.get(
    Uri.https('api.github.com', '/repos/$_repo/releases/latest'),
    headers: {'Accept': 'application/vnd.github+json'},
  );
  print('GET /releases/latest → HTTP ${res.statusCode}');
  if (res.statusCode != 200) {
    print(res.body);
    exit(1);
  }

  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final etiqueta = j['tag_name'] as String? ?? '';
  final version = etiqueta.replaceFirst(RegExp('^v'), '');
  print('  última release: $etiqueta  →  versión $version');

  final assets = (j['assets'] as List<dynamic>).whereType<Map<String, dynamic>>();
  print('  assets: ${assets.length}');
  for (final a in assets) {
    print('    ${a['name']}  ${((a['size'] as num) / 1048576).toStringAsFixed(1)} MB'
        '  descargas: ${a['download_count']}');
  }

  final exe = assets.where((a) => (a['name'] as String).endsWith('.exe'));
  if (exe.isEmpty) {
    print('\n  ✗ La release NO trae instalador: el actualizador lo rechazaría.');
    exit(1);
  }
  final url = exe.first['browser_download_url'] as String;
  final host = Uri.parse(url).host;
  print('  host de la descarga: $host  ${host == 'github.com' ? '(fiable)' : '(RECHAZADO)'}');

  print('\nVeredicto para $instalada: '
      '${esMasNueva(version, instalada) ? "SE OFRECE actualizar a $version" : "al día"}');

  // Que el fichero se pueda bajar de verdad sin autenticación es la mitad del
  // asunto: una release privada o un asset a medio subir daría 404 aquí.
  final cabeza = await http.head(Uri.parse(url));
  print('HEAD del instalador → HTTP ${cabeza.statusCode}'
      '  ${cabeza.headers['content-length'] ?? ''} bytes');
  exit(0);
}
