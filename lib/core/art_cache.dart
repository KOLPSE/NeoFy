import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_config.dart';

/// Caché de carátulas en disco con tope LRU.
///
/// Las carátulas son lo único que esta app descarga en volumen, así que se
/// guardan en disco para no repetir descargas entre arranques. El tope evita
/// que la carpeta crezca sin fin.
class ArtCache {
  static const int _maxBytes = 50 * 1024 * 1024;

  /// Cuelga de [cacheDir] y no de `appDataDir`: son 50 MB de imágenes que se
  /// pueden borrar sin perder nada (se vuelven a bajar), así que en Linux van a
  /// `~/.cache` y no a `~/.config`. En Windows las dos rutas son la misma.
  static Directory get _dir {
    final d = Directory(p.join(cacheDir().path, 'art'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static final http.Client _http = http.Client();

  /// Descargas en curso, para que N filas pidiendo la misma carátula a la vez
  /// resulten en una sola petición.
  static final Map<String, Future<File?>> _inFlight = {};

  static File _fileFor(String url) =>
      File(p.join(_dir.path, '${sha1.convert(url.codeUnits)}.img'));

  /// Deja la carátula en disco y devuelve **el fichero**, no sus bytes.
  ///
  /// ⚠️ Que devuelva el fichero y no los bytes es una decisión de memoria, no
  /// de comodidad. Con `Image.memory` el `MemoryImage` se queda como **clave**
  /// dentro del `imageCache` de Flutter, y una clave viva mantiene vivo su
  /// `Uint8List`: por cada carátula cacheada se guardaban las dos cosas, el
  /// bitmap decodificado *y* el JPEG entero. Encima, cada `ArtImage` sujetaba
  /// su propio futuro con los bytes mientras la fila existiera. Con
  /// `Image.file` la clave es una ruta y los bytes se sueltan en cuanto se
  /// decodifica.
  static Future<File?> file(String url) {
    final existing = _inFlight[url];
    if (existing != null) return existing;
    // ⚠️ El cuerpo con llaves es obligatorio. Con `=> _inFlight.remove(url)`,
    // el callback devuelve el valor borrado del mapa — que es este mismo
    // futuro — y `whenComplete` espera a que termine el futuro que le devuelve
    // el callback: se quedaba esperándose a sí mismo y no completaba nunca.
    final future = _load(url).whenComplete(() {
      _inFlight.remove(url);
    });
    _inFlight[url] = future;
    return future;
  }

  /// El fichero **solo si ya está descargado**, sin salir a la red ni esperar.
  ///
  /// Lo usa MPRIS (`core/mpris.dart`) para pasarle al escritorio la carátula de
  /// lo que suena. Ahí no se puede esperar a una descarga: la respuesta de D-Bus
  /// tiene que salir en el momento, y una carátula que aún no está vale más
  /// omitirla que retrasar los metadatos enteros. Como la pantalla ya la habrá
  /// pedido por [file], en la práctica casi siempre está.
  static File? ficheroSiEstaEnDisco(String url) {
    final f = _fileFor(url);
    return f.existsSync() ? f : null;
  }

  /// Los bytes, para quien de verdad los necesite. Hoy solo
  /// `tool/probe_art.dart`: la interfaz va por [file].
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
        // Un fichero vacío es basura de una escritura que no terminó: se tira
        // y se vuelve a bajar en vez de dárselo al decodificador. Se mira el
        // tamaño por `stat`, sin leer el contenido.
        if ((await f.stat()).size > 0) {
          // Tocar el fichero para que el LRU sepa que sigue en uso.
          unawaited(f.setLastModified(DateTime.now()).catchError((_) {}));
          return f;
        }
        await f.delete().catchError((_) => f);
      }

      final res = await _http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      // Escritura atómica: primero a un temporal propio y luego un rename, que
      // el sistema de ficheros hace de un golpe. Si se escribiera directamente
      // sobre el destino, otro widget pidiendo la misma carátula podría leerla
      // a medio escribir y el decodificador reventaría con la imagen truncada.
      final tmp = File('${f.path}.${_tmpCounter++}.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename(f.path);

      return f;
    } catch (_) {
      // Una carátula que no carga es cosmético: se pinta el hueco y ya.
      return null;
    }
  }

  /// Tira la copia local de una carátula. Se llama cuando los bytes no
  /// decodifican, para que el siguiente intento vuelva a bajarla en vez de
  /// releer eternamente un fichero roto.
  static void evict(String url) {
    unawaited(_fileFor(url).delete().catchError((_) => _fileFor(url)));
  }

  /// Poda la caché al arrancar, borrando lo más antiguo hasta bajar del tope.
  /// Se hace una sola vez y fuera del camino crítico del arranque.
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
      // Podar es best-effort; que falle no debe impedir arrancar.
    }
  }
}
