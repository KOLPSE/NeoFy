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

/// Busca versiones nuevas en las releases de GitHub y, en Windows, las instala.
///
/// El instalador ya sabe actualizar sobre una instalación existente: mata los
/// tres procesos, sobrescribe los ficheros y conserva `%APPDATA%\neofy` entera,
/// así que **no se pierde ni la sesión ni los ajustes**. Aquí solo hay que
/// bajarlo y lanzarlo.
///
/// ⚠️ **En Linux avisa pero no instala**, y no es una carencia sino lo
/// correcto: allí NeoFy se distribuye como paquete (`neofy-bin`, en su propio
/// repositorio) y es pacman quien lleva la cuenta de qué ficheros son de quién.
/// Una app que se
/// sobrescribe a sí misma por su cuenta deja la base de datos del gestor
/// mintiendo, y a la primera actualización del paquete se pisan los dos. Se
/// enseña que hay versión nueva y el comando con el que actualizarla.
class Updater extends ChangeNotifier {
  Updater({http.Client? cliente}) : _http = cliente ?? http.Client();

  final http.Client _http;

  /// De dónde se baja. Se comprueba el host antes de ejecutar nada: esto acaba
  /// lanzando un ejecutable, así que el origen no puede darse por bueno solo
  /// porque lo diga una respuesta JSON.
  static const _hostFiable = 'github.com';

  EstadoActualizacion estado = EstadoActualizacion.reposo;
  String? versionDisponible;
  String? notas;
  String? error;
  double progreso = 0;

  String? _urlDescarga;
  File? _instalador;

  String get versionActual => kVersion;

  /// ¿Puede esta plataforma instalarse la actualización ella sola?
  ///
  /// Solo Windows, donde la app se distribuye como instalador suelto. Ver el
  /// aviso de la clase.
  static bool get seInstalaSolo => Platform.isWindows;

  /// Qué hacer cuando no se instala sola. En Linux NeoFy se reparte por el
  /// repositorio pacman propio (ver el README), así que se actualiza con
  /// pacman a secas: nada de ayudantes del AUR, que ya no se usa.
  static const String comandoDeActualizacion = 'sudo pacman -Syu neofy-bin';

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
        // Un repositorio sin releases todavía no es un error que enseñar.
        _cambiar(EstadoActualizacion.alDia);
        return;
      }
      if (res.statusCode != 200) {
        throw 'GitHub respondió ${res.statusCode}';
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final etiqueta = (j['tag_name'] as String?) ?? '';
      final version = etiqueta.replaceFirst(RegExp('^v'), '');
      if (version.isEmpty) throw 'La release no tiene versión';

      if (!esMasNueva(version, kVersion)) {
        _cambiar(EstadoActualizacion.alDia);
        return;
      }

      versionDisponible = version;
      notas = j['body'] as String?;

      // En Linux se para aquí: hay novedad, se anuncia, y quien instala es el
      // gestor de paquetes. Buscar un asset sería además absurdo, porque el que
      // hay es el instalador de Windows.
      if (!seInstalaSolo) {
        _cambiar(EstadoActualizacion.disponible);
        return;
      }

      // El instalador es el único .exe de la release.
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

  /// Descarga el instalador enseñando el progreso.
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
      final bytes = <int>[];
      await for (final trozo in res.stream) {
        bytes.addAll(trozo);
        if (total > 0) {
          progreso = bytes.length / total;
          notifyListeners();
        }
      }

      final destino = File(p.join(
          Directory.systemTemp.path, 'NeoFy-$versionDisponible-setup.exe'));
      await destino.writeAsBytes(bytes, flush: true);
      _instalador = destino;
      _cambiar(EstadoActualizacion.listaParaInstalar);
    } catch (e) {
      error = '$e';
      _cambiar(EstadoActualizacion.fallo);
    }
  }

  /// Lanza el instalador y devuelve `true` si arrancó.
  ///
  /// Quien llame **debe cerrar la app justo después**: el instalador no puede
  /// sobrescribir un ejecutable en uso. Se lanza con `/SILENT` (barra de
  /// progreso, sin preguntas) y `/NOCANCEL` para que nadie lo deje a medias.
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

  /// Compara dos versiones tipo `1.2.3`.
  ///
  /// Se comparan los números por tramos y no como texto: `"0.10.0"` es más
  /// nueva que `"0.9.0"`, cosa que una comparación de cadenas diría al revés.
  static bool esMasNueva(String candidata, String actual) {
    List<int> tramos(String v) => v
        .split(RegExp(r'[.+-]'))
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
    notifyListeners();
  }
}
