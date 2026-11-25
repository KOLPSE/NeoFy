import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ui/letra_sincronizada.dart';
import 'models.dart';

/// Resultado de búsqueda de letra para una pista en LRCLIB.
class ResultadoLetra {
  const ResultadoLetra(
    this.lineas,
    this.textoPlano, {
    this.instrumental = false,
  });

  final List<LineaDeLetra> lineas;
  final String textoPlano;
  final bool instrumental;
}

/// Servicio compartido de letras (LRCLIB) con caché LRU en memoria para que
/// la vista completa y la vista previa del sidebar derecho no dupliquen peticiones.
class LetrasService {
  LetrasService({http.Client? cliente})
      : _client = cliente ?? http.Client(),
        _propio = cliente == null;

  static final _reNormalizar = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static const int _maxCache = 30;

  final http.Client _client;
  final bool _propio;
  final Map<String, ResultadoLetra?> _cache = {};

  Future<ResultadoLetra?> obtener(Track track, {bool forzar = false}) async {
    final clave = track.uri.isNotEmpty
        ? track.uri
        : '${track.name}|${track.artists}|${track.durationMs}';
    if (!forzar && _cache.containsKey(clave)) {
      final existente = _cache.remove(clave);
      _cache[clave] = existente;
      return existente;
    }

    final artista = track.listaDeArtistas.firstOrNull?.name ?? track.artists;
    final duracion = (track.durationMs / 1000).round();
    final campos = {'track_name': track.name, 'artist_name': artista};
    var data =
        await _pedir('/api/get-cached', {
              ...campos,
              'album_name': track.album,
              'duration': '$duracion',
            })
            as Map<String, dynamic>?;
    if (data == null) {
      final candidatos = await _pedir('/api/search', campos) as List<dynamic>?;
      final tituloBuscado = _normalizar(track.name);
      final artistaBuscado = _normalizar(artista);
      final albumBuscado = _normalizar(track.album);
      final coincidentes = (candidatos ?? const [])
          .whereType<Map<String, dynamic>>()
          .where(
            (item) =>
                _normalizar(item['trackName']) == tituloBuscado &&
                _normalizar(item['artistName']) == artistaBuscado &&
                item['duration'] is num &&
                ((item['duration'] as num) - duracion).abs() <= 3,
          )
          .toList();
      data =
          coincidentes
              .where(
                (item) =>
                    _normalizar(item['albumName']) == albumBuscado &&
                    item['hasWordSync'] == true,
              )
              .firstOrNull ??
          coincidentes
              .where(
                (item) =>
                    _normalizar(item['albumName']) == albumBuscado &&
                    (item['syncedLyrics'] as String?)?.isNotEmpty == true,
              )
              .firstOrNull ??
          coincidentes.firstOrNull;
    }

    ResultadoLetra? resultado;
    if (data != null) {
      if (data['instrumental'] == true) {
        resultado = const ResultadoLetra([], '', instrumental: true);
      } else {
        final lines = LineaDeLetra.leer(data, track.durationMs);
        final plain = data['plainLyrics'] as String? ?? '';
        if (lines.isNotEmpty || plain.trim().isNotEmpty) {
          resultado = ResultadoLetra(lines, plain);
        }
      }
    }

    _guardarEnCache(clave, resultado);
    return resultado;
  }

  void _guardarEnCache(String clave, ResultadoLetra? resultado) {
    _cache.remove(clave);
    if (_cache.length >= _maxCache) {
      _cache.remove(_cache.keys.first);
    }
    _cache[clave] = resultado;
  }

  Future<dynamic> _pedir(String path, Map<String, String> query) async {
    final resp = await _client
        .get(
          Uri.https('lrclib.net', path, query),
          headers: const {'User-Agent': 'NeoFy (desktop music player)'},
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw StateError('LRCLIB HTTP ${resp.statusCode}');
    }

    return jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
  }

  String _normalizar(Object? texto) =>
      (texto as String? ?? '').toLowerCase().replaceAll(_reNormalizar, '');

  void dispose() {
    if (_propio) _client.close();
  }
}
