import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/spotify_api.dart';

const Color kColorFavorito = Color(0xFFE53935);

class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.likes,
    required this.uri,
    this.size = 20,
  });

  final LikedStore likes;
  final String uri;
  final double size;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with TickerProviderStateMixin {
  late final AnimationController _nivel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 420),
  );

  late final AnimationController _onda = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final CurvedAnimation _llenado = CurvedAnimation(
    parent: _nivel,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  bool _lleno = false;

  @override
  void initState() {
    super.initState();
    _nivel.addStatusListener(_alTerminarElLlenado);
    widget.likes.addListener(_sincronizar);
    _adoptarEstadoDelStore();
    widget.likes.ensureKnown(widget.uri);
  }

  @override
  void didUpdateWidget(covariant LikeButton old) {
    super.didUpdateWidget(old);
    if (old.uri == widget.uri) return;
    _adoptarEstadoDelStore();
    widget.likes.ensureKnown(widget.uri);
  }

  @override
  void dispose() {
    widget.likes.removeListener(_sincronizar);
    _llenado.dispose();
    _nivel.dispose();
    _onda.dispose();
    super.dispose();
  }

  void _alTerminarElLlenado(AnimationStatus s) {
    if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
      _onda.stop();
    }
  }

  void _adoptarEstadoDelStore() {
    _lleno = widget.likes.isSaved(widget.uri) ?? false;
    _onda.stop();
    _nivel.value = _lleno ? 1 : 0;
  }

  void _sincronizar() {
    if (!mounted) return;
    final guardada = widget.likes.isSaved(widget.uri) ?? false;
    if (guardada == _lleno) return;
    setState(_adoptarEstadoDelStore);
  }

  void _animarHacia(bool lleno) {
    _lleno = lleno;
    _onda.repeat();
    if (lleno) {
      _nivel.forward();
    } else {
      _nivel.reverse();
    }
  }

  Future<void> _pulsar() async {
    if (!widget.likes.canModify) {
      _avisarFaltaPermiso();
      return;
    }
    final guardada = widget.likes.isSaved(widget.uri) ?? false;
    _animarHacia(!guardada);
    try {
      await widget.likes.toggle(widget.uri);
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is ApiException && e.isForbidden
          ? 'Spotify no dejó cambiar tus favoritos: ${e.message}'
          : 'No se pudo cambiar: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _avisarFaltaPermiso() {
    final reauth = widget.likes.onReauth;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text(
        'Tu sesión se inició sin permiso para editar favoritos. Hay que volver '
        'a pasar por Spotify una vez; no perderás nada.',
      ),
      action: reauth == null
          ? null
          : SnackBarAction(
              label: 'Iniciar sesión',
              onPressed: () => unawaited(reauth()),
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: _lleno ? 'Quitar de tus me gusta' : 'Guardar en tus me gusta',
      waitDuration: const Duration(milliseconds: 600),
      child: InkResponse(
        onTap: _pulsar,
        radius: 18,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_llenado, _onda]),
                builder: (context, _) {
                  final n = _llenado.value.clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: 1 + 0.22 * math.sin(math.pi * n),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: widget.size,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        if (n > 0)
                          ClipPath(
                            clipper: _RecorteLiquido(nivel: n, fase: _onda.value),
                            child: Icon(
                              Icons.favorite,
                              size: widget.size,
                              color: kColorFavorito,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecorteLiquido extends CustomClipper<Path> {
  const _RecorteLiquido({required this.nivel, required this.fase});

  final double nivel;

  final double fase;

  static const _ondas = 2;

  @override
  Path getClip(Size size) {
    if (nivel >= 1) return Path()..addRect(Offset.zero & size);

    final amplitud = size.height * 0.10 * (1 - nivel);
    final y = size.height * (1 - nivel);

    final path = Path()..moveTo(0, y);
    for (var x = 0.0; x <= size.width; x += 1) {
      final t = x / size.width;
      path.lineTo(x, y + amplitud * math.sin((t * _ondas + fase) * 2 * math.pi));
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_RecorteLiquido old) =>
      old.nivel != nivel || old.fase != fase;
}
