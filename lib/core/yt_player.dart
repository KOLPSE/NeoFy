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
  YtPlayer({int volumenInicial = 60})
      : volumen = volumenInicial.clamp(0, 100),
        _mpv = libmpvDisponible ? Player() : null {
    final mpv = _mpv;
    if (mpv == null) {
      // Sin libmpv no hay reproductor, pero el objeto tiene que existir igual:
      // el shell de NeoTube se construye siempre, esté el usuario en ese modo
      // o no. Lo único que cambia es que no suena nada y se enseña el porqué.
      error = motivoSinLibmpv;
      return;
    }
    // El volumen guardado se aplica ya, antes de que suene nada: aplicarlo al
    // abrir la primera pista se oiría como un salto de volumen a mitad de la
    // primera nota.
    unawaited(mpv.setVolume(volumen.toDouble()));
    // Cuando una pista termina sola, sigue la cola. `completed` también se
    // emite al abrir un medio nuevo en algunas versiones, de ahí el control
    // de que haya sonado algo de verdad y no estemos ya cambiando de pista.
    _subCompletado = mpv.stream.completed.listen((terminada) {
      if (terminada && !_cambiando && cola.isNotEmpty) unawaited(siguiente(automatico: true));
    });
    _subError = mpv.stream.error.listen((e) {
      error = 'Error de reproducción: $e';
      notifyListeners();
    });
  }

  /// Si libmpv se pudo cargar al arrancar. Lo fija `main()`, que es quien
  /// llama a `MediaKit.ensureInitialized()`.
  ///
  /// **Por qué esto existe.** `media_kit` no empaqueta libmpv en Linux: la
  /// carga del sistema con `dlopen` al llamar a `ensureInitialized()`, y si no
  /// está, lanza. Como esa llamada va en `main()` antes de `runApp()`, una
  /// distribución sin libmpv instalado hacía que la app arrancara y se cerrara
  /// **sin ventana ni mensaje**: era el fallo que se veía en Arch, donde
  /// `mpv` no viene de serie.
  ///
  /// Los paquetes ya declaran la dependencia, así que un usuario de `.deb`,
  /// `.rpm` o `pacman` no debería llegar aquí nunca. Queda por los del
  /// tarball, que no tiene forma de exigir nada: mejor una NeoFy entera con
  /// NeoTube apagado que ninguna app.
  ///
  /// En Windows no aplica: allí `libmpv-2.dll` viaja dentro del paquete.
  static bool libmpvDisponible = true;

  /// Qué decirle al usuario cuando [libmpvDisponible] es `false`.
  ///
  /// Es un mensaje nuestro y no el de la excepción de `media_kit`: aquel está
  /// en inglés y solo sabe recomendar `apt install libmpv-dev`, que no le sirve
  /// de nada a quien está en Arch o en Fedora. El original se queda en el log.
  static String motivoSinLibmpv =
      'No se encuentra libmpv, la librería que reproduce el audio de NeoTube. '
      'Instala el paquete de tu distribución (Arch: mpv · Debian/Ubuntu: '
      'libmpv2 · Fedora: mpv-libs) y vuelve a abrir NeoFy.';

  /// El reproductor de verdad, o `null` si falta libmpv. Privado a propósito:
  /// fuera se usan [sonando], [posicion] y compañía, que ya contemplan que no
  /// haya reproductor.
  final Player? _mpv;

  StreamSubscription<bool>? _subCompletado;
  StreamSubscription<String>? _subError;

  /// ¿Puede sonar algo? `false` solo cuando falta libmpv (ver
  /// [libmpvDisponible]). Con esto puesto a `false`, NeoTube se enseña
  /// explicando qué falta en vez de aceptar pulsaciones que no harían nada.
  bool get disponible => _mpv != null;

  bool get sonando => _mpv?.state.playing ?? false;

  /// Cambios de play/pausa. Hace falta aparte de [notifyListeners] porque
  /// pausar no cambia nada del estado que lleva esta clase.
  Stream<bool> get cambiosDeSonando => _mpv?.stream.playing ?? const Stream<bool>.empty();

  Duration get posicion => _mpv?.state.position ?? Duration.zero;

  Stream<Duration> get cambiosDePosicion =>
      _mpv?.stream.position ?? const Stream<Duration>.empty();

  Duration get duracion => _mpv?.state.duration ?? Duration.zero;

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

  /// PATH mínimo para volver a intentar una invocación que murió recorriendo
  /// el PATH del usuario. Ver [_ejecutar].
  static String get _pathMinimo => Platform.isWindows
      ? [
          '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\system32',
          Platform.environment['SystemRoot'] ?? r'C:\Windows',
        ].join(';')
      : '/usr/bin:/bin';

  /// Lanza yt-dlp y, si se cae **recorriendo el PATH**, lo reintenta con uno
  /// mínimo.
  ///
  /// El fallo real que arregla, en Windows 11:
  ///
  ///     ERROR: [WinError 448] The path cannot be traversed because it
  ///     contains an untrusted mount point: 'C:\Users\...\.mavis\bin'
  ///
  /// Ese error es de *Redirection Guard*, la mitigación que impide seguir
  /// junctions que podrían ser un ataque de enlaces. yt-dlp recorre el PATH
  /// buscando ffmpeg y un runtime de JavaScript, y si alguna entrada es un
  /// junction, revienta entero: ni resuelve la URL ni reproduce nada.
  ///
  /// Y lo que lo hace difícil de ver: **la mitigación se hereda del proceso
  /// padre**. Lanzada desde el menú de inicio la app no la tiene, pero recién
  /// actualizada la arranca el instalador, que sí — así que el sintoma aparece
  /// justo despues de actualizar y desaparece al reabrir la app a mano, que es
  /// lo que despista.
  ///
  /// No se le recorta el PATH de entrada a todo el mundo: yt-dlp lo usa para
  /// encontrar ffmpeg y el runtime de JS, y quien los tenga instalados sale
  /// perdiendo formatos. Se reintenta solo cuando se ha visto fallar.
  static Future<ProcessResult> _ejecutar(String ruta, List<String> args) async {
    final res = await Process.run(ruta, args).timeout(const Duration(seconds: 25));
    if (res.exitCode == 0) return res;
    final salida = '${res.stderr}';
    final esDelPath = salida.contains('untrusted mount point') ||
        salida.contains('WinError 448');
    if (!esDelPath) return res;
    debugPrint('[NeoTube] yt-dlp no pudo recorrer el PATH; reintento con uno mínimo');
    return Process.run(
      ruta,
      args,
      // Solo se pisa PATH: el resto del entorno (SystemRoot, TEMP…) sigue
      // haciendo falta, y sin él ni siquiera arranca el intérprete embebido.
      environment: {'PATH': _pathMinimo},
    ).timeout(const Duration(seconds: 25));
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
      final res = await _ejecutar(bin.path, ['--version']);
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
    final res = await _ejecutar(
      bin.path,
      ['-f', 'bestaudio', '-g', 'https://www.youtube.com/watch?v=$videoId'],
    );
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
    if (pistas.isEmpty || !disponible) return;
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
    final mpv = _mpv;
    if (t == null || mpv == null) return;
    _cambiando = true;
    resolviendo = t.videoId;
    error = null;
    notifyListeners();
    try {
      await alEmpezarAReproducir?.call();
      final url = await _resolverUrl(t.videoId);
      await mpv.open(Media(url));
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

  /// Se avisa cuando la cola se acaba **sola** (no por un salto del usuario).
  ///
  /// NeoTube lo deja a `null`: allí la cola de este reproductor es toda la cola
  /// que hay. La vía libre de NeoFy sí lo usa, porque allí la cola de verdad es
  /// la de canciones de Spotify y esta solo tiene la que suena ahora.
  Future<void> Function()? alAcabarLaCola;

  /// Salta a la siguiente. Cuando lo pide la cola sola ([automatico]) y la
  /// pista falla, se sigue bajando en vez de parar: un vídeo bloqueado por
  /// región en mitad de una playlist de 300 no debe terminar la escucha.
  Future<void> siguiente({bool automatico = false}) async {
    final mpv = _mpv;
    if (mpv == null) return;
    if (!puedeSaltar) {
      if (!automatico) return;
      if (alAcabarLaCola != null) {
        await alAcabarLaCola!();
        return;
      }
      // Fin de la cola: se para, pero se deja la pista puesta para que el
      // botón de play la pueda volver a arrancar.
      await mpv.pause();
      await mpv.seek(Duration.zero);
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
    final mpv = _mpv;
    if (mpv == null) return;
    // Igual que en NeoFy: pasados 3 s, "anterior" reinicia la canción.
    if (mpv.state.position.inSeconds > 3 || indice <= 0) {
      await mpv.seek(Duration.zero);
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
    final mpv = _mpv;
    if (mpv == null) return;
    // Si la cola llegó al final, un `play` pelado no arranca nada: se vuelve a
    // empezar por donde se quedó. Mismo criterio que `PlayerController`.
    if (!mpv.state.playing &&
        actual != null &&
        mpv.state.position >= mpv.state.duration &&
        mpv.state.duration > Duration.zero) {
      await mpv.seek(Duration.zero);
    }
    await (mpv.state.playing ? mpv.pause() : mpv.play());
  }

  /// Un salto de la barra hay que anunciarlo aparte al panel del sistema: los
  /// dos reproductores del escritorio extrapolan la posición por su cuenta y
  /// sin esto se quedan enseñando el minuto de antes. Mismo enganche que el
  /// `onSalto` de `PlayerController`.
  void Function(int ms)? onSalto;

  /// Volumen actual, 0..100. Se guarda aquí y no se lee de
  /// `player.state.volume` porque la barra tiene que poder pintarlo antes de
  /// que haya sonado nada.
  int volumen;

  /// Se llama al soltar el mando del volumen, para persistirlo. No en cada
  /// paso del arrastre: eso serían decenas de escrituras del config por cada
  /// vez que alguien mueve el mando.
  void Function(int volumen)? onVolumenFijado;

  /// Aplicar el volumen es instantáneo y local (libmpv, en este mismo
  /// proceso), así que **sí** se hace en cada paso del arrastre — al revés que
  /// en NeoFy, donde cada paso sería una petición a la Web API y Spotify
  /// acababa devolviendo 429.
  Future<void> setVolumen(int v) async {
    final nuevo = v.clamp(0, 100);
    if (nuevo == volumen) return;
    volumen = nuevo;
    notifyListeners();
    await _mpv?.setVolume(nuevo.toDouble());
  }

  Future<void> pause() async => _mpv?.pause();
  Future<void> resume() async => _mpv?.play();

  Future<void> seek(Duration d) async {
    if (_mpv == null) return;
    await _mpv.seek(d);
    onSalto?.call(d.inMilliseconds);
  }

  Future<void> stop() async {
    await _mpv?.stop();
    cola = const [];
    indice = -1;
    contexto = null;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subCompletado?.cancel());
    unawaited(_subError?.cancel());
    unawaited(_mpv?.dispose());
    super.dispose();
  }
}
