import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'procesos.dart' show sufijoEjecutable;
import 'yt_models.dart';

class YtPlayerException implements Exception {
  final String message;
  YtPlayerException(this.message);
  @override
  String toString() => message;
}

/// Reproduce audio de YouTube sin necesitar cuenta Premium, **con cola**.
///
/// Dos piezas separadas, como en el resto de la app: **resolver** la URL del
/// stream de audio (yt-dlp, un binario que se invoca una vez por pista y no un
/// servidor persistente como `metadata-sidecar`) y **reproducirla**
/// (`media_kit`, que envuelve libmpv y sabe abrir esa URL directamente).
///
/// A diferencia de `PlayerController` (que sondea la Web API de Spotify porque
/// el audio suena en otro proceso, `librespot`, controlado en remoto), aquí el
/// reproductor vive en este mismo proceso: no hace falta sondeo, basta con
/// escuchar sus streams.
///
/// ## Por qué hay cola aquí y no en la pantalla
///
/// La cola no es un detalle de la pantalla que la lanzó: al terminar una
/// canción tiene que empezar la siguiente aunque el usuario se haya ido a
/// buscar otra cosa, y la barra inferior necesita saber si hay "siguiente"
/// para encender su botón. Vive donde vive el audio.
///
/// ## La espera de yt-dlp
///
/// Resolver una URL tarda entre medio segundo y dos. Encadenado a cada cambio
/// de canción eso es un silencio audible entre pistas, así que la siguiente se
/// resuelve **mientras suena la actual** y se guarda en [_urls]. Las URLs que
/// devuelve Google caducan (traen su propio `expire`), de ahí que la caché
/// tenga fecha de caducidad propia y conservadora.
class YtPlayer extends ChangeNotifier {
  YtPlayer() : player = Player() {
    // Cuando una pista termina sola, sigue la cola. `completed` también se
    // emite al abrir un medio nuevo en algunas versiones, de ahí el control
    // de que haya sonado algo de verdad y no estemos ya cambiando de pista.
    _subCompletado = player.stream.completed.listen((terminada) {
      if (terminada && !_cambiando && cola.isNotEmpty) unawaited(siguiente(automatico: true));
    });
    _subError = player.stream.error.listen((e) {
      error = 'Error de reproducción: $e';
      notifyListeners();
    });
  }

  final Player player;
  late final StreamSubscription<bool> _subCompletado;
  late final StreamSubscription<String> _subError;

  /// Se llama justo antes de empezar a sonar algo. Es el enganche con el que
  /// `main.dart` para NeoFy: los dos modos comparten altavoces y sonar a la
  /// vez no es una opción.
  Future<void> Function()? alEmpezarAReproducir;

  // --------------------------------------------------------------------- cola

  List<YtTrack> cola = const [];
  int indice = -1;

  /// De dónde salió la cola (el `playlistId`), para poder marcar en la
  /// interfaz qué lista está sonando.
  String? contexto;

  YtTrack? get actual => (indice >= 0 && indice < cola.length) ? cola[indice] : null;
  bool get hayNada => actual == null;
  bool get puedeSaltar => indice + 1 < cola.length;
  bool get puedeVolver => cola.isNotEmpty;

  /// Qué pista se está resolviendo ahora mismo (su `videoId`), para que la
  /// tarjeta pulsada pueda enseñar su ruedecita. `null` si no hay ninguna.
  String? resolviendo;
  String? error;

  bool _cambiando = false;

  /// URLs ya resueltas, con su caducidad. Se limita a un puñado: no es una
  /// caché de verdad, es el adelanto de la siguiente pista.
  final Map<String, ({String url, DateTime hasta})> _urls = {};
  static const _vidaDeUrl = Duration(minutes: 45);

  // ------------------------------------------------------------------ yt-dlp

  /// Busca el binario junto al ejecutable (release) y, si no, en el árbol de
  /// desarrollo — mismo patrón que `LibrespotManager.findBinary()`.
  ///
  /// Y, como último recurso, **en el PATH**: a diferencia de librespot (que se
  /// compila con opciones concretas para esta app), yt-dlp es el mismo binario
  /// que empaqueta cualquier distribución, y YouTube le rompe los extractores
  /// cada pocas semanas. Si el usuario tiene uno instalado y más reciente que
  /// el que vino en el paquete, es mejor que el nuestro; y si el suyo es lo
  /// único que hay, NeoTube funciona igual en vez de no reproducir nada.
  static File? findYtDlpBinary() {
    final nombre = 'yt-dlp$sufijoEjecutable';
    for (final c in [
      p.join(p.dirname(Platform.resolvedExecutable), nombre),
      p.join(Directory.current.path, 'tool', 'ytdlp-build', 'bin', nombre),
    ]) {
      final f = File(c);
      if (f.existsSync()) return f;
    }
    return _enElPath(nombre);
  }

