import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color kColorFavorito = Color(0xFFE53935);

class CorazonAnimado extends StatefulWidget {
  const CorazonAnimado({
    super.key,
    required this.lleno,
    required this.tooltip,
    required this.onTap,
    this.size = 20,
  });

  final bool lleno;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  State<CorazonAnimado> createState() => _CorazonAnimadoState();
}

class _CorazonAnimadoState extends State<CorazonAnimado>
    with TickerProviderStateMixin {
  late final AnimationController _nivel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 420),
    value: widget.lleno ? 1 : 0,
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

  @override
  void initState() {
    super.initState();
    _nivel.addStatusListener(_alTerminarElLlenado);
  }

  @override
  void didUpdateWidget(covariant CorazonAnimado old) {
    super.didUpdateWidget(old);
    if (old.lleno == widget.lleno) return;
    _onda.repeat();
    if (widget.lleno) {
      _nivel.forward();
    } else {
      _nivel.reverse();
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkResponse(
        onTap: widget.onTap,
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
