import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

enum LibrespotStatus { stopped, starting, running, failed }

/// Arranca y vigila `librespot.exe`, que es quien reproduce el audio de verdad.
///
/// Spotify no deja que una app de terceros reproduzca por su API oficial sin un
/// navegador embebido, así que librespot implementa el protocolo de Spotify
/// Connect y convierte este equipo en un dispositivo más. Nosotros lo pilotamos
/// desde la Web API apuntando a su `device_id` — que es exactamente lo que hace
/// también un Stream Deck, y por eso los dos conviven sin tocarse.
class LibrespotManager extends ChangeNotifier {
  LibrespotManager(this.config);

  final AppConfig config;

  Process? _proc;
  LibrespotStatus _status = LibrespotStatus.stopped;
  String? _lastError;
  int _restartAttempts = 0;
  Timer? _restartTimer;
  DateTime? _startedAt;
  bool _stopping = false;

  /// Últimas líneas del log del proceso. Es lo único que tenemos para
  /// diagnosticar cuando librespot no arranca, así que se conserva un trozo.
  final List<String> logTail = [];

  LibrespotStatus get status => _status;
  String? get lastError => _lastError;

  /// Pid del proceso hijo, para poder medir su memoria. Cambia en cada
  /// reinicio del sidecar, así que hay que preguntarlo, no guardarlo.
  int? get pid => _proc?.pid;

  Directory get _cacheDir {
    final d = Directory(p.join(appDataDir().path, 'librespot'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// librespot guarda aquí el blob de sesión tras el login OAuth. Si existe,
  /// no hace falta volver a pasar por el navegador.
  bool get hasCredentials =>
      File(p.join(_cacheDir.path, 'credentials.json')).existsSync();

  /// Busca el binario junto al ejecutable (release) y, si no, en el árbol de
  /// desarrollo. Mismo patrón que usa NeoDrive para el icono de bandeja.
  static File? findBinary() {
    final candidates = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), 'librespot.exe'),
      p.join(Directory.current.path, 'tool', 'librespot-build', 'bin', 'librespot.exe'),
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }
    return null;
  }

  Future<void> _killOrphans() async {
    try {
      await Process.run('taskkill', ['/F', '/IM', 'librespot.exe']);
    } catch (_) {
      // Si no hay ninguno que matar, taskkill devuelve error: da igual.
    }
  }

  void _setStatus(LibrespotStatus s, {String? error}) {
    _status = s;
    _lastError = error;
    notifyListeners();
  }

  Future<void> start() async {
    if (_proc != null) return;
    _stopping = false;
    _restartTimer?.cancel();

    final bin = findBinary();
    if (bin == null) {
      _setStatus(LibrespotStatus.failed,
          error: 'No se encuentra librespot.exe. Ejecuta tool\\build_librespot.ps1.');
      return;
    }

    _setStatus(LibrespotStatus.starting);

    // Barrer instancias huérfanas antes de lanzar la nuestra. Si la app murió
    // de golpe (cuelgue, kill, corte de luz), su librespot sobrevive y se queda
    // sonando sin ventana que lo controle, además de ocupar el nombre del
    // dispositivo en Spotify Connect. El cierre ordenado ya lo mata; esto cubre
    // el que no lo fue. Es seguro: la app es de instancia única, así que ningún
    // librespot vivo en este punto es nuestro.
    await _killOrphans();

    final args = <String>[
      '--name', kDeviceName,
      '--device-type', 'computer',
      '--bitrate', '${config.bitrate}',
      '--backend', 'rodio',
      '--system-cache', _cacheDir.path,
      '--cache', p.join(_cacheDir.path, 'audio'),
      // Sin tope, la caché de audio crece indefinidamente.
      '--cache-size-limit', '1G',
      '--initial-volume', '${config.initialVolume}',
      // El descubrimiento por mDNS sobra: no queremos que otros equipos de la
      // red se conecten a este reproductor, y nos ahorra abrir un puerto.
      '--disable-discovery',
      // Sin credenciales cacheadas hay que pasar por el navegador una vez.
      // librespot usa el client_id del cliente de escritorio de Spotify, por
      // eso es un login aparte del nuestro y no se pueden compartir tokens.
      if (!hasCredentials) ...['--enable-oauth', '--oauth-port', '$kLibrespotOAuthPort'],
    ];

    try {
      final proc = await Process.start(bin.path, args);
      _proc = proc;
      _startedAt = DateTime.now();

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);

      unawaited(proc.exitCode.then(_onExit));
      _setStatus(LibrespotStatus.running);
    } catch (e) {
      _setStatus(LibrespotStatus.failed, error: 'No se pudo lanzar librespot: $e');
    }
  }

  void _onLogLine(String line) {
    logTail.add(line);
    if (logTail.length > 200) logTail.removeAt(0);

    // Durante el login, librespot escribe la URL de autorización en el log en
    // vez de abrir el navegador. La abrimos nosotros para que el usuario no
    // tenga que ir a buscarla.
    final match = RegExp(r'https://accounts\.spotify\.com/\S+').firstMatch(line);
    if (match != null) {
      final url = Uri.tryParse(match.group(0)!);
      if (url != null) unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
    }
  }

  Future<void> _onExit(int code) async {
    _proc = null;
    if (_stopping) {
      _setStatus(LibrespotStatus.stopped);
      return;
    }

    // Si aguantó un rato, la caída es puntual (típicamente un corte de red) y
    // el contador de intentos vuelve a cero. Si murió nada más arrancar, es un
    // fallo real y conviene espaciar los reintentos.
    final ranFor = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    if (ranFor > const Duration(minutes: 1)) _restartAttempts = 0;

    if (_restartAttempts >= 5) {
      _setStatus(LibrespotStatus.failed,
          error: 'librespot no arranca (código $code). Últimas líneas:\n'
              '${logTail.takeLast(6).join('\n')}');
      return;
    }

    final delay = Duration(seconds: 1 << _restartAttempts); // 1,2,4,8,16 s
    _restartAttempts++;
    _setStatus(LibrespotStatus.starting,
        error: 'librespot se cerró (código $code); reintentando en ${delay.inSeconds} s.');
    _restartTimer = Timer(delay, start);
  }

  Future<void> stop() async {
    _stopping = true;
    _restartTimer?.cancel();
    final proc = _proc;
    _proc = null;
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      // En Windows sigterm sobre un proceso de consola no siempre cuaja; si a
      // los dos segundos sigue vivo, se mata sin contemplaciones para no dejar
      // un librespot.exe huérfano sonando de fondo.
      await proc.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    _setStatus(LibrespotStatus.stopped);
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    unawaited(stop());
    super.dispose();
  }
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int n) => skip(length > n ? length - n : 0);
}
