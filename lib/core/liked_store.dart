import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'auth.dart';
import 'models.dart';
import 'spotify_api.dart';

class LikedStore extends ChangeNotifier {
  LikedStore({
    required this.api,
    required this.auth,
    this.onReauth,
    Directory? directorio,
  }) : _directorio = directorio ?? appDataDir();

  final SpotifyApi api;
  final SpotifyAuth auth;

  final Future<void> Function()? onReauth;
  final Directory _directorio;

  static const _tamanoLote = 50;

  final Set<String> _guardadas = {};
  final Set<String> _conocidas = {};
  final Set<String> _porConsultar = {};

  final List<Track> biblioteca = [];

  bool _cargandoBiblioteca = false;
  bool _bibliotecaCompleta = false;
  int _offsetBiblioteca = 0;

  int? totalBiblioteca;
  String? errorBiblioteca;

  bool get cargandoBiblioteca => _cargandoBiblioteca;
  bool get bibliotecaCompleta => _bibliotecaCompleta;

  File get _fichero => File(p.join(_directorio.path, 'biblioteca.json'));

  Future<void>? _cargaDisco;
  Future<void>? _cargaUris;
  bool _urisCargadas = false;
  Timer? _guardarAplazado;

  bool get tieneUrisDeBiblioteca => _urisCargadas && _guardadas.isNotEmpty;
  Iterable<String> get urisGuardadas => _guardadas;

  Future<void> cargarUrisDesdeDisco() => _cargaUris ??= _leerUrisDisco();

  Future<void> _leerUrisDisco() async {
    try {
      final f = _fichero;
      if (!await f.exists()) return;
      final contenido = await f.readAsString();
      final parsed = contenido.length > 64 * 1024
          ? await Isolate.run(() => _extraerUrisBiblioteca(contenido))
          : _extraerUrisBiblioteca(contenido);
      if (parsed == null || parsed.uris.isEmpty || _disposed) return;
      _urisCargadas = true;
      totalBiblioteca ??= parsed.total ?? parsed.uris.length;
      seedSaved(parsed.uris);
    } catch (_) {
    }
  }

  Future<void> cargarDesdeDisco() => _cargaDisco ??= _leerDisco();

  Future<void> _leerDisco() async {
    try {
      final f = _fichero;
      if (!await f.exists()) return;
      final contenido = await f.readAsString();
      final parsed = contenido.length > 64 * 1024
          ? await Isolate.run(() => _decodificarBiblioteca(contenido))
          : _decodificarBiblioteca(contenido);
      if (parsed == null || parsed.pistas.isEmpty || _disposed) return;
      biblioteca
        ..clear()
        ..addAll(parsed.pistas);
      seedSaved(parsed.pistas.map((t) => t.uri));
      totalBiblioteca = parsed.total ?? parsed.pistas.length;
      _bibliotecaCompleta = true;
      _urisCargadas = _guardadas.isNotEmpty;
      if (!_disposed) notifyListeners();
    } catch (_) {
    }
  }

  void liberarMemoriaDeBiblioteca() {
    if (!_bibliotecaCompleta ||
        _cargandoBiblioteca ||
        _guardarAplazado != null) {
      return;
    }
    try {
      if (!_fichero.existsSync()) return;
    } catch (_) {
      return;
    }
    biblioteca.clear();
    _bibliotecaCompleta = false;
    _offsetBiblioteca = 0;
    _cargaDisco = null;
    _urisCargadas = _guardadas.isNotEmpty;
  }

  void _programarGuardado() {
    _guardarAplazado?.cancel();
    _guardarAplazado = Timer(const Duration(milliseconds: 400), () {
      _guardarAplazado = null;
      unawaited(_guardarEnDisco());
    });
  }

  Future<void> _guardarEnDisco() async {
    if (_disposed || !_bibliotecaCompleta) return;
    try {
      if (!await _directorio.exists()) {
        await _directorio.create(recursive: true);
      }
      await _fichero.writeAsString(jsonEncode({
        'total': totalBiblioteca ?? biblioteca.length,
        'pistas': [for (final t in biblioteca) t.aLocal()],
      }));
    } catch (_) {
    }
  }

