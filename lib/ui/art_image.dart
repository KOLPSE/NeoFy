import 'dart:io';

import 'package:flutter/material.dart';

import '../core/art_cache.dart';
import '../core/settings.dart';

/// Carátula con caché en disco y decodificación al tamaño de destino.
///
/// El `cacheWidth` es lo importante: sin él Flutter guarda en memoria el bitmap
/// a resolución completa aunque se pinte a 48 px, y una lista con cien filas se
/// come cientos de megas. Con él, cada miniatura ocupa lo que ocupa en pantalla.
///
/// ⚠️ Pinta desde **fichero**, no desde bytes. `Image.memory` obligaba a
/// guardar el JPEG entero además del bitmap: el `MemoryImage` es la clave de la
/// entrada en el `imageCache` de Flutter, y mientras la entrada viva su
/// `Uint8List` vive con ella. Además cada fila sujetaba su propio futuro con
/// los bytes. Con `Image.file` la clave es una ruta.
///
/// Es un `StatefulWidget` **a propósito**: el futuro de la descarga se resuelve
/// una sola vez por URL, en `initState`/`didUpdateWidget`. Pedirlo desde
/// `build()` crearía un futuro nuevo en cada repintado — y la barra de
/// reproducción se repinta en cada sondeo —, así que la imagen volvía al
/// placeholder continuamente y varias lecturas competían por el mismo fichero.
class ArtImage extends StatefulWidget {
  const ArtImage({
    super.key,
    required this.url,
    this.urlGrande,
    required this.size,
    this.radius = 4,
  });

  /// La variante pequeña (los 64 px de Spotify).
  final String? url;

  /// La variante de 300 px, si el modelo la tiene. Solo se baja cuando el
  /// tamaño real en píxeles no cabe en la de 64.
  final String? urlGrande;

  final double size;
  final double radius;

  /// El escalón de Spotify más pequeño. Por debajo de esto, pedir la de 300 es
  /// bajarse hasta 78 KB para pintar 56 px.
  static const int _escalonPequeno = 64;

  @override
  State<ArtImage> createState() => _ArtImageState();
}

class _ArtImageState extends State<ArtImage> {
  Future<File?>? _future;
  String? _elegida;

  /// Cuál de las dos variantes hace falta **en píxeles reales**.
  ///
  /// Spotify sirve cada carátula en 640/300/64. La barra de reproducción pinta
  /// 56 px lógicos: en una pantalla al 100 % son 56 físicos y la de 64 sobra,
  /// pero en una HiDPI al 200 % son 112 y se vería blanda. Elegir por el
  /// tamaño lógico (como se hacía) obliga a acertar a ciegas para todas las
  /// pantallas; elegir por píxeles acierta en cada una.
  String? _urlPara(double dpr) {
    final pixeles = widget.size * dpr;
    if (pixeles <= ArtImage._escalonPequeno) return widget.url ?? widget.urlGrande;
    return widget.urlGrande ?? widget.url;
  }

  // El dpr sale de MediaQuery, que no está disponible en initState. Aquí sí, y
  // además esto se vuelve a llamar si la ventana cambia de monitor.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo cuando cambia la URL de verdad; un repintado cualquiera no debe
    // volver a lanzar la descarga.
    if (oldWidget.url != widget.url ||
        oldWidget.urlGrande != widget.urlGrande ||
        oldWidget.size != widget.size) {
      _resolve();
    }
  }

  void _resolve() {
    // En modo rendimiento no se pide nada: ni red, ni disco, ni decodificar.
    // El mosaico se dibuja con la propia URL como semilla.
    if (modoRendimiento.value) {
      _elegida = null;
      _future = null;
      return;
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final url = _urlPara(dpr);
    if (url == _elegida && _future != null) return;
    _elegida = url;
    _future = url == null ? null : ArtCache.file(url);
  }

  @override
  void initState() {
    super.initState();
    // Encender o apagar el modo tiene que redibujar todas las carátulas que
    // haya en pantalla en ese momento, no solo las que se construyan después.
    modoRendimiento.addListener(_alCambiarElModo);
  }

  @override
  void dispose() {
    modoRendimiento.removeListener(_alCambiarElModo);
    super.dispose();
  }

  void _alCambiarElModo() {
    if (!mounted) return;
    setState(_resolve);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final target = (widget.size * dpr).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _future == null
            ? _placeholder(context)
            : FutureBuilder<File?>(
                future: _future,
                builder: (context, snap) {
                  final fichero = snap.data;
                  if (fichero == null) return _placeholder(context);
                  return Image.file(
                    fichero,
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.cover,
                    cacheWidth: target,
                    cacheHeight: target,
                    gaplessPlayback: true,
                    // Una imagen que no decodifica no debe pintar el cuadro de
                    // error de Flutter en mitad de una lista: se tira la copia
                    // de disco (que puede estar corrupta) y se deja el hueco.
                    errorBuilder: (context, error, stack) {
                      final url = widget.url;
                      if (url != null) ArtCache.evict(url);
                      return _placeholder(context);
                    },
                  );
                },
              ),
      ),
    );
  }

  /// Lo que se pinta cuando no hay imagen: sin carátula (modo rendimiento) o
  /// mientras se descarga.
  ///
  /// No es un cuadro gris. El tono sale de la propia URL, así que **cada disco
  /// tiene siempre el mismo color** y una lista sigue leyéndose de un vistazo:
  /// el ojo distingue las filas por color aunque no haya portadas. Cuesta cero
  /// bytes — es un degradado, no una imagen.
  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semilla = widget.url ?? widget.urlGrande;

    if (semilla == null) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.music_note,
          size: widget.size * 0.5,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );
    }

    final tono = (semilla.hashCode % 360).abs().toDouble();
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    // Saturación contenida y luminosidad acorde al tema: colores de fondo, no
    // pegatinas fosforitas que compitan con el texto de al lado.
    final a = HSLColor.fromAHSL(1, tono, 0.42, oscuro ? 0.30 : 0.68).toColor();
    final b = HSLColor.fromAHSL(1, (tono + 28) % 360, 0.42, oscuro ? 0.20 : 0.56)
        .toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
      ),
      child: Icon(
        Icons.music_note,
        size: widget.size * 0.45,
        color: Colors.white.withValues(alpha: 0.55),
      ),
    );
  }
}