  /// Recorre el PATH a mano en vez de dejar que lo resuelva el sistema al
  /// lanzar el proceso: así Ajustes puede decir **dónde** está el que se va a
  /// usar, que es la mitad de lo que hace falta cuando algo no reproduce.
  static File? _enElPath(String nombre) {
    final path = Platform.environment['PATH'];
    if (path == null) return null;
    for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
      if (dir.trim().isEmpty) continue;
      try {
        final f = File(p.join(dir, nombre));
        if (f.existsSync()) return f;
      } catch (_) {
        // Una entrada del PATH con caracteres inválidos no debe tirar la
        // búsqueda entera: se salta y se sigue con las demás.
      }
    }
    return null;
  }

  /// La versión de yt-dlp instalada, o `null` si no responde.
  ///
  /// Sirve para que Ajustes pueda decir algo mejor que "está el fichero": un
  /// binario presente pero roto (descarga a medias, antivirus que lo ha
  /// vaciado) se ve exactamente igual desde fuera, y el síntoma sería que
  /// ninguna canción arranca sin más pista que un error por pista.
  static Future<String?> versionDeYtDlp() async {
    final bin = findYtDlpBinary();
    if (bin == null) return null;
    try {
      final res = await Process.run(bin.path, ['--version'])
          .timeout(const Duration(seconds: 10));
      if (res.exitCode != 0) return null;
      final v = (res.stdout as String).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// Resuelve la URL del stream de solo-audio de un vídeo con yt-dlp.
  ///
  /// Una invocación, no un proceso vigilado: `yt-dlp -f bestaudio -g` imprime
  /// la URL resuelta en stdout y termina solo. `Process.run` (sin
  /// `runInShell`, que es el que de verdad abriría una shell) no pasa por
  /// ninguna shell del sistema.
  ///
  /// Sin `matarHuerfano` a propósito: eso es para procesos vigilados que se
  /// quedan vivos entre arranques (librespot, metadata-sidecar); aquí cada
  /// pista lanza el suyo y `Process.run` ya espera a que termine solo. Matar
  /// por nombre de imagen antes de cada invocación llegó a cargarse una
  /// resolución en marcha si se pulsaba una segunda canción demasiado rápido.
  Future<String> _resolverUrl(String videoId) async {
    final guardada = _urls[videoId];
    if (guardada != null && guardada.hasta.isAfter(DateTime.now())) return guardada.url;

    final bin = findYtDlpBinary();
    if (bin == null) {
      throw YtPlayerException(
          'No se encuentra yt-dlp. Ejecuta tool/fetch_ytdlp.ps1 (o .sh en Linux).');
    }
    final res = await Process.run(
      bin.path,
      ['-f', 'bestaudio', '-g', 'https://www.youtube.com/watch?v=$videoId'],
    ).timeout(const Duration(seconds: 25));
    if (res.exitCode != 0) {
      throw YtPlayerException('yt-dlp no pudo resolver el vídeo: ${res.stderr}');
    }
    final url = (res.stdout as String).trim().split('\n').first.trim();
    if (url.isEmpty) throw YtPlayerException('yt-dlp no devolvió ninguna URL.');

    if (_urls.length > 12) _urls.clear();
    _urls[videoId] = (url: url, hasta: DateTime.now().add(_vidaDeUrl));
    return url;
  }

  /// Adelanta la resolución de la siguiente pista mientras suena la actual.
  /// Falla en silencio a propósito: es un adelanto, y si no llega a tiempo se
  /// resolverá cuando toque como se hacía antes.
  void _adelantarSiguiente() {
    final proxima = indice + 1 < cola.length ? cola[indice + 1] : null;
    if (proxima == null) return;
    final guardada = _urls[proxima.videoId];
    if (guardada != null && guardada.hasta.isAfter(DateTime.now())) return;
    unawaited(_resolverUrl(proxima.videoId).catchError((_) => ''));
  }

  // ------------------------------------------------------------- reproducción

  /// Pone una cola entera a sonar desde [desde].
  Future<void> reproducirLista(
    List<YtTrack> pistas, {
    int desde = 0,
    String? contexto,
  }) async {
    if (pistas.isEmpty) return;
    cola = List.unmodifiable(pistas);
    this.contexto = contexto;
    indice = desde.clamp(0, pistas.length - 1);
    await _abrirActual();
  }

  /// Una canción suelta: empieza a sonar ya, ella sola.
  ///
  /// Quien la lanza suele pedir después su radio y engancharla con [anexar].
  /// Se hace en dos pasos y no en uno a propósito: esperar a la radio antes de
  /// abrir el audio le sumaba a cada pulsación el viaje entero a la API
  /// **antes** del primer sonido, y eso se nota mucho más que quedarse sin
  /// continuación al terminar.
  Future<void> reproducirPista(YtTrack t) => reproducirLista([t]);

  /// Añade pistas al final de la cola actual, sin repetir las que ya estén.
  void anexar(List<YtTrack> pistas) {
    if (pistas.isEmpty || cola.isEmpty) return;
    final vistos = cola.map((t) => t.videoId).toSet();
    final nuevas = pistas.where((t) => vistos.add(t.videoId)).toList();
    if (nuevas.isEmpty) return;
    cola = List.unmodifiable([...cola, ...nuevas]);
    notifyListeners();
    _adelantarSiguiente();
  }

  Future<void> _abrirActual() async {
    final t = actual;
    if (t == null) return;
    _cambiando = true;
    resolviendo = t.videoId;
    error = null;
    notifyListeners();
    try {
      await alEmpezarAReproducir?.call();
      final url = await _resolverUrl(t.videoId);
      await player.open(Media(url));
      _adelantarSiguiente();
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      resolviendo = null;
      _cambiando = false;
      notifyListeners();
    }
  }

  /// Salta a la siguiente. Cuando lo pide la cola sola ([automatico]) y la
  /// pista falla, se sigue bajando en vez de parar: un vídeo bloqueado por
  /// región en mitad de una playlist de 300 no debe terminar la escucha.
  Future<void> siguiente({bool automatico = false}) async {
    if (!puedeSaltar) {
      if (!automatico) return;
      // Fin de la cola: se para, pero se deja la pista puesta para que el
      // botón de play la pueda volver a arrancar.
      await player.pause();
      await player.seek(Duration.zero);
      return;
    }
    indice++;
    try {
      await _abrirActual();
    } catch (_) {
      if (automatico && puedeSaltar) await siguiente(automatico: true);
    }
  }

  Future<void> anterior() async {
    // Igual que en NeoFy: pasados 3 s, "anterior" reinicia la canción.
    if (player.state.position.inSeconds > 3 || indice <= 0) {
      await player.seek(Duration.zero);
      return;
    }
    indice--;
    await _abrirActual();
  }

  /// Salta a una posición concreta de la cola (la lista de la pantalla de
  /// reproducción, o pulsar una fila de una playlist ya sonando).
  Future<void> saltarA(int i) async {
    if (i < 0 || i >= cola.length) return;
    indice = i;
    await _abrirActual();
  }

  Future<void> alternar() async {
    // Si la cola llegó al final, un `play` pelado no arranca nada: se vuelve a
    // empezar por donde se quedó. Mismo criterio que `PlayerController`.
    if (!player.state.playing &&
        actual != null &&
        player.state.position >= player.state.duration &&
        player.state.duration > Duration.zero) {
      await player.seek(Duration.zero);
    }
    await (player.state.playing ? player.pause() : player.play());
  }

  /// Un salto de la barra hay que anunciarlo aparte al panel del sistema: los
  /// dos reproductores del escritorio extrapolan la posición por su cuenta y
  /// sin esto se quedan enseñando el minuto de antes. Mismo enganche que el
  /// `onSalto` de `PlayerController`.
  void Function(int ms)? onSalto;

  Future<void> pause() => player.pause();
  Future<void> resume() => player.play();

  Future<void> seek(Duration d) async {
    await player.seek(d);
    onSalto?.call(d.inMilliseconds);
  }
  Future<void> setVolumen(double v) => player.setVolume(v.clamp(0, 100));

  Future<void> stop() async {
    await player.stop();
    cola = const [];
    indice = -1;
    contexto = null;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subCompletado.cancel());
    unawaited(_subError.cancel());
    unawaited(player.dispose());
    super.dispose();
  }
}
