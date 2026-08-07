import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'procesos.dart';

enum LibrespotStatus { stopped, starting, running, failed }

/// ¿Esta línea del log dice que librespot se ha quedado sin audio?
///
/// Cuando el dispositivo de salida desaparece bajo sus pies, librespot **no se
/// muere**: sigue vivo, sigue diciéndole a Spotify que la canción avanza, y lo
/// único que pasa es que no sale sonido. Un proceso que no cae no dispara el
/// reinicio automático, así que el error del backend de audio en el log es el
/// único aviso que hay de que hace falta reabrir la salida.
///
/// Se busca a propósito por el nombre del backend y no por el texto exacto del
/// error: los mensajes de rodio/cpal cambian de versión en versión, pero el
/// backend que los firma no.
bool esFalloDeAudio(String linea) {
  if (!linea.contains('ERROR')) return false;
  final l = linea.toLowerCase();
  return l.contains('audio sink') ||
      l.contains('audiosink') ||
      l.contains('rodio') ||
      l.contains('cpal') ||
      // Los backends de Linux. `pulseaudio` es el que usamos allí; `alsa`
      // aparece igualmente porque PulseAudio se apoya en él por debajo y sus
      // errores suben al log con ese nombre.
      l.contains('pulseaudio') ||
      l.contains('alsa') ||
      l.contains('audio backend') ||
      l.contains('output device');
}

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
  bool _reiniciando = false;

  /// Se llama cuando el log delata que la salida de audio se ha roto. Quien
  /// escucha decide qué hacer (reiniciar el sidecar y retomar la canción);
  /// aquí no se sabe nada de la Web API ni de lo que estuviera sonando.
  void Function()? onFalloDeAudio;

  /// Últimas líneas del log del proceso. Es lo único que tenemos para
  /// diagnosticar cuando librespot no arranca, así que se conserva un trozo.
  final List<String> logTail = [];

  LibrespotStatus get status => _status;
  String? get lastError => _lastError;

  /// Pid del proceso hijo, para poder medir su memoria. Cambia en cada
  /// reinicio del sidecar, así que hay que preguntarlo, no guardarlo.
  int? get pid => _proc?.pid;

  /// Donde librespot deja `credentials.json`. Cuelga de [appDataDir] y no de la
  /// caché: perderlo obliga a repetir el login del navegador.
  Directory get _credencialesDir {
    final d = Directory(p.join(appDataDir().path, 'librespot'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// librespot guarda aquí el blob de sesión tras el login OAuth. Si existe,
  /// no hace falta volver a pasar por el navegador.
  bool get hasCredentials =>
      File(p.join(_credencialesDir.path, 'credentials.json')).existsSync();

  /// Busca el binario junto al ejecutable (release) y, si no, en el árbol de
  /// desarrollo. Mismo patrón que usa NeoDrive para el icono de bandeja.
  ///
  /// Junto al ejecutable es donde lo dejan las dos cadenas de empaquetado: el
  /// `install(PROGRAMS ...)` de CMake en Windows y el mismo en Linux, que en un
  /// paquete del AUR acaba en `/opt/neofy`.
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

    // Barrer instancias huérfanas antes de lanzar la nuestra. Si la app murió
    // de golpe (cuelgue, kill, corte de luz), su librespot sobrevive y se queda
    // sonando sin ventana que lo controle, además de ocupar el nombre del
    // dispositivo en Spotify Connect. El cierre ordenado ya lo mata; esto cubre
    // el que no lo fue. Ver `procesos.dart`: cada plataforma lo hace de una
    // forma, y en Linux **no** vale barrer por nombre.
    await matarHuerfano('librespot', bin);

    final args = <String>[
      '--name', kDeviceName,
      '--device-type', 'computer',
      '--bitrate', '${config.bitrate}',
      // En Windows, rodio (que va por cpal). En Linux, PulseAudio: PipeWire lo
      // expone por su shim y **mueve el flujo solo** cuando cambia el altavoz,
      // que es justo el fallo que en Windows hay que vigilar a mano con un
      // IMMNotificationClient. Ver "El audio que se queda mudo".
      '--backend', Platform.isWindows ? 'rodio' : 'pulseaudio',
      '--system-cache', _credencialesDir.path,
      // La caché de audio son megas que se pueden tirar: va a la carpeta de
      // caché, que en Linux no es la misma que la de configuración.
      '--cache', p.join(cacheDir().path, 'audio'),
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
      // Anotado para poder barrerlo si la app muere sin llegar a matarlo.
      anotarPid('librespot', proc.pid);

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLogLine);

      unawaited(proc.exitCode.then((code) => _onExit(proc, code)));
      _setStatus(LibrespotStatus.running);
    } catch (e) {
      _setStatus(LibrespotStatus.failed, error: 'No se pudo lanzar librespot: $e');
    }
  }

  /// Vuelve a levantar el sidecar con la salida de audio que haya ahora.
  ///
  /// El contador de reintentos se pone a cero a propósito: esto no es una
  /// caída, es un reinicio pedido, y no debe gastar los cinco intentos que
  /// protegen del bucle cuando librespot de verdad no arranca.
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

    if (esFalloDeAudio(line)) onFalloDeAudio?.call();

    // Durante el login, librespot escribe la URL de autorización en el log en
    // vez de abrir el navegador. La abrimos nosotros para que el usuario no
    // tenga que ir a buscarla.
    final match = RegExp(r'https://accounts\.spotify\.com/\S+').firstMatch(line);
    if (match != null) {
      final url = Uri.tryParse(match.group(0)!);
      if (url != null) unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
    }
  }

  Future<void> _onExit(Process proc, int code) async {
    // Un proceso que ya no es el nuestro no tiene voz. Al reiniciar el sidecar,
    // si el viejo tarda más de dos segundos en morir se le mata a lo bruto y
    // `stop()` no espera: su aviso de salida puede llegar con el nuevo ya
    // arrancado, y sin esta comprobación lo daría por caído y lo reiniciaría
    // otra vez, cortando el audio que acabábamos de recuperar.
    if (_proc != null && !identical(_proc, proc)) return;
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
      // Cierre ordenado: la anotación ya no sirve, y dejarla haría que el
      // siguiente arranque fuera a buscar un pid que puede haberse reciclado.
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
