import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:yaml/yaml.dart';

enum ModoVisualizacionLetra { letras, palabras }

typedef _Palabra = ({String texto, int inicio, int? fin});
typedef _Linea = ({
  String texto,
  int inicio,
  int? fin,
  List<_Palabra> palabras,
});
typedef _Tramo = ({int desde, int hasta, int inicio, int fin});

class LineaDeLetra {
  LineaDeLetra._(
    this.inicioMs,
    this.finMs,
    this.texto,
    this._limites,
    this._tramos,
  );

  final int inicioMs;
  final int finMs;
  final String texto;
  final List<int> _limites;
  final List<_Tramo> _tramos;

  static List<LineaDeLetra> leer(
    Map<String, dynamic> respuesta,
    int duracionMs,
  ) {
    final estructuradas = _leerLyricsfile(respuesta['lyricsfile']);
    final lrc = _leerLrc(respuesta['syncedLyrics']);
    final lineas = estructuradas.any((linea) => linea.palabras.isNotEmpty)
        ? estructuradas
        : lrc.isNotEmpty
        ? lrc
        : estructuradas;
    lineas.sort((a, b) => a.inicio.compareTo(b.inicio));
    return [
      for (final (i, linea) in lineas.indexed)
        _preparar(
          linea,
          i + 1 < lineas.length ? lineas[i + 1].inicio : duracionMs,
        ),
    ];
  }

  ({String anterior, String actual, String siguiente}) en(
    int ms, {
    ModoVisualizacionLetra modo = ModoVisualizacionLetra.letras,
  }) {
    var indice = 0;
    var activo = false;
    for (final tramo in _tramos) {
      if (ms < tramo.inicio) break;
      if (ms >= tramo.fin) {
        indice = tramo.hasta;
        continue;
      }
      indice =
          tramo.desde +
          (ms - tramo.inicio) *
              (tramo.hasta - tramo.desde) ~/
              (tramo.fin - tramo.inicio);
      activo = true;
      break;
    }
    if (!activo || indice + 1 >= _limites.length) {
      return (
        anterior: texto.substring(0, _limites[indice]),
        actual: '',
        siguiente: texto.substring(_limites[indice]),
      );
    }
    final visible = _grafema(indice);
    if (visible.trim().isEmpty) {
      return (
        anterior: texto.substring(0, _limites[indice]),
        actual: '',
        siguiente: texto.substring(_limites[indice]),
      );
    }
    if (modo == ModoVisualizacionLetra.letras) {
      return (
        anterior: texto.substring(0, _limites[indice]),
        actual: visible,
        siguiente: texto.substring(_limites[indice + 1]),
      );
    }
    var inicioPalabra = indice;
    while (inicioPalabra > 0 && _grafema(inicioPalabra - 1).trim().isNotEmpty) {
      inicioPalabra--;
    }
    var finPalabra = indice + 1;
    while (finPalabra + 1 < _limites.length &&
        _grafema(finPalabra).trim().isNotEmpty) {
      finPalabra++;
    }
    return (
      anterior: texto.substring(0, _limites[inicioPalabra]),
      actual: texto.substring(_limites[inicioPalabra], _limites[finPalabra]),
      siguiente: texto.substring(_limites[finPalabra]),
    );
  }

  String _grafema(int indice) =>
      texto.substring(_limites[indice], _limites[indice + 1]);

  bool estaEnPausa(int ms) {
    if (ms < inicioMs || ms >= finMs || _tramos.isEmpty) return true;
    for (final tramo in _tramos) {
      if (ms < tramo.inicio) return true;
      if (ms < tramo.fin) {
        final indice =
            tramo.desde +
            (ms - tramo.inicio) *
                (tramo.hasta - tramo.desde) ~/
                (tramo.fin - tramo.inicio);
        if (indice + 1 >= _limites.length) return true;
        return _grafema(indice).trim().isEmpty;
      }
    }
    return true;
  }

  int? siguientePasoMs(
    int ms, {
    required ModoVisualizacionLetra modo,
  }) {
    for (final tramo in _tramos) {
      if (tramo.fin <= ms) continue;
      final total = tramo.hasta - tramo.desde;
      if (total <= 0) continue;
      final duracion = tramo.fin - tramo.inicio;
      for (var g = tramo.desde; g < tramo.hasta; g++) {
        if (g + 1 >= _limites.length) break;
        if (_grafema(g).trim().isEmpty) continue;
        final esInicioPalabra = g == 0 || _grafema(g - 1).trim().isEmpty;
        if (modo == ModoVisualizacionLetra.palabras && !esInicioPalabra) {
          continue;
        }
        final inicioPaso =
            tramo.inicio + ((g - tramo.desde) * duracion) ~/ total;
        if (inicioPaso > ms) return inicioPaso;
      }
    }
    return null;
  }

