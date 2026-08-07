import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'models.dart';
import 'procesos.dart';

/// Cliente y supervisor de `metadata-sidecar.exe`.
///
/// Existe por una restricción concreta: estando en Modo Desarrollo, la Web API
/// contesta **403** al pedir el contenido de una playlist que no sea tuya (y
/// también en `/v1/tracks?ids=`). La sesión de librespot sí puede leerlo, así
/// que el sidecar abre esa sesión y sirve los metadatos en localhost con la
/// misma forma de JSON que la Web API — por eso aquí se reutiliza
/// `Track.fromJson` tal cual.
///
/// Solo se usa como plan B: las playlists propias siguen yendo por la vía
/// oficial.
class MetadataSidecar extends ChangeNotifier {
  static const int puerto = 8900;

  Process? _proc;
  bool _ready = false;
  String? _error;
  bool _stopping = false;

  final http.Client _http = http.Client();

  bool get ready => _ready;
  String? get error => _error;

  /// Pid del proceso hijo, para poder medir su memoria.
  int? get pid => _proc?.pid;

  static File? findBinary() {
    final nombre = 'metadata-sidecar$sufijoEjecutable';
    final candidates = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), nombre),
      p.join(Directory.current.path, 'tool', 'metadata-sidecar', 'target', 'release',
          nombre),
      p.join(Directory.current.path, 'tool', 'metadata-sidecar', 'target', 'debug',
          nombre),
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }
    return null;
  }

  /// Arranca el sidecar. Debe llamarse **después** de que librespot haya dejado
  /// sus credenciales en caché: sin ellas el proceso sale con código 3.
  Future<void> start() async {
    if (_proc != null) return;
    _stopping = false;

    final bin = findBinary();
    if (bin == null) {
      _error = 'No se encuentra metadata-sidecar$sufijoEjecutable.';
      notifyListeners();
      return;
    }

    // Un sidecar huérfano de un arranque anterior tendría el puerto ocupado.
    await matarHuerfano('metadata-sidecar', bin);

    try {
      final proc = await Process.start(bin.path, ['$puerto']);
      _proc = proc;
      anotarPid('metadata-sidecar', proc.pid);

      final listo = Completer<bool>();
      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        // El sidecar anuncia "READY <puerto>" cuando ya puede atender.
        if (line.startsWith('READY') && !listo.isCompleted) listo.complete(true);
      });
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        _error = line;
      });

      unawaited(proc.exitCode.then((code) {
        _proc = null;
        _ready = false;
        if (!_stopping) {
          _error ??= 'El sidecar de metadatos se cerró (código $code).';
        }
        if (!listo.isCompleted) listo.complete(false);
        notifyListeners();
      }));

      _ready = await listo.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      if (_ready) _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'No se pudo lanzar el sidecar de metadatos: $e';
      notifyListeners();
    }
  }

  /// Página de canciones de una playlist, con la misma forma que la Web API.
  Future<ApiPage<Track>> playlistItems(String id, {int offset = 0, int limit = 50}) async {
    if (!_ready) throw StateError('El sidecar de metadatos no está listo.');

    final uri = Uri.http('127.0.0.1:$puerto', '/playlist/$id', {
      'offset': '$offset',
      'limit': '$limit',
    });
    final res = await _http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('El sidecar devolvió ${res.statusCode}: ${res.body}');
    }

    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final total = (j['total'] as num?)?.toInt() ?? 0;
    final items = ((j['items'] as List<dynamic>?) ?? const [])
        .map((t) => Track.fromJson(t as Map<String, dynamic>?))
        .whereType<Track>()
        .toList();

    // El sidecar corta por offset/limit sobre la lista completa y se salta las
    // pistas ilegibles, así que el avance del offset se calcula con la ventana
    // pedida, no con las que hayan sobrevivido.
    final consumidas = (total - offset).clamp(0, limit);
    return ApiPage(
      items: items,
      hasMore: offset + consumidas < total,
      rawCount: consumidas,
    );
  }

  Future<void> stop() async {
    _stopping = true;
    final proc = _proc;
    _proc = null;
    _ready = false;
    if (proc != null) {
      proc.kill();
      await proc.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      olvidarPid('metadata-sidecar');
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
