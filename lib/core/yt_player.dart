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

class YtPlayer extends ChangeNotifier {
  YtPlayer({int volumenInicial = 60})
      : volumen = volumenInicial.clamp(0, 100),
        _mpv = libmpvDisponible ? Player() : null {
    final mpv = _mpv;
    if (mpv == null) {
      error = motivoSinLibmpv;
      return;
    }
    unawaited(mpv.setVolume(volumen.toDouble()));
    _subCompletado = mpv.stream.completed.listen((terminada) {
      if (terminada && !_cambiando && cola.isNotEmpty) unawaited(siguiente(automatico: true));
    });
    _subError = mpv.stream.error.listen((e) {
      error = 'Error de reproducción: $e';
      notifyListeners();
    });
  }

  static bool libmpvDisponible = true;

  static String motivoSinLibmpv =
      'No se encuentra libmpv, la librería que reproduce el audio de NeoTube. '
      'Instala el paquete de tu distribución (Arch: mpv · Debian/Ubuntu: '
      'libmpv2 · Fedora: mpv-libs) y vuelve a abrir NeoFy.';

  final Player? _mpv;

  StreamSubscription<bool>? _subCompletado;
  StreamSubscription<String>? _subError;

  bool get disponible => _mpv != null;

  bool get sonando => _mpv?.state.playing ?? false;

  Stream<bool> get cambiosDeSonando => _mpv?.stream.playing ?? const Stream<bool>.empty();

  Duration get posicion => _mpv?.state.position ?? Duration.zero;

  Stream<Duration> get cambiosDePosicion =>
      _mpv?.stream.position ?? const Stream<Duration>.empty();

  Duration get duracion => _mpv?.state.duration ?? Duration.zero;

  Future<void> Function()? alEmpezarAReproducir;

  List<YtTrack> cola = const [];
  int indice = -1;

  String? contexto;

  YtTrack? get actual => (indice >= 0 && indice < cola.length) ? cola[indice] : null;
  bool get hayNada => actual == null;
  bool get puedeSaltar => indice + 1 < cola.length;
  bool get puedeVolver => cola.isNotEmpty;

  String? resolviendo;
  String? error;

  bool _cambiando = false;

  final Map<String, ({String url, DateTime hasta})> _urls = {};
  static const _vidaDeUrl = Duration(minutes: 45);

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

  static File? _enElPath(String nombre) {
    final path = Platform.environment['PATH'];
    if (path == null) return null;
    for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
      if (dir.trim().isEmpty) continue;
      try {
        final f = File(p.join(dir, nombre));
        if (f.existsSync()) return f;
      } catch (_) {
      }
    }
    return null;
  }

  static String get _pathMinimo => Platform.isWindows
      ? [
          '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\system32',
          Platform.environment['SystemRoot'] ?? r'C:\Windows',
        ].join(';')
      : '/usr/bin:/bin';

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
      environment: {'PATH': _pathMinimo},
    ).timeout(const Duration(seconds: 25));
  }

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

  void _adelantarSiguiente() {
    final proxima = indice + 1 < cola.length ? cola[indice + 1] : null;
    if (proxima == null) return;
    final guardada = _urls[proxima.videoId];
    if (guardada != null && guardada.hasta.isAfter(DateTime.now())) return;
    unawaited(_resolverUrl(proxima.videoId).catchError((_) => ''));
  }

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

  Future<void> reproducirPista(YtTrack t) => reproducirLista([t]);

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

  Future<void> Function()? alAcabarLaCola;

  Future<void> siguiente({bool automatico = false}) async {
    final mpv = _mpv;
    if (mpv == null) return;
    if (!puedeSaltar) {
      if (!automatico) return;
      if (alAcabarLaCola != null) {
        await alAcabarLaCola!();
        return;
      }
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
    if (mpv.state.position.inSeconds > 3 || indice <= 0) {
      await mpv.seek(Duration.zero);
      return;
    }
    indice--;
    await _abrirActual();
  }

  Future<void> saltarA(int i) async {
    if (i < 0 || i >= cola.length) return;
    indice = i;
    await _abrirActual();
  }

  Future<void> alternar() async {
    final mpv = _mpv;
    if (mpv == null) return;
    if (!mpv.state.playing &&
        actual != null &&
        mpv.state.position >= mpv.state.duration &&
        mpv.state.duration > Duration.zero) {
      await mpv.seek(Duration.zero);
    }
    await (mpv.state.playing ? mpv.pause() : mpv.play());
  }

  void Function(int ms)? onSalto;

  int volumen;

  void Function(int volumen)? onVolumenFijado;

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
