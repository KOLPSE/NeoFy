import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/settings.dart';
import '../core/temas.dart';

class Pulsable extends StatefulWidget {
  const Pulsable({
    super.key,
    required this.child,
    this.escalaPulsada = 0.96,
    this.escalaSobre = 1.02,
    this.activo = true,
  });

  final Widget child;
  final double escalaPulsada;
  final double escalaSobre;
  final bool activo;

  @override
  State<Pulsable> createState() => _PulsableState();
}

class _PulsableState extends State<Pulsable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _escala =
      AnimationController.unbounded(vsync: this, value: 1);

  bool _encima = false;
  bool _pulsado = false;

  @override
  void dispose() {
    _escala.dispose();
    super.dispose();
  }

  Movimiento get _movimiento => EstiloNeoFy.de(context).movimiento;

  bool get _habilitado =>
      widget.activo && _movimiento.seMueve && !modoRendimiento.value;

  double get _destino {
    if (!_habilitado) return 1;
    if (_pulsado) return widget.escalaPulsada;
    if (_encima) return widget.escalaSobre;
    return 1;
  }

  void _asentar({bool rapido = false}) {
    final destino = _destino;
    if (!_habilitado) {
      _escala.value = 1;
      return;
    }
    _escala.animateWith(
      SpringSimulation(
        rapido ? _movimiento.espacialRapido : _movimiento.espacialNormal,
        _escala.value,
        destino,
        _escala.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _encima = true;
        _asentar();
      },
      onExit: (_) {
        _encima = false;
        _pulsado = false;
        _asentar();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _pulsado = true;
          _asentar(rapido: true);
        },
        onPointerUp: (_) {
          _pulsado = false;
          _asentar(rapido: true);
        },
        onPointerCancel: (_) {
          _pulsado = false;
          _asentar(rapido: true);
        },
        child: AnimatedBuilder(
          animation: _escala,
          builder: (context, hijo) => Transform.scale(
            scale: _escala.value,
            filterQuality: FilterQuality.low,
            child: hijo,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Equivale al CSS del desplegable:
/// `transition: max-height 0.3s cubic-bezier(0.2, 0, 0, 1)`.
const Curve kCurvaDesplegable = Cubic(0.2, 0.0, 0.0, 1.0);

const Duration kDuracionDesplegable = Duration(milliseconds: 300);

class EntradaDeLista extends StatefulWidget {
  const EntradaDeLista({
    super.key,
    required this.child,
    this.animar = true,
  });

  final Widget child;
  final bool animar;

  @override
  State<EntradaDeLista> createState() => _EntradaDeListaState();
}

class _EntradaDeListaState extends State<EntradaDeLista>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: kDuracionDesplegable,
    value: widget.animar ? 0 : 1,
  );
  late final CurvedAnimation _alto =
      CurvedAnimation(parent: _c, curve: kCurvaDesplegable);
  late final CurvedAnimation _opacidad = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.7, curve: Curves.linear),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final mueve =
            EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value;
        _c.duration = mueve ? kDuracionDesplegable : Duration.zero;
        _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _alto.dispose();
    _opacidad.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _alto,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _opacidad,
        child: widget.child,
      ),
    );
  }
}

class Plegable extends StatefulWidget {
  const Plegable({
    super.key,
    required this.abierto,
    required this.contenidoAbierto,
    required this.contenidoCerrado,
    this.recorteDirecto = false,
  });

  final bool abierto;
  final Widget contenidoAbierto;
  final Widget contenidoCerrado;
  final bool recorteDirecto;

  @override
  State<Plegable> createState() => _PlegableState();
}

