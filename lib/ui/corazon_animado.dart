import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../core/temas.dart';

const Color kColorFavorito = Color(0xFFE53935);

const Color kColorFavoritoResaltado = Color(0xFFFF6B6B);

const Duration kResaltadoDelCorazon = Duration(milliseconds: 160);

class CorazonAnimado extends StatefulWidget {
  const CorazonAnimado({
    super.key,
    required this.lleno,
    required this.tooltip,
    required this.onTap,
    this.size = 20,
    this.caja = 36,
  });

  final bool lleno;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double caja;

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

  late final AnimationController _resalte;

  @override
  void initState() {
    super.initState();
    _resalte = AnimationController(
      vsync: this,
      duration: kResaltadoDelCorazon,
      reverseDuration: kResaltadoDelCorazon,
      value: 0,
    );
    _nivel.addStatusListener(_alTerminarElLlenado);
  }

  void _alEntrarElRaton() {
    if (EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value) {
      _resalte.forward();
    } else {
      _resalte.value = 1;
    }
  }

  void _alSalirElRaton() {
    if (EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value) {
      _resalte.reverse();
    } else {
      _resalte.value = 0;
    }
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
    _resalte.dispose();
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
      child: MouseRegion(
        onEnter: (_) => _alEntrarElRaton(),
        onExit: (_) => _alSalirElRaton(),
        child: InkResponse(
          onTap: widget.onTap,
          radius: 18,
          child: SizedBox(
            width: widget.caja,
            height: widget.caja,
            child: Center(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_llenado, _onda, _resalte]),
                  builder: (context, _) {
                    final n = _llenado.value.clamp(0.0, 1.0);
                    final resalte = _resalte.value.clamp(0.0, 1.0);
                    return Transform.scale(
                      scale:
                          (1 + 0.22 * math.sin(math.pi * n)) *
                          (1 + 0.08 * resalte),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: widget.size,
                            color: Color.lerp(
                              theme.colorScheme.onSurfaceVariant,
                              kColorFavorito,
                              resalte,
                            ),
                          ),
                          if (n > 0)
                            ClipPath(
                              clipper: _RecorteLiquido(
                                nivel: n,
                                fase: _onda.value,
                              ),
                              child: Icon(
                                Icons.favorite,
                                size: widget.size,
                                color: Color.lerp(
                                  kColorFavorito,
                                  kColorFavoritoResaltado,
                                  resalte,
                                ),
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
