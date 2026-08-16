// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:neofy/core/app_config.dart';
import 'package:path/path.dart' as p;

const _base = 'music.youtube.com';

Future<void> main(List<String> args) async {
  final volcar = args.contains('--volcar');
  final ids = args.where((a) => !a.startsWith('--')).toList();

  final f = File(p.join(appDataDir().path, 'yt_cookies.json'));
  if (!f.existsSync()) {
    print('No hay sesión de YouTube en ${appDataDir().path}.');
    print('Conéctala desde Ajustes y vuelve a ejecutar esto.');
    exit(1);
  }

  final crudas = (jsonDecode(await f.readAsString()) as List).cast<Map<String, dynamic>>();
  final basura = RegExp(r'[^\x21-\x7E]');
  final cookies = <String, String>{};
  for (final c in crudas) {
    final nombre = (c['name'] as String? ?? '').replaceAll(basura, '');
    final valor = (c['value'] as String? ?? '').replaceAll(basura, '');
    if (nombre.isEmpty) continue;
    cookies.putIfAbsent(nombre, () => valor);
  }
  final nombreSapisid = const ['SAPISID', '__Secure-3PAPISID', '__Secure-1PAPISID']
      .firstWhere((n) => (cookies[n] ?? '').isNotEmpty, orElse: () => '');
  final sapisid = cookies[nombreSapisid] ?? '';
  if (sapisid.isEmpty) {
    print('Las cookies guardadas no traen SAPISID: la sesión no vale.');
    exit(1);
  }
  print('Sesión: ${cookies.length} cookies, firmando con $nombreSapisid.\n');

  final cabeceraCookie = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<Map<String, dynamic>> browse(String browseId) async {
    final epoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final origin = 'https://$_base';
    final hash = sha1.convert(utf8.encode('$epoch $sapisid $origin')).toString();
    final res = await http.post(
      Uri.https(_base, '/youtubei/v1/browse'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cabeceraCookie,
        'Authorization': 'SAPISIDHASH ${epoch}_$hash',
        'X-Goog-AuthUser': '0',
        'X-Origin': origin,
        'Origin': origin,
      },
      body: jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20241201.01.00',
            'hl': 'es',
            'gl': 'ES',
          },
          'user': {'lockedSafetyMode': false},
        },
        'browseId': browseId,
      }),
    );
    if (res.statusCode != 200) {
      throw 'HTTP ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 300))}';
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  final objetivos = ids.isNotEmpty
      ? ids
      : const [
          'FEmusic_home',
          'FEmusic_liked_playlists',
          'FEmusic_liked_albums',
          'FEmusic_liked_videos',
        ];

  for (final id in objetivos) {
    print('─── $id ${'─' * (50 - id.length).clamp(0, 50)}');
    try {
      final j = await browse(id);
      if (volcar) {
        final salida = File('${Directory.systemTemp.path}/yt_$id.json');
        await salida.writeAsString(const JsonEncoder.withIndent('  ').convert(j));
        print('JSON crudo en ${salida.path}');
      }
      _describir(j);
    } catch (e) {
      print('  FALLO: $e');
    }
    print('');
  }
}

void _describir(Map<String, dynamic> j) {
  final contenido = j['contents'] as Map<String, dynamic>?;
  if (contenido == null) {
    print('  sin `contents`: claves de primer nivel ${j.keys.toList()}');
    return;
  }
  print('  contents → ${contenido.keys.toList()}');

  var encontrado = false;
  for (final raiz in ['singleColumnBrowseResultsRenderer', 'twoColumnBrowseResultsRenderer']) {
    final r = contenido[raiz];
    if (r == null) continue;
    for (final tab in (r['tabs'] as List? ?? const [])) {
      final c = tab['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
      if (c is List && c.isNotEmpty) {
        print('  [pestaña] ${c.length} bloques:');
        for (final bloque in c) {
          _describirBloque(bloque, '    ');
        }
        encontrado = true;
        break;
      }
    }
    final sec = r['secondaryContents']?['sectionListRenderer']?['contents'];
    if (sec is List && sec.isNotEmpty) {
      print('  [secondaryContents] ${sec.length} bloques:');
      for (final bloque in sec) {
        _describirBloque(bloque, '    ');
      }
      encontrado = true;
    }
  }

  if (!encontrado) print('  no se encontró ningún sectionListRenderer con contenido');
}

void _describirBloque(dynamic bloque, String sangria) {
  if (bloque is! Map || bloque.isEmpty) {
    print('$sangria(bloque vacío o inesperado)');
    return;
  }
  final clave = bloque.keys.first;
  final valor = bloque.values.first;
  if (clave == 'itemSectionRenderer') {
    print('$sangria$clave → desenvuelve:');
    for (final dentro in ((valor as Map)['contents'] as List? ?? const [])) {
      _describirBloque(dentro, '$sangria  ');
    }
    return;
  }
  if (valor is! Map) {
    print('$sangria$clave (sin cuerpo)');
    return;
  }
  if (clave == 'messageRenderer') {
    print('$sangria$clave → «${_texto(valor['text']) ?? '?'}»'
        '${valor['subtext'] == null ? '' : ' / «${_texto(valor['subtext']?['messageSubtextRenderer']?['text']) ?? '?'}»'}');
    return;
  }
  final desde = valor.containsKey('contents')
      ? 'contents'
      : valor.containsKey('items')
          ? 'items'
          : null;
  final lista = desde == null ? null : valor[desde] as List?;
  final titulo = _texto(valor['title']) ?? _tituloDeHeader(valor['header']) ?? '(sin título)';
  print('$sangria$clave  título="$titulo"  elementos en '
      '${desde ?? "NINGUNA CLAVE CONOCIDA (${valor.keys.toList()})"}'
      '${lista == null ? "" : " (${lista.length})"}');

  for (final item in (lista ?? const []).take(3)) {
    if (item is! Map || item.isEmpty) continue;
    final tipoItem = item.keys.first;
    final cuerpo = item.values.first;
    if (cuerpo is! Map) continue;
    final t = _texto(cuerpo['title']) ??
        _texto(cuerpo['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']
            ?['text']) ??
        '?';
    final nav = cuerpo['navigationEndpoint'];
    final destino = nav?['browseEndpoint']?['browseId'] ??
        nav?['watchEndpoint']?['videoId'] ??
        nav?['watchPlaylistEndpoint']?['playlistId'] ??
        cuerpo['playlistItemData']?['videoId'] ??
        '—';
    print('$sangria  · $tipoItem "$t" → $destino');
  }
}

String? _tituloDeHeader(dynamic header) {
  if (header is! Map || header.isEmpty) return null;
  final v = header.values.first;
  return v is Map ? _texto(v['title']) : null;
}

String? _texto(dynamic nodo) {
  final runs = (nodo is Map ? nodo['runs'] : null) as List?;
  if (runs == null || runs.isEmpty) return null;
  return runs.map((r) => (r is Map ? r['text'] : null) as String? ?? '').join();
}
