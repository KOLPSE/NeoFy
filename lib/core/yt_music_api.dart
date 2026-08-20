import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'yt_auth.dart';
import 'yt_models.dart';

class YtApiException implements Exception {
  final String message;
  YtApiException(this.message);
  @override
  String toString() => message;
}

class YtMusicApi {
  YtMusicApi(this.auth);

  final YtAuth auth;
  final http.Client _http = http.Client();

  static const _base = 'music.youtube.com';

  static const browseIdInicio = 'FEmusic_home';
  static const browseIdExplorar = 'FEmusic_explore';
  static const browseIdListas = 'FEmusic_liked_playlists';
  static const browseIdAlbumes = 'FEmusic_liked_albums';
  static const browseIdCanciones = 'FEmusic_liked_videos';
  static const browseIdArtistas = 'FEmusic_library_corpus_track_artists';

  static final String _hl = () {
    final l = Platform.localeName;
    final corte = l.indexOf(RegExp(r'[_\-.]'));
    return corte > 0 ? l.substring(0, corte) : 'en';
  }();

  static final String _gl = () {
    final m = RegExp(r'^[a-zA-Z]{2}[_\-]([A-Za-z]{2})').firstMatch(Platform.localeName);
    return m == null ? 'US' : m.group(1)!.toUpperCase();
  }();

