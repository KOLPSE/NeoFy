import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_config.dart';

class ArtCache {
  static const int _maxBytes = 50 * 1024 * 1024;

  static Directory get _dir {
    final d = Directory(p.join(cacheDir().path, 'art'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static final http.Client _http = http.Client();

  static final Map<String, Future<File?>> _inFlight = {};

  static File _fileFor(String url) =>
      File(p.join(_dir.path, '${sha1.convert(url.codeUnits)}.img'));

  static Future<File?> file(String url) {
    final existing = _inFlight[url];
    if (existing != null) return existing;
    final future = _load(url).whenComplete(() {
      _inFlight.remove(url);
    });
    _inFlight[url] = future;
    return future;
  }

  static File? ficheroSiEstaEnDisco(String url) {
    final f = _fileFor(url);
    return f.existsSync() ? f : null;
  }

  static Future<Uint8List?> bytes(String url) async {
    final f = await file(url);
    if (f == null) return null;
    try {
      final b = await f.readAsBytes();
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  static int _tmpCounter = 0;

  static Future<File?> _load(String url) async {
    final f = _fileFor(url);
    try {
      if (await f.exists()) {
        if ((await f.stat()).size > 0) {
          unawaited(f.setLastModified(DateTime.now()).catchError((_) {}));
          return f;
        }
        await f.delete().catchError((_) => f);
      }

      final res = await _http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      final tmp = File('${f.path}.${_tmpCounter++}.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename(f.path);

      return f;
    } catch (_) {
      return null;
    }
  }

  static void evict(String url) {
    unawaited(_fileFor(url).delete().catchError((_) => _fileFor(url)));
  }

  static Future<void> prune() async {
    try {
      final files = await _dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final stats = <File, FileStat>{};
      var total = 0;
      for (final f in files) {
        final s = await f.stat();
        stats[f] = s;
        total += s.size;
      }
      if (total <= _maxBytes) return;

      files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      for (final f in files) {
        if (total <= _maxBytes) break;
        total -= stats[f]!.size;
        await f.delete().catchError((_) => f);
      }
    } catch (_) {
    }
  }
}
