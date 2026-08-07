import 'package:flutter/services.dart';

/// Teclas multimedia del sistema: las del teclado y **el botón de los cascos**.
///
/// Unos auriculares con botón de play/pausa mandan exactamente la misma tecla
/// que el teclado multimedia (`VK_MEDIA_PLAY_PAUSE`), así que no hay que
/// distinguirlos. Lo que sí hace falta es que llegue con la app en segundo
/// plano, y eso solo se consigue con `RegisterHotKey`, que necesita un HWND y
/// una cola de mensajes de Windows.
///
/// Por eso el registro está en el runner de C++ (`windows/runner/`) y aquí solo
/// se escucha el canal. Se hizo así en vez de con un paquete: el único
/// candidato le pasaba a `RegisterHotKey` el código HID de Flutter en lugar del
/// virtual-key de Windows, y traía ocho dependencias transitivas para algo que
/// el runner ya sabe hacer en sesenta líneas.
class MediaKeys {
  MediaKeys({
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onPause,
  });

  static const _channel = MethodChannel('neofy/media_keys');

  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onPause;

  void start() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          await onPlayPause();
        case 'next':
          await onNext();
        case 'previous':
          await onPrevious();
        case 'pause':
          await onPause();
      }
      return null;
    });
  }

  void stop() => _channel.setMethodCallHandler(null);
}
