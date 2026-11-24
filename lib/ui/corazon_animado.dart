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

  AnimationController? _onda;

  late final CurvedAnimation _llenado = CurvedAnimation(
    parent: _nivel,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  AnimationController? _resalte;
  bool _hover = false;
  late Listenable _animaciones = _llenado;

  @override
  void initState() {
    super.initState();
    _nivel.addStatusListener(_alTerminarElLlenado);
  }

  void _actualizarAnimaciones() {
    final fuentes = <Listenable>[
      _llenado,
      ?_onda,
      ?_resalte,
    ];
    _animaciones = fuentes.length == 1 ? _llenado : Listenable.merge(fuentes);
  }

  AnimationController _asegurarOnda() {
    final existente = _onda;
    if (existente != null) return existente;
    final c = _onda = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _actualizarAnimaciones();
    return c;
  }

  AnimationController _asegurarResalte() {
    final existente = _resalte;
    if (existente != null) return existente;
    final c = _resalte = AnimationController(
      vsync: this,
      duration: kResaltadoDelCorazon,
      reverseDuration: kResaltadoDelCorazon,
      value: _hover ? 1 : 0,
    );
    _actualizarAnimaciones();
    return c;
  }

  void _alEntrarElRaton() {
    _hover = true;
    if (EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value) {
      final creada = _resalte == null;
      _asegurarResalte().forward();
      if (creada) setState(() {});
    } else if (_resalte != null) {
      _resalte!.value = 1;
    } else {
      setState(() {});
    }
  }

  void _alSalirElRaton() {
    _hover = false;
    if (EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value) {
      _resalte?.reverse();
    } else if (_resalte != null) {
      _resalte!.value = 0;
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant CorazonAnimado old) {
    super.didUpdateWidget(old);
    if (old.lleno == widget.lleno) return;
    if (!EstiloNeoFy.de(context).movimiento.seMueve || modoRendimiento.value) {
      _onda?.stop();
      _nivel.value = widget.lleno ? 1 : 0;
      return;
    }
    _asegurarOnda().repeat();
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
    _onda?.dispose();
    _resalte?.dispose();
    super.dispose();
  }

  void _alTerminarElLlenado(AnimationStatus s) {
    if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
      _onda?.stop();
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
                  animation: _animaciones,
                  builder: (context, _) {
                    final n = _llenado.value.clamp(0.0, 1.0);
                    final resalte =
                        (_resalte?.value ?? (_hover ? 1.0 : 0.0)).clamp(0.0, 1.0);
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
                                fase: _onda?.value ?? 0,
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
