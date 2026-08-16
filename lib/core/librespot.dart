import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'procesos.dart';

enum LibrespotStatus { stopped, starting, running, failed }

bool esFalloDeAudio(String linea) {
  if (!linea.contains('ERROR')) return false;
  final l = linea.toLowerCase();
  return l.contains('audio sink') ||
      l.contains('audiosink') ||
      l.contains('rodio') ||
      l.contains('cpal') ||
      l.contains('pulseaudio') ||
      l.contains('alsa') ||
      l.contains('audio backend') ||
      l.contains('output device');
}

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
  bool _reiniciando = false;

  void Function(String linea)? onFalloDeAudio;

  final List<String> logTail = [];

  LibrespotStatus get status => _status;
  String? get lastError => _lastError;

  int? get pid => _proc?.pid;

  Directory get _credencialesDir {
    final d = Directory(p.join(appDataDir().path, 'librespot'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  bool get hasCredentials =>
      File(p.join(_credencialesDir.path, 'credentials.json')).existsSync();

  static File? findBinary() {
    final nombre = 'librespot$sufijoEjecutable';
    final candidates = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), nombre),
      p.join(Directory.current.path, 'tool', 'librespot-build', 'bin', nombre),
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }
    return null;
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
          error: Platform.isWindows
              ? 'No se encuentra librespot.exe. Ejecuta tool\\build_librespot.ps1.'
              : 'No se encuentra librespot. Ejecuta tool/build_sidecars.sh.');
      return;
    }

    _setStatus(LibrespotStatus.starting);

    await matarHuerfano('librespot', bin);

    final args = <String>[
      '--name', kDeviceName,
      '--device-type', 'computer',
      '--bitrate', '${config.bitrate}',
      '--backend', Platform.isWindows ? 'rodio' : 'pulseaudio',
      '--system-cache', _credencialesDir.path,
      '--cache', p.join(cacheDir().path, 'audio'),
      '--cache-size-limit', '1G',
      '--initial-volume', '${config.initialVolume}',
      '--disable-discovery',
      if (!hasCredentials) ...['--enable-oauth', '--oauth-port', '$kLibrespotOAuthPort'],
    ];

    try {
      final proc = await Process.start(bin.path, args);
      _proc = proc;
      _startedAt = DateTime.now();
      anotarPid('librespot', proc.pid);

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);

      unawaited(proc.exitCode.then((code) => _onExit(proc, code)));
      _setStatus(LibrespotStatus.running);
    } catch (e) {
      _setStatus(LibrespotStatus.failed, error: 'No se pudo lanzar librespot: $e');
    }
  }

  Future<void> reiniciar() async {
    if (_reiniciando) return;
    _reiniciando = true;
    try {
      await stop();
      _restartAttempts = 0;
      await start();
    } finally {
      _reiniciando = false;
    }
  }

  void _onLogLine(String line) {
    logTail.add(line);
    if (logTail.length > 200) logTail.removeAt(0);

    if (esFalloDeAudio(line)) onFalloDeAudio?.call(line);

    final match = RegExp(r'https://accounts\.spotify\.com/\S+').firstMatch(line);
    if (match != null) {
      final url = Uri.tryParse(match.group(0)!);
      if (url != null) unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
    }
  }

  Future<void> _onExit(Process proc, int code) async {
    if (_proc != null && !identical(_proc, proc)) return;
    _proc = null;
    if (_stopping) {
      _setStatus(LibrespotStatus.stopped);
      return;
    }

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

    final delay = Duration(seconds: 1 << _restartAttempts);
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
      await proc.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      });
      olvidarPid('librespot');
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
