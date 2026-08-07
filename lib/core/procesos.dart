import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config.dart';

/// Lo que hay que saber del sistema para lanzar y matar los dos sidecars.
///
/// Existe porque `librespot` y `metadata-sidecar` necesitan exactamente el
/// mismo tratamiento y las dos plataformas lo resuelven de forma distinta.

/// Sufijo de los ejecutables: `.exe` en Windows, nada en Linux.
final String sufijoEjecutable = Platform.isWindows ? '.exe' : '';

/// El separador de `/proc/<pid>/cmdline`, que va por NUL y no por espacios.
///
/// Se construye en vez de escribirlo como escape en un literal para que no
/// quede un byte cero suelto en el código fuente.
final String _nul = String.fromCharCode(0);

/// Dónde se anotan los pids de los sidecars.
///
/// En Linux, `XDG_RUNTIME_DIR` es tmpfs y el sistema lo vacía al cerrar sesión:
/// es justo donde va un fichero de pid, porque así no sobrevive a un reinicio
/// (un pid de la sesión anterior no significa nada). Si no está definida, vale
/// la caché.
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

/// Anota el pid de un sidecar recién lanzado, para poder barrerlo si la app
/// muere de golpe y no llega a matarlo por las buenas.
void anotarPid(String nombre, int pid) {
  if (Platform.isWindows) return;
  try {
    _ficheroDePid(nombre).writeAsStringSync('$pid');
  } catch (_) {
    // Sin el fichero solo se pierde el barrido de huérfanos, que ya es el plan
    // B. No es motivo para no arrancar el sidecar.
  }
}

/// Borra la anotación tras un cierre ordenado, para que el siguiente arranque
/// no vaya a buscar un proceso que ya no existe.
void olvidarPid(String nombre) {
  if (Platform.isWindows) return;
  try {
    final f = _ficheroDePid(nombre);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

/// Mata una instancia huérfana del sidecar `nombre` antes de lanzar la nuestra.
///
/// Hace falta porque el cierre ordenado mata los sidecars, pero un cuelgue, un
/// `kill` o un corte de luz los deja vivos: sonando de fondo, sin ventana que
/// los controle y ocupando el nombre del dispositivo en Spotify Connect.
///
/// ⚠️ **En Linux no se puede hacer `pkill librespot`.** Es la traducción obvia
/// del `taskkill /F /IM` de Windows y sería un error grave: mataría el
/// `spotifyd` del usuario, o su propio librespot, o el de cualquier otro
/// programa. Aquí solo se toca **el pid que anotamos nosotros**, y aun así se
/// comprueba antes en `/proc` que sigue siendo el mismo proceso — un pid se
/// recicla, y matar a ciegas el número que había apuntado es tan malo como
/// `pkill`.
Future<void> matarHuerfano(String nombre, File? binario) async {
  if (Platform.isWindows) {
    try {
      // En Windows sí vale por nombre de imagen: la app es de instancia única,
      // así que ningún proceso con ese nombre en este punto es de nadie más.
      await Process.run('taskkill', ['/F', '/IM', '$nombre.exe']);
    } catch (_) {
      // Si no hay ninguno que matar, taskkill devuelve error: da igual.
    }
    return;
  }

  final fichero = _ficheroDePid(nombre);
  if (!fichero.existsSync()) return;

  int? pid;
  try {
    pid = int.tryParse(fichero.readAsStringSync().trim());
  } catch (_) {}
  // Se borra pase lo que pase: un fichero que no se pudo leer o cuyo pid ya no
  // es nuestro solo puede confundir al siguiente arranque.
  try {
    fichero.deleteSync();
  } catch (_) {}
  if (pid == null || pid <= 0) return;

  if (!_esNuestro(pid, nombre, binario)) return;

  Process.killPid(pid, ProcessSignal.sigterm);
  // Un margen corto para que se cierre por las buenas; si sigue ahí, a lo
  // bruto. No se espera más: esto corre en el arranque de la app.
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!Directory('/proc/$pid').existsSync()) return;
  }
  Process.killPid(pid, ProcessSignal.sigkill);
}

/// ¿El proceso que ocupa ahora ese pid es el sidecar que anotamos?
///
/// `/proc/<pid>/cmdline` trae los argumentos separados por NUL, y el primero es
/// el `argv[0]` con el que se lanzó: como `Process.start` recibe la ruta
/// completa del binario, se puede comparar tal cual. Si no se sabe qué binario
/// era, basta con que el nombre encaje.
bool _esNuestro(int pid, String nombre, File? binario) {
  try {
    final cmdline = File('/proc/$pid/cmdline').readAsStringSync();
    final argv0 = cmdline.split(_nul).first;
    if (argv0.isEmpty) return false;
    if (binario != null) return argv0 == binario.path;
    return p.basename(argv0) == nombre;
  } catch (_) {
    // El proceso ya no existe, o no se deja mirar: en ninguno de los dos casos
    // hay nada que matar.
    return false;
  }
}
