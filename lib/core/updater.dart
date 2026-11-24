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
  Updater({
    http.Client? cliente,
    bool? instalaSolo,
    CanalActualizacion? canalInicial,
    String? versionActual,
  }) : _http = cliente ?? http.Client(),
       _httpPropio = cliente == null,
       _instalaSolo = instalaSolo ?? seInstalaSolo,
       _versionActual = versionActual ?? kVersion,
       _canal = canalInicial ?? canalDeVersion(versionActual ?? kVersion);

  final http.Client _http;
  final bool _httpPropio;
  final bool _instalaSolo;
  final String _versionActual;
  CanalActualizacion _canal;
  int _generacionBusqueda = 0;
  bool _disposed = false;

  static const _hostFiable = kHostActualizaciones;
  static final _rePrefijoV = RegExp('^v');
  static final _reSeparadorVersion = RegExp(r'[.+-]');

  /// URI de consulta de la última release en GitLab para [canal]. Se construye
  /// con `Uri.parse` porque `Uri.https` vuelve a escapar `%2F` como `%252F` y
  /// GitLab responde 404.
  static Uri uriUltimaReleasePara(CanalActualizacion canal) => Uri.parse(
        'https://$kHostActualizaciones/api/v4/projects/'
        '${Uri.encodeComponent(canal.proyecto)}'
        '/releases/permalink/latest',
      );

  static Uri get uriUltimaRelease =>
      uriUltimaReleasePara(CanalActualizacion.estable);

  static Uri get uriUltimaReleasePreview =>
      uriUltimaReleasePara(CanalActualizacion.preview);

  Uri get uriConsultaActual => uriUltimaReleasePara(_canal);

  EstadoActualizacion estado = EstadoActualizacion.reposo;
  String? versionDisponible;
  String? notas;
  String? error;
  double progreso = 0;

  String? _urlDescarga;
  File? _instalador;

  CanalActualizacion get canal => _canal;
  bool get instalaSolo => _instalaSolo;
  String get versionActual => _versionActual;
  CanalActualizacion get canalInstalado => canalDeVersion(_versionActual);
  bool get esCambioAEstable =>
      canalInstalado == CanalActualizacion.preview &&
      _canal == CanalActualizacion.estable;
  bool get ocupado =>
      estado == EstadoActualizacion.descargando ||
      estado == EstadoActualizacion.listaParaInstalar;

  static bool get seInstalaSolo => Platform.isWindows;

  Future<void> cambiarCanal(
    CanalActualizacion nuevo, {
    bool buscarAhora = true,
  }) async {
    if (nuevo == _canal || ocupado) return;
    _canal = nuevo;
    _generacionBusqueda++;
    versionDisponible = null;
    notas = null;
    error = null;
    _urlDescarga = null;
    _instalador = null;
    progreso = 0;
    _cambiar(EstadoActualizacion.reposo);
    if (buscarAhora) {
      await buscar(forzar: true);
    }
  }

  Future<void> buscar({bool forzar = false}) async {
    if (ocupado) return;
    if (!forzar && estado == EstadoActualizacion.buscando) return;

    final generacion = ++_generacionBusqueda;
    final canalConsulta = _canal;
    final uri = uriUltimaReleasePara(canalConsulta);
    versionDisponible = null;
    notas = null;
    _urlDescarga = null;
    _instalador = null;
    _cambiar(EstadoActualizacion.buscando);
    try {
      final res = await _http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));
      if (_disposed || generacion != _generacionBusqueda) return;

      if (res.statusCode == 404) {
        _cambiar(EstadoActualizacion.alDia);
        return;
      }
      if (res.statusCode != 200) {
        throw 'El servidor de actualizaciones respondió ${res.statusCode}';
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final etiqueta = (j['tag_name'] as String?) ?? '';
      final version = etiqueta.replaceFirst(_rePrefijoV, '');
      if (version.isEmpty) throw 'La release no tiene versión';

      final cambioAEstable =
          canalInstalado == CanalActualizacion.preview &&
          canalConsulta == CanalActualizacion.estable;
      final debeOfrecer = cambioAEstable
          ? version != _versionActual
          : esMasNueva(version, _versionActual);
      if (!debeOfrecer) {
        _cambiar(EstadoActualizacion.alDia);
        return;
      }

      versionDisponible = version;
      notas = j['description'] as String?;

      if (!_instalaSolo) {
        _cambiar(EstadoActualizacion.disponible);
        return;
      }

      final assets = j['assets'] as Map<String, dynamic>?;
      final enlaces = (assets?['links'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      final exe = enlaces.where((enlace) {
        final url = enlace['url'] as String?;
        final uri = url == null ? null : Uri.tryParse(url);
        return uri != null && uri.path.toLowerCase().endsWith('.exe');
      });
      if (exe.isEmpty) throw 'La release no trae instalador';

      final url = exe.first['url'] as String;
      final uriDescarga = Uri.tryParse(url);
      if (uriDescarga == null ||
          uriDescarga.scheme != 'https' ||
          uriDescarga.host != _hostFiable) {
        throw 'La descarga no viene de $_hostFiable';
      }

      _urlDescarga = url;
      _cambiar(EstadoActualizacion.disponible);
    } catch (e) {
      if (_disposed || generacion != _generacionBusqueda) return;
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
      final tipo = (res.headers['content-type'] ?? '').toLowerCase();
      if (tipo.startsWith('text/html')) {
        throw 'La descarga devolvió una página HTML en lugar del instalador';
      }

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
