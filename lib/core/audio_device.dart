import 'dart:async';

import 'package:flutter/services.dart';

/// Avisos de Windows cuando cambia el dispositivo de salida de audio.
///
/// librespot abre la salida **una vez**, al arrancar, y se queda con ella: si
/// después el usuario se pone unos cascos, los quita, o cambia el altavoz desde
/// la barra de tareas, el flujo se queda escribiendo en un sitio que ya no
/// suena. Nadie da error — Spotify sigue diciendo que la canción avanza — así
/// que el único síntoma es el silencio, y hasta ahora la única salida era matar
/// el proceso y reabrir la app.
///
/// Windows solo lo cuenta por COM (`IMMNotificationClient`), que necesita una
/// ventana y una cola de mensajes, así que el registro vive en el runner de C++
/// —igual que las teclas multimedia— y aquí solo se escucha el canal.
class AudioDeviceWatcher {
  AudioDeviceWatcher({required this.onCambio, this.espera = kEsperaPorDefecto});

  static const _channel = MethodChannel('neofy/audio_device');

  /// Un solo cambio de salida dispara varios avisos seguidos: enchufar unos
  /// cascos USB primero añade el dispositivo, luego lo pone por defecto y a
  /// veces vuelve a moverlo. Reiniciar el audio con el primero significaría
  /// reiniciarlo tres veces, y cada reinicio corta la música un segundo.
  static const kEsperaPorDefecto = Duration(milliseconds: 1200);

  final Future<void> Function() onCambio;
  final Duration espera;

  Timer? _pendiente;

  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'defaultDeviceChanged') _programar();
      return null;
    });
  }

  void _programar() {
    _pendiente?.cancel();
    _pendiente = Timer(espera, () => unawaited(onCambio()));
  }

  void stop() {
    _pendiente?.cancel();
    _pendiente = null;
    _channel.setMethodCallHandler(null);
  }
}
