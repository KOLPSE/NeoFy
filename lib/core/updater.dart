import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_config.dart';

enum EstadoActualizacion {
  reposo,
  buscando,
  alDia,
  disponible,
  descargando,
  listaParaInstalar,
  fallo,
}

class Updater extends ChangeNotifier {
  Updater({http.Client? cliente})
      : _http = cliente ?? http.Client(),
        _httpPropio = cliente == null;

  final http.Client _http;
  final bool _httpPropio;
  bool _disposed = false;

  static const _hostFiable = 'github.com';
  static final _rePrefijoV = RegExp('^v');
  static final _reSeparadorVersion = RegExp(r'[.+-]');

  EstadoActualizacion estado = EstadoActualizacion.reposo;
  String? versionDisponible;
  String? notas;
  String? error;
  double progreso = 0;

  String? _urlDescarga;
  File? _instalador;

  String get versionActual => kVersion;

  static bool get seInstalaSolo => Platform.isWindows;

  Future<void> buscar() async {
    if (estado == EstadoActualizacion.buscando ||
        estado == EstadoActualizacion.descargando) {
      return;
    }
    _cambiar(EstadoActualizacion.buscando);
    try {
      final res = await _http.get(
        Uri.https('api.github.com', '/repos/$kRepoGitHub/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 404) {
        _cambiar(EstadoActualizacion.alDia);
        return;
      }
      if (res.statusCode != 200) {
        throw 'GitHub respondió ${res.statusCode}';
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final etiqueta = (j['tag_name'] as String?) ?? '';
      final version = etiqueta.replaceFirst(_rePrefijoV, '');
      if (version.isEmpty) throw 'La release no tiene versión';

      if (!esMasNueva(version, kVersion)) {
        _cambiar(EstadoActualizacion.alDia);
        return;
      }

      versionDisponible = version;
      notas = j['body'] as String?;

      if (!seInstalaSolo) {
        _cambiar(EstadoActualizacion.disponible);
        return;
      }

      final assets = (j['assets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      final exe = assets.where((a) => (a['name'] as String? ?? '').endsWith('.exe'));
      if (exe.isEmpty) throw 'La release no trae instalador';

      final url = exe.first['browser_download_url'] as String;
      if (Uri.parse(url).host != _hostFiable) {
        throw 'La descarga no viene de $_hostFiable';
      }

      _urlDescarga = url;
      _cambiar(EstadoActualizacion.disponible);
    } catch (e) {
      error = '$e';
      _cambiar(EstadoActualizacion.fallo);
    }
  }

  Future<void> descargar() async {
    final url = _urlDescarga;
    if (url == null) return;
    progreso = 0;
    _cambiar(EstadoActualizacion.descargando);
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await _http.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw 'La descarga falló (${res.statusCode})';

      final total = res.contentLength ?? 0;
      final destino = File(p.join(
          Directory.systemTemp.path, 'NeoFy-$versionDisponible-setup.exe'));
      final temporal = File('${destino.path}.part');
      final sink = temporal.openWrite();
      var recibidos = 0;
      var ultimoNotificado = -1.0;
      try {
        await for (final trozo in res.stream) {
          sink.add(trozo);
          recibidos += trozo.length;
          if (total > 0) {
            progreso = (recibidos / total).clamp(0.0, 1.0);
            if (!_disposed &&
                (progreso - ultimoNotificado >= 0.01 || progreso >= 1.0)) {
              ultimoNotificado = progreso;
              notifyListeners();
            }
          }
        }
        await sink.flush();
      } catch (_) {
        await sink.close();
        if (await temporal.exists()) {
          await temporal.delete().catchError((_) => temporal);
        }
        rethrow;
      }
      await sink.close();
      if (await destino.exists()) {
        await destino.delete().catchError((_) => destino);
      }
      await temporal.rename(destino.path);
      _instalador = destino;
      _cambiar(EstadoActualizacion.listaParaInstalar);
    } catch (e) {
      error = '$e';
      _cambiar(EstadoActualizacion.fallo);
    }
  }

  Future<bool> instalar() async {
    final exe = _instalador;
    if (exe == null || !exe.existsSync()) return false;
    try {
      await Process.start(
        exe.path,
        ['/SILENT', '/NOCANCEL', '/NORESTART'],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      error = '$e';
      _cambiar(EstadoActualizacion.fallo);
      return false;
    }
  }

  static bool esMasNueva(String candidata, String actual) {
    List<int> tramos(String v) => v
        .split(_reSeparadorVersion)
        .map((t) => int.tryParse(t) ?? 0)
        .toList();
    final a = tramos(candidata);
    final b = tramos(actual);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  void _cambiar(EstadoActualizacion nuevo) {
    estado = nuevo;
    if (nuevo != EstadoActualizacion.fallo) error = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_httpPropio) _http.close();
    super.dispose();
  }
}
