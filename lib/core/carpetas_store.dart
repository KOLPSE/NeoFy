import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';

/// Una carpeta de playlists.
///
/// La Web API de Spotify **no expone carpetas** — el cliente oficial las guarda
/// en su cuenta, pero no hay endpoint para crearlas, leerlas ni moverlas. Así
/// que esto es puramente local: un id generado aquí (no vale ningún id de
/// Spotify), un nombre y la lista **ordenada** de ids de playlist que contiene.
/// ¿La playlist que guarda? Esa sigue viviendo en la cuenta y se lee de la API
/// como siempre; aquí solo se apunta su id.
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

  /// Acepta solo carpetas bien formadas: una entrada con id o nombre que no son
  /// cadenas no es una carpeta (un id desaparecido, un campo reescrito a mano),
  /// y descartarla entera es más seguro que adivinar.
  ///
  /// Se comprueba con `is String` y no con un `as String?`: un cast sobre un
  /// valor del tipo equivocado **lanza**, y una sola entrada malformada no
  /// debería poder tirar la carga entera.
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

/// Dónde vive la estructura de carpetas de la sesión.
///
/// Se guarda en `carpetas.json` dentro de [appDataDir] y **no** dentro de
/// `config.json`: `AppConfig.save()` reescribe ese fichero entero, y mezclar los
/// dos en uno acabaría por perder la mitad al primer guardado.
///
/// El store cuelga de `main.dart` y sobrevive a la navegación por el mismo
/// motivo que LikedStore y HomeStore: `_content()` de `shell.dart` construye
/// solo la vista activa y destruye el State al salir, así que el estado de las
/// carpetas no puede vivir dentro de una pantalla (ver la sección "Los stores
/// existen por la navegación" de ARQUITECTURA.md).
///
/// Las playlists en sí se siguen paginando de 50 en 50 en `shell.dart`; este
/// store jamás llama a la Web API.
class CarpetasStore extends ChangeNotifier {
  CarpetasStore({Directory? directorio}) : _directorio = directorio ?? appDataDir();

  final Directory _directorio;
  final List<Carpeta> carpetas = [];

  File get _fichero => File(p.join(_directorio.path, 'carpetas.json'));

  /// Carga la estructura desde disco. Un fichero corrupto o ausente no puede
  /// impedir arrancar: se cae a "sin carpetas", igual que hace
  /// `AppConfig.load()` con un `config.json` roto.
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
      // JSON roto: se empieza sin carpetas y la primera escritura lo repara.
      carpetas.clear();
    }
    notifyListeners();
  }

  /// Crea una carpeta con un id propio: Spotify no puede asignárnoslo.
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

  /// Borrar la carpeta no toca ninguna playlist: solo desaparece la estructura,
  /// y sus playlists vuelven a estar sueltas en la lista.
  Future<void> borrarCarpeta(String id) async {
    carpetas.removeWhere((c) => c.id == id);
    await _guardar();
  }

  /// Mueve una playlist a una carpeta, o la deja suelta si [carpetaId] es null.
  ///
  /// Una playlist solo puede estar en una carpeta (como en el cliente oficial),
  /// así que moverla la saca de la que estuviera antes. La id de una carpeta
  /// que ya no existe se ignora: la playlist queda suelta y nadie se rompe.
  Future<void> moverPlaylist(String playlistId, String? carpetaId) async {
    for (final c in carpetas) {
      c.playlistIds.remove(playlistId);
    }
    if (carpetaId != null) {
      for (final c in carpetas) {
        if (c.id == carpetaId) {
          // Al final y sin repetir: mover algo que ya está dentro no lo duplica,
          // solo lo reordena al fondo.
          c.playlistIds.remove(playlistId);
          c.playlistIds.add(playlistId);
          break;
        }
      }
    }
    await _guardar();
  }

  /// Quita una playlist de todas las carpetas. Lo usa el borrado de la
  /// biblioteca: si la playlist ya no existe en la cuenta, dejarla apuntada
  /// solo ensuciaría el fichero.
  Future<void> quitarPlaylist(String playlistId) async {
    var tocada = false;
    for (final c in carpetas) {
      if (c.playlistIds.remove(playlistId)) tocada = true;
    }
    if (tocada) await _guardar();
  }

  /// La carpeta que contiene esta playlist, si está en alguna. Sirve para
  /// marcar con una palomita cuál es la actual en el diálogo de mover.
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
      // Fallar al escribir no debe romper la sesión: las carpetas siguen en
      // memoria, solo se pierden al cerrar la app. Mejor eso que una excepción
      // en un menú.
      debugPrint('No se pudo guardar carpetas.json: $e');
    }
    notifyListeners();
  }

  static final _random = Random();

  /// Un id local único y con prefijo reconocible (nunca colisiona con un id de
  /// Spotify, y un JSON que mezcle los dos se lee sin ambigüedad).
  static String _nuevoId() =>
      'carpeta-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_random.nextInt(0xFFFFFF).toRadixString(36)}';
}