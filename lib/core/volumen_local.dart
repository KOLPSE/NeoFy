import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel kCanalVolumenSesion = MethodChannel('neofy/volumen_sesion');

/// El volumen de Connect tarda 1–2 s en oírse: va a los servidores de Spotify
/// y vuelve. El mixer de librespot se deja fijo al 100 % y esto mueve la
/// sesión de audio del proceso, que es instantáneo.
class VolumenLocal {
  VolumenLocal({
    MethodChannel? canal,
    this._pactl,
  }) : _canal = canal ?? kCanalVolumenSesion;

  final MethodChannel _canal;
  final Future<String> Function(List<String> args)? _pactl;

  Future<bool> aplicar(int percent) async {
    final nivel = percent.clamp(0, 100);
    try {
      if (Platform.isWindows) {
        final ok = await _canal.invokeMethod<bool>('set', {'percent': nivel});
        return ok == true;
      }
      if (Platform.isLinux) {
        return _aplicarPulse(nivel);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<bool> _aplicarPulse(int percent) async {
    final listar = _pactl ?? _pactlReal;
    final listado = await listar(['list', 'sink-inputs']);
    final entradas = entradasDeLibrespot(listado);
    if (entradas.isEmpty) return false;
    for (final id in entradas) {
      await listar(['set-sink-input-volume', id, '$percent%']);
    }
    return true;
  }

  static Future<String> _pactlReal(List<String> args) async {
    final r = await Process.run('pactl', args);
    if (r.exitCode != 0) return '';
    return r.stdout as String? ?? '';
  }
}

/// Ids de sink-input cuyo proceso es librespot. El formato es el de
/// `pactl list sink-inputs`, no el JSON: PipeWire a veces no lo da.
List<String> entradasDeLibrespot(String listado) {
  final ids = <String>[];
  String? actual;
  var esLibrespot = false;

  void cerrar() {
    if (actual != null && esLibrespot) ids.add(actual!);
    actual = null;
    esLibrespot = false;
  }

  for (final cruda in listado.split('\n')) {
    final linea = cruda.trim();
    final cabecera = RegExp(r'^Sink Input #(\d+)').firstMatch(linea);
    if (cabecera != null) {
      cerrar();
      actual = cabecera.group(1);
      continue;
    }
    if (actual == null) continue;
    final bajo = linea.toLowerCase();
    if (bajo.contains('application.process.binary') ||
        bajo.contains('application.name') ||
        bajo.contains('application.process.id')) {
      if (bajo.contains('librespot')) esLibrespot = true;
    }
  }
  cerrar();
  return ids;
}
