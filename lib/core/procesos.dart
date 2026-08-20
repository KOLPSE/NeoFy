import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config.dart';

final String sufijoEjecutable = Platform.isWindows ? '.exe' : '';

final String _nul = String.fromCharCode(0);

Directory _dirDePids() {
  final base = Platform.environment['XDG_RUNTIME_DIR'];
  final dir = Directory(base != null && base.isNotEmpty && p.isAbsolute(base)
      ? p.join(base, 'neofy')
      : p.join(cacheDir().path, 'run'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

File _ficheroDePid(String nombre) =>
    File(p.join(_dirDePids().path, '$nombre.pid'));

void anotarPid(String nombre, int pid) {
  if (Platform.isWindows) return;
  try {
    _ficheroDePid(nombre).writeAsStringSync('$pid');
  } catch (_) {
  }
}

void olvidarPid(String nombre) {
  if (Platform.isWindows) return;
  try {
    final f = _ficheroDePid(nombre);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

Future<void> matarHuerfano(String nombre, File? binario) async {
  if (Platform.isWindows) {
    try {
      await Process.run('taskkill', ['/F', '/IM', '$nombre.exe']);
    } catch (_) {
    }
    return;
  }

  final fichero = _ficheroDePid(nombre);
  if (!fichero.existsSync()) return;

  int? pid;
  try {
    pid = int.tryParse(fichero.readAsStringSync().trim());
  } catch (_) {}
  try {
    fichero.deleteSync();
  } catch (_) {}
  if (pid == null || pid <= 0) return;

  if (!_esNuestro(pid, nombre, binario)) return;

  Process.killPid(pid, ProcessSignal.sigterm);
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!Directory('/proc/$pid').existsSync()) return;
  }
  Process.killPid(pid, ProcessSignal.sigkill);
}

bool _esNuestro(int pid, String nombre, File? binario) {
  try {
    final cmdline = File('/proc/$pid/cmdline').readAsStringSync();
    final argv0 = cmdline.split(_nul).first;
    if (argv0.isEmpty) return false;
    if (binario != null) return argv0 == binario.path;
    return p.basename(argv0) == nombre;
  } catch (_) {
    return false;
  }
}
