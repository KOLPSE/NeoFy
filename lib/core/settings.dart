import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'app_config.dart';

final ValueNotifier<bool> modoRendimiento = ValueNotifier(false);

class Settings extends ChangeNotifier {
  Settings(this.config) {
    modoRendimiento.value = config.performanceMode;
    _aplicar();
  }

  final AppConfig config;

  void Function(bool activo)? onCambioDeModo;

  void Function(bool activo, String clientId)? onCambioDiscord;

  bool get performanceMode => modoRendimiento.value;
  bool get discordRpcEnabled => config.discordRpcEnabled;
  String get discordClientId => config.discordClientId;

  Future<void> setPerformanceMode(bool activo) async {
    if (modoRendimiento.value == activo) return;
    modoRendimiento.value = activo;
    config.performanceMode = activo;
    _aplicar();
    onCambioDeModo?.call(activo);
    notifyListeners();
    await config.save();
  }

  Future<void> setDiscordRpcEnabled(bool activo) async {
    if (config.discordRpcEnabled == activo) return;
    config.discordRpcEnabled = activo;
    onCambioDiscord?.call(activo, config.discordClientId);
    notifyListeners();
    await config.save();
  }

  Future<void> setDiscordClientId(String id) async {
    final recortado = id.trim();
    if (config.discordClientId == recortado) return;
    config.discordClientId = recortado;
    onCambioDiscord?.call(config.discordRpcEnabled, recortado);
    notifyListeners();
    await config.save();
  }

  void _aplicar() {
    final cache = PaintingBinding.instance.imageCache;
    if (modoRendimiento.value) {
      cache.clear();
      cache.clearLiveImages();
      cache.maximumSizeBytes = 1 << 20;
      cache.maximumSize = 20;
    } else {
      cache.maximumSizeBytes = 8 << 20;
      cache.maximumSize = 120;
    }
  }
}
