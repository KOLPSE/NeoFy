import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';

class Carpeta {
  Carpeta({required this.id, required this.nombre, List<String>? playlistIds})
      : playlistIds = playlistIds ?? [];

  final String id;
  String nombre;
  final List<String> playlistIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'playlistIds': playlistIds,
      };

  static Carpeta? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final nombre = j['nombre'];
    if (id is! String || id.isEmpty || nombre is! String) return null;
    return Carpeta(
      id: id,
      nombre: nombre,
      playlistIds: [
        for (final s in (j['playlistIds'] as List<dynamic>?) ?? const [])
          if (s is String && s.isNotEmpty) s,
      ],
    );
  }
}

class CarpetasStore extends ChangeNotifier {
  CarpetasStore({Directory? directorio}) : _directorio = directorio ?? appDataDir();

  final Directory _directorio;
  final List<Carpeta> carpetas = [];

  File get _fichero => File(p.join(_directorio.path, 'carpetas.json'));

  Future<void> cargar() async {
    try {
      final f = _fichero;
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final raw in (map['carpetas'] as List<dynamic>?) ?? const []) {
        if (raw is Map<String, dynamic>) {
          final c = Carpeta.fromJson(raw);
          if (c != null) carpetas.add(c);
        }
      }
    } catch (_) {
      carpetas.clear();
    }
    notifyListeners();
  }

  Future<void> crearCarpeta(String nombre) async {
    carpetas.add(Carpeta(id: _nuevoId(), nombre: nombre));
    await _guardar();
  }

  Future<void> renombrarCarpeta(String id, String nombre) async {
    for (final c in carpetas) {
      if (c.id == id) {
        c.nombre = nombre;
        await _guardar();
        return;
      }
    }
  }

  Future<void> borrarCarpeta(String id) async {
    carpetas.removeWhere((c) => c.id == id);
    await _guardar();
  }

  Future<void> moverPlaylist(String playlistId, String? carpetaId) async {
    for (final c in carpetas) {
      c.playlistIds.remove(playlistId);
    }
    if (carpetaId != null) {
      for (final c in carpetas) {
        if (c.id == carpetaId) {
          c.playlistIds.remove(playlistId);
          c.playlistIds.add(playlistId);
          break;
        }
      }
    }
    await _guardar();
  }

  Future<void> quitarPlaylist(String playlistId) async {
    var tocada = false;
    for (final c in carpetas) {
      if (c.playlistIds.remove(playlistId)) tocada = true;
    }
    if (tocada) await _guardar();
  }

  Carpeta? carpetaDe(String playlistId) {
    for (final c in carpetas) {
      if (c.playlistIds.contains(playlistId)) return c;
    }
    return null;
  }

  Future<void> _guardar() async {
    try {
      await _fichero.writeAsString(jsonEncode({
        'carpetas': [for (final c in carpetas) c.toJson()],
      }));
    } catch (e) {
      debugPrint('No se pudo guardar carpetas.json: $e');
    }
    notifyListeners();
  }

  static final _random = Random();

  static String _nuevoId() =>
      'carpeta-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_random.nextInt(0xFFFFFF).toRadixString(36)}';
}
