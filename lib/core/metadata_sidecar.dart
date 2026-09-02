import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'models.dart';
import 'procesos.dart';
import 'idiomas_spotify.dart';

class MetadataSidecar extends ChangeNotifier {
  static const int puerto = 8900;

  MetadataSidecar({String Function()? localeEfectivo})
      : _localeEfectivo = localeEfectivo ?? localeSpotifyDesdePc;

  final String Function() _localeEfectivo;

  Process? _proc;
  bool _ready = false;
  String? _error;
  bool _stopping = false;

  final http.Client _http = http.Client();

  bool get ready => _ready;
  String? get error => _error;

  int? get pid => _proc?.pid;

  static File? findBinary() {
    final nombre = 'metadata-sidecar$sufijoEjecutable';
    final candidatos = <File>[
      File(p.join(p.dirname(Platform.resolvedExecutable), nombre)),
      File(p.join(Directory.current.path, 'tool', 'metadata-sidecar', 'target',
          'release', nombre)),
      File(p.join(Directory.current.path, 'tool', 'metadata-sidecar', 'target',
          'debug', nombre)),
    ].where((f) => f.existsSync()).toList();
    if (candidatos.isEmpty) return null;
    candidatos.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return candidatos.first;
  }

  Future<void> start() async {
    if (_proc != null) return;
    _stopping = false;

    final bin = findBinary();
    if (bin == null) {
      _error = 'No se encuentra metadata-sidecar$sufijoEjecutable.';
      notifyListeners();
      return;
    }

    await matarHuerfano('metadata-sidecar', bin);

    try {
      final proc = await Process.start(bin.path, ['$puerto']);
      _proc = proc;
      anotarPid('metadata-sidecar', proc.pid);

      final listo = Completer<bool>();
      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.startsWith('READY') && !listo.isCompleted) listo.complete(true);
      });
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _error = line;
      });

      unawaited(proc.exitCode.then((code) {
        _proc = null;
        _ready = false;
        if (!_stopping) {
          _error ??= 'El sidecar de metadatos se cerró (código $code).';
        }
        if (!listo.isCompleted) listo.complete(false);
        notifyListeners();
      }));

      _ready = await listo.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (_ready) _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'No se pudo lanzar el sidecar de metadatos: $e';
      notifyListeners();
    }
  }

  Future<ApiPage<Track>> playlistItems(String id, {int offset = 0, int limit = 50}) async {
    if (!_ready) throw StateError('El sidecar de metadatos no está listo.');

    final j = await _getJson('/playlist/${idDeSpotify(id)}', query: {
      'offset': '$offset',
      'limit': '$limit',
    });
    final total = (j['total'] as num?)?.toInt() ?? 0;
    final items = ((j['items'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>?))
        .whereType<Track>()
        .toList();

    final consumidas = (total - offset).clamp(0, limit);
    return ApiPage(
      items: items,
      hasMore: offset + consumidas < total,
      rawCount: consumidas,
    );
  }

  Future<PerfilDeArtista> artista(String id) async {
    final locale = _localeEfectivo();
    final j = await _getJson('/artist/${idDeSpotify(id)}', query: {
      'locale': locale,
    });
    return PerfilDeArtista.desdeJson(j, locale: locale);
  }

  Future<List<Track>> albumTracks(String id) async {
    final j = await _getJson('/album/${idDeSpotify(id)}');
    final tracks = j['tracks'] as Map<String, dynamic>?;
    final raw = (tracks?['items'] as List<dynamic>?) ?? const [];
    return [
      for (final t in raw) Track.fromJson(t as Map<String, dynamic>?)
    ].whereType<Track>().toList();
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    if (!_ready) throw StateError('El sidecar de metadatos no está listo.');

    final uri = Uri.http('127.0.0.1:$puerto', path, query);
    final res = await _http.get(uri).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('El sidecar devolvió ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> stop() async {
    _stopping = true;
    final proc = _proc;
    _proc = null;
    _ready = false;
    if (proc != null) {
      proc.kill();
      await proc.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      olvidarPid('metadata-sidecar');
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}

class PerfilDeArtista {
  const PerfilDeArtista({
    required this.artista,
    this.top = const [],
    this.albumes = const [],
    this.singles = const [],
    this.apareceEn = const [],
    this.relacionados = const [],
  });

  final Artist artista;
  final List<Track> top;
  final List<Album> albumes;
  final List<Album> singles;
  final List<Album> apareceEn;
  final List<Artist> relacionados;

  static PerfilDeArtista desdeJson(Map<String, dynamic> j, {String? locale}) {
    final artista = Artist.fromJson(j, locale: locale) ??
        Artist(id: '', uri: '', name: '', art: null);
    return PerfilDeArtista(
      artista: artista,
      top: _pistas(j['top_tracks']),
      albumes: _albumes(j['albums']),
      singles: _albumes(j['singles']),
      apareceEn: _albumes(j['appears_on']),
      relacionados: [
        for (final raw in (j['related'] as List<dynamic>?) ?? const [])
          Artist.fromJson(raw as Map<String, dynamic>?)
      ].whereType<Artist>().where((a) => a.id.isNotEmpty).toList(),
    );
  }

  static List<Track> _pistas(Object? raw) => [
        for (final t in (raw as List<dynamic>?) ?? const [])
          Track.fromJson(t as Map<String, dynamic>?)
      ].whereType<Track>().toList();

  static List<Album> _albumes(Object? raw) => [
        for (final a in (raw as List<dynamic>?) ?? const [])
          Album.fromJson(a as Map<String, dynamic>?)
      ].whereType<Album>().toList();
}