  static LineaDeLetra _preparar(_Linea linea, int siguiente) {
    final limites = [0];
    for (final grafema in linea.texto.characters) {
      limites.add(limites.last + grafema.length);
    }
    final cantidad = limites.length - 1;
    final estimado = linea.inicio + (cantidad * 155).clamp(900, 11000);
    final limite = siguiente > linea.inicio ? siguiente : estimado;
    var fin = math.min(limite, linea.fin ?? limite);
    if (linea.palabras.isEmpty) fin = math.min(fin, estimado);
    final tramos = <_Tramo>[];
    var indice = 0;
    var cursorMs = linea.inicio;

    void tramoHasta(int hasta, int finTramo) {
      if (hasta > indice) {
        tramos.add((
          desde: indice,
          hasta: hasta,
          inicio: cursorMs,
          fin: finTramo,
        ));
      }
      indice = hasta;
      cursorMs = finTramo;
    }

    for (final palabra in linea.palabras) {
      final visible = palabra.texto.trim();
      if (visible.isEmpty) continue;
      final posicion = linea.texto.indexOf(visible, limites[indice]);
      if (posicion < 0) continue;
      final desde = limites.indexOf(posicion);
      final hasta = limites.indexOf(posicion + visible.length);
      if (desde < indice || hasta <= desde) continue;
      final inicio = palabra.inicio.clamp(cursorMs, fin);
      tramoHasta(desde, inicio);
      tramoHasta(hasta, (palabra.fin ?? fin).clamp(inicio, fin));
    }
    tramoHasta(cantidad, fin);
    return LineaDeLetra._(linea.inicio, fin, linea.texto, limites, tramos);
  }

  static List<_Linea> _leerLyricsfile(Object? contenido) {
    if (contenido is! String || contenido.isEmpty) return [];
    try {
      final doc = loadYaml(contenido);
      if (doc is! Map || doc['lines'] is! List) return [];
      return [
        for (final fila in (doc['lines'] as List).whereType<Map>())
          if (fila['start_ms'] case int inicio when inicio >= 0)
            if (fila['text'] case String texto)
              (
                inicio: inicio,
                fin: fila['end_ms'] is int && fila['end_ms'] > inicio
                    ? fila['end_ms'] as int
                    : null,
                texto: texto.trim(),
                palabras: [
                  for (final palabra
                      in (fila['words'] is List
                              ? fila['words'] as List
                              : const [])
                          .whereType<Map>())
                    if (palabra['start_ms'] case int desde)
                      if (palabra['end_ms'] case int hasta when hasta > desde)
                        if (palabra['text'] case String literal)
                          (texto: literal, inicio: desde, fin: hasta),
                ],
              ),
      ];
    } on YamlException {
      return [];
    }
  }

  static final _marcaLrc = RegExp(r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _marcaInterna = RegExp(r'<(\d+):(\d{2})(?:[.:](\d{1,3}))?>');
  static final _offsetLrc = RegExp(
    r'^\s*\[offset:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
    multiLine: true,
  );

  static int _ms(Match marca) =>
      int.parse(marca[1]!) * 60000 +
      int.parse(marca[2]!) * 1000 +
      int.parse((marca[3] ?? '').padRight(3, '0'));

  static List<_Linea> _leerLrc(Object? contenido) {
    if (contenido is! String) return [];
    final offset =
        int.tryParse(_offsetLrc.firstMatch(contenido)?[1] ?? '') ?? 0;
    final lineas = <_Linea>[];
    for (final original in const LineSplitter().convert(contenido)) {
      final fila = original.trimLeft();
      var cursor = 0;
      final instantes = <int>[];
      var marca = _marcaLrc.matchAsPrefix(fila, cursor);
      while (marca != null) {
        instantes.add(_ms(marca));
        cursor = marca.end;
        marca = _marcaLrc.matchAsPrefix(fila, cursor);
      }
      if (instantes.isEmpty) continue;
      final cuerpo = fila.substring(cursor);
      final internas = _marcaInterna.allMatches(cuerpo).toList();
      final texto = cuerpo.replaceAll(_marcaInterna, '').trim();
      for (final inicio in instantes) {
        final desfase = inicio - instantes.first - offset;
        lineas.add((
          inicio: inicio - offset,
          fin: null,
          texto: texto,
          palabras: [
            for (final (i, marca) in internas.indexed)
              (
                texto: cuerpo.substring(
                  marca.end,
                  i + 1 < internas.length
                      ? internas[i + 1].start
                      : cuerpo.length,
                ),
                inicio: _ms(marca) + desfase,
                fin: i + 1 < internas.length
                    ? _ms(internas[i + 1]) + desfase
                    : null,
              ),
          ],
        ));
      }
    }
    return lineas;
  }
}