  Map<String, dynamic> _contexto() => {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20241201.01.00',
            'hl': _hl,
            'gl': _gl,
          },
          'user': {'lockedSafetyMode': false},
        },
      };

  Future<dynamic> _post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? query,
  }) async {
    if (!auth.isLoggedIn) throw YtApiException('No hay sesión de NeoTube iniciada.');
    final uri = Uri.https(_base, '/youtubei/v1/$endpoint', query);
    final res = await _http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Cookie': auth.cookieHeader(),
            'Authorization': auth.authorizationHeader(),
            'X-Goog-AuthUser': '0',
            'X-Origin': 'https://$_base',
            'Origin': 'https://$_base',
          },
          body: jsonEncode({..._contexto(), ...body}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw YtApiException('YouTube Music devolvió ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body);
  }

  Future<List<YtSection>> buscar(String query) async {
    final j = await _post('search', {'query': query});
    final secciones = <YtSection>[];
    try {
      final tabs = j['contents']['tabbedSearchResultsRenderer']['tabs'] as List;
      final contenido =
          tabs.first['tabRenderer']['content']['sectionListRenderer']['contents'] as List;
      for (final bloque in contenido) {
        final s = _parseSeccion(bloque);
        if (s != null && s.items.isNotEmpty) secciones.add(s);
      }
    } catch (e) {
      debugPrint('[NeoTube buscar] no se pudo parsear: $e');
    }
    return secciones;
  }

  Future<List<YtSection>> browseSections(String browseId) async {
    final secciones = seccionesDeRespuesta(await _post('browse', {'browseId': browseId}));
    if (secciones.isEmpty) {
      debugPrint('[NeoTube browse $browseId] respuesta sin secciones parseables');
    }
    return secciones;
  }

  @visibleForTesting
  List<YtSection> seccionesDeRespuesta(dynamic j) {
    final secciones = <YtSection>[];
    for (final bloque in _bloquesDeSecciones(j)) {
      final s = _parseSeccion(bloque);
      if (s != null && s.items.isNotEmpty) secciones.add(s);
    }
    return secciones;
  }

  Future<List<YtSection>> biblioteca() async {
    final peticiones = <String, String>{
      browseIdListas: 'Tus playlists',
      browseIdAlbumes: 'Tus álbumes',
      browseIdCanciones: 'Canciones que te gustan',
      browseIdArtistas: 'Tus artistas',
    };
    final resultados = await Future.wait(
      peticiones.keys.map((id) async {
        try {
          return await browseSections(id);
        } catch (e) {
          debugPrint('[NeoTube biblioteca $id] fallo: $e');
          return <YtSection>[];
        }
      }),
    );
    final secciones = <YtSection>[];
    var i = 0;
    for (final titulo in peticiones.values) {
      for (final s in resultados[i]) {
        secciones.add(s.titulo.isEmpty ? YtSection(titulo: titulo, items: s.items) : s);
      }
      i++;
    }
    return secciones;
  }

  Future<YtColeccion> coleccion({String? playlistId, String? browseId}) async {
    if (browseId != null && browseId.startsWith('MPRE')) {
      final album = await _browseColeccion(browseId);
      if (album.pistas.isNotEmpty) return album;
    }
    final id = playlistId;
    if (id == null) {
      throw YtApiException('No hay lista que abrir en este elemento.');
    }
    if (!id.startsWith('RD')) {
      final lista = await _browseColeccion(id.startsWith('VL') ? id : 'VL$id');
      if (lista.pistas.isNotEmpty) return lista;
    }
    return _colaDe(playlistId: id);
  }

  Future<YtColeccion> _browseColeccion(String browseId) async {
    final j = await _post('browse', {'browseId': browseId});
    final (coleccion, continuacion) = coleccionDeRespuesta(j);
    var token = continuacion;
    var restantes = 20;
    final pistas = [...coleccion.pistas];
    while (token != null && restantes-- > 0) {
      token = await _continuacion(token, pistas);
    }
    return YtColeccion(
      titulo: coleccion.titulo,
      subtitulo: coleccion.subtitulo,
      miniatura: coleccion.miniatura,
      pistas: pistas,
    );
  }

  @visibleForTesting
  (YtColeccion, String?) coleccionDeRespuesta(dynamic j) {
    final cabecera = _parseCabecera(j);
    final pistas = <YtTrack>[];
    String? continuacion;
    for (final bloque in _bloquesDeContenido(j)) {
      final estante = _valorDeRenderer(bloque);
      if (estante == null) continue;
      final lista = estante['contents'] ?? estante['items'];
      if (lista is! List) continue;
      _acumularPistas(lista, pistas);
      continuacion ??= _tokenDeContinuacion(estante, lista);
    }
    return (
      YtColeccion(
        titulo: cabecera.$1,
        subtitulo: cabecera.$2,
        miniatura: cabecera.$3,
        pistas: pistas,
      ),
      continuacion,
    );
  }

  Future<String?> _continuacion(String token, List<YtTrack> acumulador) async {
    dynamic j;
    try {
      j = await _post('browse', {'continuation': token});
    } catch (_) {
      j = await _post('browse', const {},
          query: {'ctoken': token, 'continuation': token, 'type': 'next'});
    }
    try {
      final acciones = j['onResponseReceivedActions'] as List?;
      if (acciones != null && acciones.isNotEmpty) {
        final items =
            acciones.first['appendContinuationItemsAction']['continuationItems'] as List;
        _acumularPistas(items, acumulador);
        return _tokenDeContinuacion(const {}, items);
      }
    } catch (_) {}
    try {
      final cont = (j['continuationContents'] as Map).values.first as Map;
      final lista = cont['contents'] ?? cont['items'];
      if (lista is List) {
        _acumularPistas(lista, acumulador);
        return _tokenDeContinuacion(cont, lista);
      }
    } catch (_) {}
    return null;
  }

  void _acumularPistas(List lista, List<YtTrack> destino) {
    for (final item in lista) {
      final it = _parseItem(item);
      final pista = it?.comoPista;
      if (pista != null) destino.add(pista);
    }
  }

  String? _tokenDeContinuacion(Map estante, List lista) {
    try {
      final c = estante['continuations'];
      if (c is List && c.isNotEmpty) {
        final t = c.first['nextContinuationData']?['continuation'] as String?;
        if (t != null) return t;
      }
    } catch (_) {}
    try {
      final ultimo = lista.isEmpty ? null : lista.last;
      if (ultimo is Map && ultimo.containsKey('continuationItemRenderer')) {
        return ultimo['continuationItemRenderer']['continuationEndpoint']
            ['continuationCommand']['token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<YtColeccion> _colaDe({String? playlistId, String? videoId}) async {
    final j = await _post('next', {
      'playlistId': ?playlistId,
      'videoId': ?videoId,
      'isAudioOnly': true,
      'params': 'wAEB',
    });
    final pistas = <YtTrack>[];
    String titulo = '';
    try {
      final panel = j['contents']['singleColumnMusicWatchNextResultsRenderer']
              ['tabbedRenderer']['watchNextTabbedResultsRenderer']['tabs'][0]['tabRenderer']
          ['content']['musicQueueRenderer']['content']['playlistPanelRenderer'] as Map;
      titulo = _runsToText(panel['title']?['runs']) ?? '';
      for (final item in (panel['contents'] as List)) {
        final p = _parsePanelVideo(item['playlistPanelVideoRenderer']);
        if (p != null) pistas.add(p);
      }
    } catch (e) {
      debugPrint('[NeoTube next] no se pudo parsear la cola: $e');
    }
    if (pistas.isEmpty) {
      throw YtApiException('YouTube Music no devolvió ninguna pista para esta lista.');
    }
    return YtColeccion(
      titulo: titulo.isEmpty ? 'Mezcla' : titulo,
      subtitulo: '${pistas.length} canciones',
      miniatura: pistas.first.miniatura,
      pistas: pistas,
    );
  }

  Future<List<YtTrack>> radioDe(String videoId) async {
    try {
      final c = await _colaDe(videoId: videoId, playlistId: 'RDAMVM$videoId');
      return c.pistas;
    } catch (e) {
      debugPrint('[NeoTube radio] $e');
      return const [];
    }
  }

  List _bloquesDeSecciones(dynamic j) {
    for (final ruta in [_rutaUnaColumna, _rutaDosColumnasPrimaria]) {
      final r = ruta(j);
      if (r != null && r.isNotEmpty) return r;
    }
    return const [];
  }

  List _bloquesDeContenido(dynamic j) {
    final dos = _rutaDosColumnasSecundaria(j);
    if (dos != null && dos.isNotEmpty) return dos;
    return _bloquesDeSecciones(j);
  }

  List? _rutaUnaColumna(dynamic j) {
    try {
      final tabs = j['contents']['singleColumnBrowseResultsRenderer']['tabs'] as List;
      for (final tab in tabs) {
        final c = tab['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
        if (c is List && c.isNotEmpty) return c;
      }
    } catch (_) {}
    return null;
  }

  List? _rutaDosColumnasPrimaria(dynamic j) {
    try {
      final tabs = j['contents']['twoColumnBrowseResultsRenderer']['tabs'] as List;
      for (final tab in tabs) {
        final c = tab['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
        if (c is List && c.isNotEmpty) return c;
      }
    } catch (_) {}
    return null;
  }

  List? _rutaDosColumnasSecundaria(dynamic j) {
    try {
      final c = j['contents']['twoColumnBrowseResultsRenderer']['secondaryContents']
          ['sectionListRenderer']['contents'];
      if (c is List) return c;
    } catch (_) {}
    return null;
  }

  (String, String, String?) _parseCabecera(dynamic j) {
    for (final candidata in [
      () => _bloquesDeSecciones(j).firstOrNull,
      () => j['header'],
    ]) {
      try {
        var h = _valorDeRenderer(candidata());
        if (h == null) continue;
        if (h.containsKey('header') && h['header'] is Map) {
          h = _valorDeRenderer(h['header']) ?? h;
        }
        final titulo = _runsToText(h['title']?['runs']) ?? '';
        if (titulo.isEmpty) continue;
        final sub = [
          _runsCompletos(h['subtitle']?['runs']),
          _runsCompletos(h['secondSubtitle']?['runs']),
        ].where((s) => s.isNotEmpty).join(' • ');
        final mini = _urlDeMiniatura(h['thumbnail']) ?? _urlDeMiniatura(h['background']);
        return (titulo, sub, mini);
      } catch (_) {}
    }
    return ('', '', null);
  }

  Map? _valorDeRenderer(dynamic bloque) {
    if (bloque is! Map || bloque.isEmpty) return null;
    final v = bloque.values.first;
    return v is Map ? v : null;
  }

  YtSection? _parseSeccion(dynamic bloque) {
    try {
      if (bloque is! Map || bloque.isEmpty) return null;
      final clave = bloque.keys.first;
      if (clave == 'itemSectionRenderer') {
        final dentro = (bloque.values.first as Map)['contents'] as List?;
        if (dentro == null || dentro.isEmpty) return null;
        return _parseSeccion(dentro.first);
      }
      final contenido = _valorDeRenderer(bloque);
      if (contenido == null) return null;

      final lista = contenido['contents'] ?? contenido['items'];
      if (lista is! List) return null;

      final titulo = _tituloDeHeader(contenido['header']) ??
          _runsToText(contenido['title']?['runs']) ??
          '';
      final items = <YtItem>[];
      for (final it in lista) {
        final parseado = _parseItem(it);
        if (parseado != null && parseado.tieneDestino) items.add(parseado);
      }
      return YtSection(titulo: titulo, items: items);
    } catch (_) {
      return null;
    }
  }

  YtItem? _parseItem(dynamic item) {
    if (item is! Map) return null;
    if (item.containsKey('musicTwoRowItemRenderer')) {
      return _parseTwoRowItem(item['musicTwoRowItemRenderer']);
    }
    if (item.containsKey('musicResponsiveListItemRenderer')) {
      return _parseListItem(item['musicResponsiveListItemRenderer']);
    }
    if (item.containsKey('playlistPanelVideoRenderer')) {
      final p = _parsePanelVideo(item['playlistPanelVideoRenderer']);
      return p == null
          ? null
          : YtItem(
              tipo: YtTipo.cancion,
              titulo: p.titulo,
              subtitulo: p.artista,
              videoId: p.videoId,
              miniatura: p.miniatura,
              duracion: p.duracion,
            );
    }
    return null;
  }

  String? _tituloDeHeader(dynamic header) {
    if (header == null) return null;
    try {
      final contenido = _valorDeRenderer(header);
      if (contenido == null) return null;
      return _runsToText(contenido['title']?['runs']) ??
          _runsToText(contenido['strapline']?['runs']);
    } catch (_) {
      return null;
    }
  }

  String? _runsToText(dynamic runs) {
    if (runs is! List || runs.isEmpty) return null;
    return runs.first['text'] as String?;
  }

  String _runsCompletos(dynamic runs) {
    if (runs is! List) return '';
    return runs.map((r) => (r is Map ? r['text'] : null) as String? ?? '').join();
  }

  YtItem? _parseTwoRowItem(dynamic item) {
    if (item is! Map) return null;
    try {
      final nav = item['navigationEndpoint'];
      final videoId = nav?['watchEndpoint']?['videoId'] as String?;
      final playlistId = (nav?['watchPlaylistEndpoint']?['playlistId'] ??
              nav?['watchEndpoint']?['playlistId'] ??
              _playlistDelOverlay(item)) as String?;
      var browseId = nav?['browseEndpoint']?['browseId'] as String?;
      browseId ??= item['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']
          ?['browseId'] as String?;

      final titulo = _runsToText(item['title']?['runs']) ?? '';
      if (titulo.isEmpty) return null;
      final subtitulo = _runsCompletos(item['subtitle']?['runs']);

      return YtItem(
        tipo: _tipoDe(videoId: videoId, playlistId: playlistId, browseId: browseId),
        titulo: titulo,
        subtitulo: subtitulo,
        videoId: videoId,
        playlistId: playlistId ??
            (browseId != null && browseId.startsWith('VL') ? browseId.substring(2) : null),
        browseId: browseId,
        miniatura: _urlDeMiniatura(item['thumbnailRenderer']),
      );
    } catch (_) {
      return null;
    }
  }

  String? _playlistDelOverlay(Map item) {
    try {
      return item['thumbnailOverlay']['musicItemThumbnailOverlayRenderer']['content']
              ['musicPlayButtonRenderer']['playNavigationEndpoint']['watchPlaylistEndpoint']
          ['playlistId'] as String?;
    } catch (_) {
      return null;
    }
  }

  YtItem? _parseListItem(dynamic item) {
    if (item is! Map) return null;
    try {
      final columnas = item['flexColumns'] as List;
      final titulo = _runsToText(
              columnas[0]['musicResponsiveListItemFlexColumnRenderer']['text']['runs']) ??
          '';
      if (titulo.isEmpty) return null;
      var subtitulo = '';
      if (columnas.length > 1) {
        subtitulo = _runsCompletos(
            columnas[1]['musicResponsiveListItemFlexColumnRenderer']['text']?['runs']);
      }

      final videoId = _extraerVideoId(item);
      final nav = item['navigationEndpoint'];
      final browseId = nav?['browseEndpoint']?['browseId'] as String?;
      final playlistId = (nav?['watchPlaylistEndpoint']?['playlistId'] ??
          _playlistDelOverlay(item)) as String?;

      return YtItem(
        tipo: _tipoDe(videoId: videoId, playlistId: playlistId, browseId: browseId),
        titulo: titulo,
        subtitulo: subtitulo,
        videoId: videoId,
        playlistId: playlistId ??
            (browseId != null && browseId.startsWith('VL') ? browseId.substring(2) : null),
        browseId: browseId,
        miniatura: _urlDeMiniatura(item['thumbnail']),
        duracion: _duracionDeFixedColumn(item),
      );
    } catch (_) {
      return null;
    }
  }

  YtTrack? _parsePanelVideo(dynamic item) {
    if (item is! Map) return null;
    try {
      final videoId = item['videoId'] as String?;
      if (videoId == null) return null;
      return YtTrack(
        videoId: videoId,
        titulo: _runsToText(item['title']?['runs']) ?? '',
        artista: _runsCompletos(item['longBylineText']?['runs'] ??
            item['shortBylineText']?['runs']),
        miniatura: _urlDeMiniatura(item['thumbnail']),
        duracion: _parseDuracion(item['lengthText']?['runs']?[0]?['text'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  YtTipo _tipoDe({String? videoId, String? playlistId, String? browseId}) {
    if (videoId != null) return YtTipo.cancion;
    if (browseId != null && browseId.startsWith('MPRE')) return YtTipo.album;
    if (browseId != null && browseId.startsWith('UC')) return YtTipo.artista;
    if (playlistId != null || (browseId != null && browseId.startsWith('VL'))) {
      return YtTipo.lista;
    }
    return YtTipo.desconocido;
  }

  String? _extraerVideoId(dynamic item) {
    try {
      final v = item['playlistItemData']?['videoId'] as String?;
      if (v != null) return v;
    } catch (_) {}
    try {
      return item['overlay']['musicItemThumbnailOverlayRenderer']['content']
          ['musicPlayButtonRenderer']['playNavigationEndpoint']['watchEndpoint']
          ['videoId'] as String?;
    } catch (_) {}
    try {
      return item['navigationEndpoint']['watchEndpoint']['videoId'] as String?;
    } catch (_) {}
    return null;
  }

  Duration? _duracionDeFixedColumn(Map item) {
    try {
      final fijas = item['fixedColumns'] as List;
      final texto = fijas[0]['musicResponsiveListItemFixedColumnRenderer']['text']['runs'][0]
          ['text'] as String?;
      return _parseDuracion(texto);
    } catch (_) {
      return null;
    }
  }

  Duration? _parseDuracion(String? texto) {
    if (texto == null) return null;
    final partes = texto.trim().split(':').map(int.tryParse).toList();
    if (partes.any((p) => p == null)) return null;
    final n = partes.cast<int>();
    return switch (n.length) {
      2 => Duration(minutes: n[0], seconds: n[1]),
      3 => Duration(hours: n[0], minutes: n[1], seconds: n[2]),
      _ => null,
    };
  }

  String? _urlDeMiniatura(dynamic nodo) {
    if (nodo == null) return null;
    List? miniaturas;
    for (final ruta in [
      () => nodo['musicThumbnailRenderer']['thumbnail']['thumbnails'],
      () => nodo['croppedSquareThumbnailRenderer']['thumbnail']['thumbnails'],
      () => nodo['thumbnails'],
      () => nodo['thumbnail']['thumbnails'],
    ]) {
      try {
        final r = ruta();
        if (r is List && r.isNotEmpty) {
          miniaturas = r;
          break;
        }
      } catch (_) {}
    }
    if (miniaturas == null) return null;
    return miniaturas.last['url'] as String?;
  }
}
