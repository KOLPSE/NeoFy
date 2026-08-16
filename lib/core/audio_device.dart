import 'dart:async';

import 'package:flutter/services.dart';

class AudioDeviceWatcher {
  AudioDeviceWatcher({required this.onCambio, this.espera = kEsperaPorDefecto});

  static const _channel = MethodChannel('neofy/audio_device');

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
