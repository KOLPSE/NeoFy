import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'app_config.dart';
import 'app_mode.dart';

/// ¿Está encendido el modo rendimiento?
///
/// Es un notificador suelto y no un campo de `Settings` porque quien más lo
/// consulta es `ArtImage`, que aparece en cada fila de cada lista: pasarle el
/// objeto de ajustes por el árbol de widgets obligaría a tocar todas las
/// pantallas para acarrear un booleano. Lo escribe únicamente [Settings].
final ValueNotifier<bool> modoRendimiento = ValueNotifier(false);

/// El modo activo de la app: NeoFy o NeoTube. Mismo motivo que
/// [modoRendimiento] para ser un notificador suelto: `MaterialApp` y el
/// interruptor del sidebar lo necesitan por fuera del árbol de `Settings`.
/// Lo escribe únicamente [Settings].
final ValueNotifier<AppMode> modoApp = ValueNotifier(AppMode.neofy);

/// Preferencias que el usuario puede tocar en caliente.
///
/// ## Modo rendimiento
///
/// La memoria de esta app se va casi entera en dos sitios: el motor de Flutter
/// (que no se puede tocar) y las carátulas. El modo rendimiento ataca lo
/// segundo hasta el final:
///
/// - **No se baja ni una imagen.** Cada carátula se sustituye por un mosaico de
///   color generado a partir de su propia URL, así que cada disco tiene siempre
///   el mismo color y la lista sigue leyéndose bien. Cuesta cero bytes.
/// - **La caché de imágenes se vacía y se deja casi a cero.**
/// - **Se apaga el sidecar de metadatos**, que son ~13 MB y solo sirve de plan B
///   para leer playlists ajenas.
///
/// Lo que **no** toca, por encargo: el audio. librespot sigue igual, con el
/// mismo bitrate y la misma caché.
class Settings extends ChangeNotifier {
  Settings(this.config) {
    modoRendimiento.value = config.performanceMode;
    modoApp.value = AppMode.fromNombre(config.modo);
    _aplicar();
  }

  final AppConfig config;

  /// Se invoca al cambiar de modo para que quien tenga procesos que arrancar o
  /// parar (el sidecar de metadatos) reaccione, y para poder devolverle al
  /// sistema la memoria que se acaba de soltar.
  void Function(bool activo)? onCambioDeModo;

  bool get performanceMode => modoRendimiento.value;

  Future<void> setPerformanceMode(bool activo) async {
    if (modoRendimiento.value == activo) return;
    modoRendimiento.value = activo;
    config.performanceMode = activo;
    _aplicar();
    onCambioDeModo?.call(activo);
    notifyListeners();
    await config.save();
  }

  AppMode get modo => modoApp.value;

  Future<void> setModo(AppMode m) async {
    if (modoApp.value == m) return;
    modoApp.value = m;
    config.modo = m.nombre;
    notifyListeners();
    await config.save();
  }

  /// Ajusta el techo de la caché de bitmaps y tira lo que hubiera dentro.
  ///
  /// Al encender el modo no basta con dejar de pedir imágenes nuevas: las que
  /// ya estaban decodificadas seguirían ocupando megas hasta que el LRU las
  /// fuera echando.
  void _aplicar() {
    final cache = PaintingBinding.instance.imageCache;
    if (modoRendimiento.value) {
      cache.clear();
      cache.clearLiveImages();
      // No se deja en cero: `maximumSize` a 0 desactiva la caché por completo y
      // hace que cualquier imagen que quedara se redecodifique en cada frame.
      cache.maximumSizeBytes = 1 << 20; // 1 MB
      cache.maximumSize = 20;
    } else {
      // 8 MB siguen sobrando de largo: una miniatura de fila decodificada a
      // 40 px ocupa unos 14 KB, o sea que caben quinientas.
      cache.maximumSizeBytes = 8 << 20;
      cache.maximumSize = 120;
    }
  }
}
