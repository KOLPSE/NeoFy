import 'dart:io';

import 'package:flutter/material.dart';

import '../core/art_cache.dart';
import '../core/settings.dart';

class ArtImage extends StatefulWidget {
  const ArtImage({
    super.key,
    required this.url,
    this.urlGrande,
    required this.size,
    this.radius = 4,
  });

  final String? url;

  final String? urlGrande;

  final double size;
  final double radius;

  static const int _escalonPequeno = 64;

  @override
  State<ArtImage> createState() => _ArtImageState();
}

class _ArtImageState extends State<ArtImage> {
  Future<File?>? _future;
  String? _elegida;

  String? _urlPara(double dpr) {
    final pixeles = widget.size * dpr;
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
        oldWidget.size != widget.size) {
      _resolve();
    }
  }

  void _resolve() {
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