class _PlegableState extends State<Plegable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: kDuracionDesplegable,
    value: widget.abierto ? 1 : 0,
  );
  late final _alto = CurvedAnimation(
    parent: _c,
    curve: kCurvaDesplegable,
    reverseCurve: kCurvaDesplegable,
  );
  late final _opacidad = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 2 / 3, curve: Curves.linear),
    reverseCurve: const Interval(0, 2 / 3, curve: Curves.linear),
  );
  late final _recorte = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(covariant Plegable viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.abierto == widget.abierto) return;
    _lanzar(widget.abierto);
  }

  @override
  void dispose() {
    _alto.dispose();
    _opacidad.dispose();
    _recorte.dispose();
    _c.dispose();
    super.dispose();
  }

  void _lanzar(bool abrir) {
    final mueve =
        EstiloNeoFy.de(context).movimiento.seMueve &&
        !modoRendimiento.value &&
        !MediaQuery.disableAnimationsOf(context);
    if (!mueve) {
      _c.value = abrir ? 1 : 0;
      return;
    }
    _c.duration = widget.recorteDirecto
        ? const Duration(milliseconds: 205)
        : kDuracionDesplegable;
    _c.reverseDuration = widget.recorteDirecto
        ? const Duration(milliseconds: 155)
        : kDuracionDesplegable;
    if (abrir) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: RepaintBoundary(child: widget.contenidoAbierto),
      builder: (context, lista) {
        if (_c.value <= 0 && !widget.abierto) {
          return widget.contenidoCerrado;
        }
        if (widget.recorteDirecto) {
          final opacidadFijada = (1 - _c.value * 5).clamp(0.0, 1.0);
          return Stack(
            children: [
              if (opacidadFijada > 0)
                IgnorePointer(
                  child: Opacity(
                    opacity: opacidadFijada,
                    child: widget.contenidoCerrado,
                  ),
                ),
              SizeTransition(
                sizeFactor: _recorte,
                alignment: Alignment.topCenter,
                child: IgnorePointer(
                  ignoring: !widget.abierto,
                  child: ExcludeFocus(excluding: !widget.abierto, child: lista!),
                ),
              ),
            ],
          );
        }
        return Stack(
          children: [
            SizeTransition(
              sizeFactor: _alto,
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: _opacidad,
                child: lista,
              ),
            ),
            if (_opacidad.value < 0.97)
              IgnorePointer(
                ignoring: _opacidad.value > 0.2,
                child: FadeTransition(
                  opacity: ReverseAnimation(_opacidad),
                  child: widget.contenidoCerrado,
                ),
              ),
          ],
        );
      },
    );
  }
}

class GiroConMuelle extends StatefulWidget {
  const GiroConMuelle({
    super.key,
    required this.abierto,
    required this.child,
  });

  final bool abierto;
  final Widget child;

  @override
  State<GiroConMuelle> createState() => _GiroConMuelleState();
}

class _GiroConMuelleState extends State<GiroConMuelle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: kDuracionDesplegable,
    value: widget.abierto ? 1 : 0,
  );
  late final CurvedAnimation _curva = CurvedAnimation(
    parent: _c,
    curve: kCurvaDesplegable,
  );
  late final Animation<double> _giro = Tween<double>(
    begin: 0.5,
    end: 0,
  ).animate(_curva);

  @override
  void didUpdateWidget(covariant GiroConMuelle viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.abierto == widget.abierto) return;
    final mueve =
        EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value;
    _c.duration = mueve ? kDuracionDesplegable : Duration.zero;
    if (widget.abierto) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _curva.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _giro,
      child: widget.child,
    );
  }
}

class PildoraDeNavegacion extends StatefulWidget {
  const PildoraDeNavegacion({
    super.key,
    required this.seleccionado,
    required this.color,
    required this.child,
  });

  final bool seleccionado;
  final Color color;
  final Widget child;

  @override
  State<PildoraDeNavegacion> createState() => _PildoraDeNavegacionState();
}

class _PildoraDeNavegacionState extends State<PildoraDeNavegacion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _apertura = AnimationController.unbounded(
    vsync: this,
    value: widget.seleccionado ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant PildoraDeNavegacion viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.seleccionado == widget.seleccionado) return;
    final movimiento = EstiloNeoFy.de(context).movimiento;
    final destino = widget.seleccionado ? 1.0 : 0.0;
    if (!movimiento.seMueve || modoRendimiento.value) {
      _apertura.value = destino;
      return;
    }
    _apertura.animateWith(
      SpringSimulation(
        movimiento.espacialRapido,
        _apertura.value,
        destino,
        _apertura.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _apertura.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _apertura,
      builder: (context, hijo) {
        final t = _apertura.value.clamp(0.0, 1.2);
        return Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color.withValues(
                        alpha: t.clamp(0.0, 1.0),
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            hijo!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
