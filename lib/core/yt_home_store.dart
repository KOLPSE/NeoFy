import 'package:flutter/foundation.dart';

import 'yt_models.dart';

/// Carga y guarda las secciones de una pantalla de NeoTube (portada, explorar
/// o biblioteca).
///
/// Recibe **cómo** cargar y no un `browseId`: la biblioteca no es un solo
/// `browseId` sino cuatro (playlists, álbumes, canciones y artistas viven en
/// endpoints distintos), y encajar eso en un campo de texto obligaba a poner
/// la excepción dentro del store. Con una función, cada pantalla trae la suya.
class YtHomeStore extends ChangeNotifier {
  YtHomeStore(this.cargarSecciones);

  final Future<List<YtSection>> Function() cargarSecciones;

  List<YtSection> secciones = const [];
  bool cargando = false;
  String? error;

  bool get vacio => secciones.isEmpty;

  Future<void> cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      secciones = await cargarSecciones();
    } catch (e) {
      error = '$e';
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Carga solo si no hay nada todavía: al volver a una pestaña ya vista no
  /// se repite el viaje.
  Future<void> cargarSiHaceFalta() async {
    if (secciones.isNotEmpty || cargando) return;
    await cargar();
  }
}
