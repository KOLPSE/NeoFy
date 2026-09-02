import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'models.dart';

class ArtistasFavoritosStore extends ChangeNotifier {
  ArtistasFavoritosStore({Directory? directorio})
      : _directorio = directorio ?? appDataDir();

  final Directory _directorio;
  final List<Artist> artistas = [];

  bool _disposed = false;

  File get _fichero =>
      File(p.join(_directorio.path, 'artistas_favoritos.json'));

  bool esFavorito(String id) {
    for (final a in artistas) {
      if (a.id == id) return true;
    }
    return false;
  }

  Future<void> cargar() async {
    try {
      final f = _fichero;
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString());
      if (map is! Map<String, dynamic>) return;
      artistas.clear();
      for (final raw in (map['artistas'] as List<dynamic>?) ?? const []) {
        if (raw is Map<String, dynamic>) {
          final a = Artist.desdeLocal(raw);
          if (a != null && a.id.isNotEmpty) artistas.add(a);
        }
      }
    } catch (_) {
      artistas.clear();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle(Artist artista) async {
    if (artista.id.isEmpty) return;
    final i = artistas.indexWhere((a) => a.id == artista.id);
    if (i >= 0) {
      artistas.removeAt(i);
    } else {
      artistas.insert(0, artista);
    }
    if (!_disposed) notifyListeners();
    await _guardar();
  }

  Future<void> _guardar() async {
    try {
      if (!await _directorio.exists()) {
        await _directorio.create(recursive: true);
      }
      await _fichero.writeAsString(jsonEncode({
        'artistas': [for (final a in artistas) a.aLocal()],
      }));
    } catch (_) {
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
