// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _host = 'git.neogex.xyz';
const _proyecto = 'apps/neofy';

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

  final endpoint = Uri.parse(
    'https://$_host/api/v4/projects/${Uri.encodeComponent(_proyecto)}/releases/permalink/latest',
  );
  final res = await http.get(
    endpoint,
    headers: {'Accept': 'application/json'},
  );
  print('GET $endpoint → HTTP ${res.statusCode}');
  if (res.statusCode != 200) {
    print(res.body);
    exit(1);
  }

  final j = jsonDecode(res.body) as Map<String, dynamic>;
  final etiqueta = j['tag_name'] as String? ?? '';
  final version = etiqueta.replaceFirst(RegExp('^v'), '');
  print('  última release: $etiqueta  →  versión $version');

  final assets = j['assets'] as Map<String, dynamic>?;
  final enlaces = (assets?['links'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  print('  enlaces de descarga: ${enlaces.length}');
  for (final e in enlaces) {
    print('    ${e['name']}  [${e['link_type']}]  ${e['url']}');
  }

  final exe = enlaces.where((e) {
    final url = e['url'] as String?;
    final uri = url == null ? null : Uri.tryParse(url);
    return uri != null && uri.path.toLowerCase().endsWith('.exe');
  });
  if (exe.isEmpty) {
    print('\n  ✗ La release NO trae instalador: el actualizador lo rechazaría.');
    exit(1);
  }
  final url = exe.first['url'] as String;
  final uri = Uri.parse(url);
  final fiable = uri.scheme == 'https' && uri.host == _host;
  print('  host de la descarga: ${uri.host}  ${fiable ? '(fiable)' : '(RECHAZADO)'}');

  print('\nVeredicto para $instalada: '
      '${esMasNueva(version, instalada) ? "SE OFRECE actualizar a $version" : "al día"}');

  final cabeza = await http.head(uri);
  print('HEAD del instalador → HTTP ${cabeza.statusCode}'
      '  ${cabeza.headers['content-type'] ?? ''}'
      '  ${cabeza.headers['content-length'] ?? ''} bytes');
  exit(0);
}
