import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'models.dart';

class UltimaReproduccion {
  const UltimaReproduccion({
    required this.track,
    required this.posicionMs,
    this.contextUri,
    this.uris,
  });

  final Track track;
  final int posicionMs;
  final String? contextUri;
  final List<String>? uris;

  UltimaReproduccion conPosicion(int ms) => UltimaReproduccion(
        track: track,
        posicionMs: ms,
        contextUri: contextUri,
        uris: uris,
      );

  Map<String, dynamic> toJson() => {
        'track': {
          'id': track.id,
          'uri': track.uri,
          'name': track.name,
          'artists': track.artists,
          'album': track.album,
          'artSmall': track.artSmall,
          'artMedium': track.artMedium,
          'durationMs': track.durationMs,
          'isLocal': track.isLocal,
        },
        'posicionMs': posicionMs,
        if (contextUri != null) 'contextUri': contextUri,
        if (uris != null) 'uris': uris,
      };

  static UltimaReproduccion? fromJson(Map<String, dynamic> j) {
    final t = j['track'];
    if (t is! Map<String, dynamic>) return null;
    final uri = t['uri'];
    if (uri is! String || uri.isEmpty) return null;
    final crudas = j['uris'];
    final uris = crudas is List
        ? [
            for (final u in crudas)
              if (u is String && u.isNotEmpty) u,
          ]
        : null;
    return UltimaReproduccion(
      track: Track(
        id: (t['id'] as String?) ?? '',
        uri: uri,
        name: (t['name'] as String?) ?? 'Desconocido',
        artists: (t['artists'] as String?) ?? '',
        album: (t['album'] as String?) ?? '',
        artSmall: t['artSmall'] as String?,
        artMedium: t['artMedium'] as String?,
        durationMs: (t['durationMs'] as num?)?.toInt() ?? 0,
        isLocal: (t['isLocal'] as bool?) ?? false,
      ),
      posicionMs: (j['posicionMs'] as num?)?.toInt() ?? 0,
      contextUri: j['contextUri'] as String?,
      uris: uris == null || uris.isEmpty ? null : uris,
    );
  }

  static const int kMaxUris = 300;

  static List<String>? colaDesde(List<String>? uris, String uriActual) {
    if (uris == null || uris.isEmpty) return null;
    final desde = uris.indexOf(uriActual);
    final resto = desde < 0 ? uris : uris.sublist(desde);
    return List.unmodifiable(
      resto.length > kMaxUris ? resto.sublist(0, kMaxUris) : resto,
    );
  }
}

class UltimaReproduccionStore {
  UltimaReproduccionStore({Directory? directorio})
      : _directorio = directorio ?? appDataDir();

  final Directory _directorio;

  File get _fichero => File(p.join(_directorio.path, 'ultima_reproduccion.json'));

  Future<UltimaReproduccion?> cargar() async {
    try {
      final f = _fichero;
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString());
      if (map is! Map<String, dynamic>) return null;
      return UltimaReproduccion.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar(UltimaReproduccion r) async {
    try {
      await _fichero.writeAsString(jsonEncode(r.toJson()));
    } catch (e) {
      debugPrint('No se pudo guardar ultima_reproduccion.json: $e');
    }
  }

  Future<void> borrar() async {
    try {
      final f = _fichero;
      if (await f.exists()) await f.delete();
    } catch (_) {
    }
  }
}
