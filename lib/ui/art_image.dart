import 'dart:io';

import 'package:flutter/material.dart';

import '../core/art_cache.dart';
import '../core/settings.dart';
import '../core/temas.dart';

class ArtImage extends StatefulWidget {
  const ArtImage({
    super.key,
    required this.url,
    this.urlGrande,
    required this.size,
    this.ancho,
    this.radius,
    this.fit = BoxFit.cover,
  });

  final String? url;

  final String? urlGrande;

  final double size;

  final double? ancho;

  final double? radius;

  final BoxFit fit;

  static const int _escalonPequeno = 64;

  /// Miniaturas (rail, filas, tiles de 40) comparten cubeta para que el
  /// `imageCache` acierte al plegar el sidebar: 28, 32 y 40 no son claves
  /// distintas. Las de 56+ (now playing, cabeceras) se quedan en su tamaño.
  @visibleForTesting
  static int pixelsDeCache(double logico, double dpr) {
    final crudo = (logico * dpr).round().clamp(1, 1920);
    if (logico <= 48) {
      return (ArtImage._escalonPequeno * dpr)
          .round()
          .clamp(ArtImage._escalonPequeno, 1920);
    }
    return crudo;
  }

  @override
  State<ArtImage> createState() => _ArtImageState();
}

class _ArtImageState extends State<ArtImage> {
  Future<File?>? _future;
  File? _fichero;
  String? _elegida;

  String? _urlPara(double dpr) {
    final pixeles = (widget.ancho ?? widget.size) * dpr;
    if (pixeles <= ArtImage._escalonPequeno) return widget.url ?? widget.urlGrande;
    return widget.urlGrande ?? widget.url;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.urlGrande != widget.urlGrande ||
        oldWidget.size != widget.size ||
        oldWidget.ancho != widget.ancho) {
      _resolve();
    }
  }

  void _resolve() {
    if (modoRendimiento.value) {
      _elegida = null;
      _future = null;
      _fichero = null;
      return;
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final url = _urlPara(dpr);
    if (url == _elegida &&
        (url == null || _fichero != null || _future != null)) {
      return;
    }
    _elegida = url;
    if (url == null) {
      _fichero = null;
      _future = null;
      return;
    }
    // El FutureBuilder, aunque el jpeg ya esté en disco, espera un microtask
    // y pinta el mosaico un frame (o varios). Al plegar el rail parece que
    // las carátulas se vuelven a bajar.
    _fichero = ArtCache.ficheroSiEstaEnDisco(url);
    _future = _fichero == null ? ArtCache.file(url) : null;
  }

  @override
  void initState() {
    super.initState();
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
    final ancho = widget.ancho ?? widget.size;
    final alto = widget.size;
    final cacheW = ArtImage.pixelsDeCache(ancho, dpr);
    final cacheH = ArtImage.pixelsDeCache(alto, dpr);
    final cuadrada = (ancho - alto).abs() < 0.5;

    final radio = widget.radius ??
        EstiloNeoFy.de(context).radioDeCaratula(widget.size);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: SizedBox(
        width: ancho,
        height: alto,
        child: _cuerpo(context, cacheW, cuadrada ? cacheH : null),
      ),
    );
  }

  Widget _cuerpo(BuildContext context, int cacheW, int? cacheH) {
    final local = _fichero;
    if (local != null) {
      return _imagen(context, local, cacheW, cacheH);
    }
    final pendiente = _future;
    if (pendiente == null) return _placeholder(context);
    return FutureBuilder<File?>(
      future: pendiente,
      builder: (context, snap) {
        final fichero = snap.data;
        if (fichero == null) return _placeholder(context);
        return _imagen(context, fichero, cacheW, cacheH);
      },
    );
  }

  Widget _imagen(
    BuildContext context,
    File fichero,
    int cacheW,
    int? cacheH,
  ) {
    final ancho = widget.ancho ?? widget.size;
    final alto = widget.size;
    return Image.file(
      fichero,
      width: ancho,
      height: alto,
      fit: widget.fit,
      cacheWidth: cacheW,
      cacheHeight: cacheH,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) {
        final url = widget.url;
        if (url != null) ArtCache.evict(url);
        return _placeholder(context);
      },
    );
  }

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