  Future<void> cargarBiblioteca({bool forzar = false}) async {
    if (_cargandoBiblioteca) return;
    if (!forzar) {
      await cargarDesdeDisco();
      if (_bibliotecaCompleta) return;
    }
    if (forzar) {
      biblioteca.clear();
      _offsetBiblioteca = 0;
      _bibliotecaCompleta = false;
    }
    _cargandoBiblioteca = true;
    errorBiblioteca = null;
    notifyListeners();
    try {
      var quedan = true;
      while (quedan && !_disposed) {
        final page = await api.savedTracks(limit: 50, offset: _offsetBiblioteca);
        biblioteca.addAll(page.items);
        _offsetBiblioteca += page.rawCount;
        totalBiblioteca = page.total ?? totalBiblioteca;
        seedSaved(page.items.map((t) => t.uri));
        quedan = page.hasMore;
        if (!_disposed) notifyListeners();
      }
      if (!quedan) {
        _bibliotecaCompleta = true;
        await _guardarEnDisco();
      }
    } catch (e) {
      errorBiblioteca = '$e';
    } finally {
      _cargandoBiblioteca = false;
      if (!_disposed) notifyListeners();
    }
  }

  Timer? _agrupador;
  bool _consultando = false;
  bool _disposed = false;

  bool get canModify => auth.hasScope(kScopeLibraryModify);

  bool? isSaved(String uri) =>
      _conocidas.contains(uri) ? _guardadas.contains(uri) : null;

  void seedSaved(Iterable<String> uris) {
    var nuevas = false;
    for (final uri in uris) {
      if (_conocidas.add(uri)) nuevas = true;
      _guardadas.add(uri);
      _porConsultar.remove(uri);
    }
    if (nuevas) notifyListeners();
  }

  void ensureKnown(String uri) {
    if (uri.isEmpty || _conocidas.contains(uri) || _porConsultar.contains(uri)) {
      return;
    }
    _porConsultar.add(uri);
    _agrupador ??= Timer(const Duration(milliseconds: 120), _consultarPendientes);
  }

  Future<void> _consultarPendientes() async {
    _agrupador = null;
    if (_consultando || _disposed) return;
    _consultando = true;
    try {
      while (_porConsultar.isNotEmpty && !_disposed) {
        final lote = _porConsultar.take(_tamanoLote).toList();
        _porConsultar.removeAll(lote);
        try {
          final res = await api.savedContains(lote);
          for (var i = 0; i < lote.length && i < res.length; i++) {
            _conocidas.add(lote[i]);
            if (res[i]) {
              _guardadas.add(lote[i]);
            } else {
              _guardadas.remove(lote[i]);
            }
          }
          if (!_disposed) notifyListeners();
        } catch (_) {
        }
      }
    } finally {
      _consultando = false;
    }
  }

  Future<void> toggle(String uri, {Track? pista}) async {
    if (!canModify) {
      throw ApiException(403, 'Falta el permiso para editar tus favoritos.');
    }
    final estaba = isSaved(uri) ?? false;
    _actualizarBiblioteca(uri, guardada: !estaba, pista: pista);
    _aplicar(uri, !estaba);
    try {
      if (estaba) {
        await api.removeSavedTracks([uri]);
      } else {
        await api.saveTracks([uri]);
      }
      _programarGuardado();
    } catch (e) {
      _actualizarBiblioteca(uri, guardada: estaba, pista: pista);
      _aplicar(uri, estaba);
      rethrow;
    }
  }

  void _actualizarBiblioteca(String uri, {required bool guardada, Track? pista}) {
    if (!_bibliotecaCompleta && biblioteca.isEmpty) return;
    Track? existente;
    for (final t in biblioteca) {
      if (t.uri == uri) {
        existente = t;
        break;
      }
    }
    biblioteca.removeWhere((t) => t.uri == uri);
    if (guardada) {
      final t = pista ?? existente;
      if (t != null) biblioteca.insert(0, t);
    }
    totalBiblioteca = biblioteca.length;
  }

  void _aplicar(String uri, bool guardada) {
    _conocidas.add(uri);
    if (guardada) {
      _guardadas.add(uri);
    } else {
      _guardadas.remove(uri);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _agrupador?.cancel();
    _guardarAplazado?.cancel();
    super.dispose();
  }
}

({int? total, List<String> uris})? _extraerUrisBiblioteca(String contenido) {
  final map = jsonDecode(contenido);
  if (map is! Map<String, dynamic>) return null;
  final crudas = map['pistas'];
  if (crudas is! List) return null;
  final uris = <String>[
    for (final raw in crudas)
      if (raw is Map<String, dynamic> && raw['uri'] is String && (raw['uri'] as String).isNotEmpty)
        raw['uri'] as String,
  ];
  return (total: (map['total'] as num?)?.toInt(), uris: uris);
}

({int? total, List<Track> pistas})? _decodificarBiblioteca(String contenido) {
  final map = jsonDecode(contenido);
  if (map is! Map<String, dynamic>) return null;
  final crudas = map['pistas'];
  if (crudas is! List) return null;
  final pistas = <Track>[
    for (final raw in crudas)
      if (raw is Map<String, dynamic>) ?Track.desdeLocal(raw),
  ];
  return (total: (map['total'] as num?)?.toInt(), pistas: pistas);
}
