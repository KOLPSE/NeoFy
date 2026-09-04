import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/settings.dart';
import '../core/temas.dart';

/// Botones de la barra de reproducción con el movimiento de Material 3
/// Expressive: el de play crece en vertical al pasar el ratón y se achata al
/// pulsar; los de salto empujan el icono en su propia dirección. Todo va con
/// los muelles del tema activo y se apaga con el modo rendimiento.

class BotonPlayExpresivo extends StatefulWidget {
  const BotonPlayExpresivo({
    super.key,
    required this.sonando,
    required this.onPressed,
    required this.tooltip,
  });

  final bool sonando;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  State<BotonPlayExpresivo> createState() => _BotonPlayExpresivoState();
}

class _BotonPlayExpresivoState extends State<BotonPlayExpresivo>
    with SingleTickerProviderStateMixin {
  /// 0 = reposo, 1 = hover, -1 = pulsado.
  late final AnimationController _impulso =
      AnimationController.unbounded(vsync: this);

  bool _encima = false;
  bool _pulsado = false;

  @override
  void dispose() {
    _impulso.dispose();
    super.dispose();
  }

  Movimiento get _movimiento => EstiloNeoFy.de(context).movimiento;

  bool get _habilitado => _movimiento.seMueve && !modoRendimiento.value;

  void _asentar({bool rapido = false}) {
    final destino = !_habilitado
        ? 0.0
        : _pulsado
            ? -1.0
            : _encima
                ? 1.0
                : 0.0;
    if (!_habilitado) {
      _impulso.value = 0;
      return;
    }
    _impulso.animateWith(
      SpringSimulation(
        rapido ? _movimiento.espacialRapido : _movimiento.espacialNormal,
        _impulso.value,
        destino,
        _impulso.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
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
        child: Tooltip(
          message: widget.tooltip,
          child: AnimatedBuilder(
            animation: _impulso,
            builder: (context, _) {
              final t = _impulso.value;
              // Hover: estira hacia arriba y abajo; pulsar: achata y ensancha
              // un pelo. Sutil: ±4 px de alto y ∓2 px de ancho como mucho.
              final alto = 40 + 4 * t.clamp(-1.0, 1.0);
              final ancho = 40 - 2 * t.clamp(-1.0, 1.0);
              return SizedBox(
                width: 44,
                height: 48,
                child: Center(
                  child: Material(
                    color: esquema.primary,
                    borderRadius: BorderRadius.circular(999),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onPressed,
                      customBorder: const StadiumBorder(),
                      child: SizedBox(
                        width: ancho,
                        height: alto,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (hijo, animacion) =>
                                FadeTransition(
                              opacity: animacion,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.7, end: 1)
                                    .animate(animacion),
                                child: hijo,
                              ),
                            ),
                            child: Icon(
                              widget.sonando ? Icons.pause : Icons.play_arrow,
                              key: ValueKey(widget.sonando),
                              color: esquema.onPrimary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Botón de salto (anterior/siguiente). Al pasar el ratón, el icono se
/// desplaza un par de píxeles en la dirección del salto y al pulsar se
/// hunde; cada dirección tiene así su propio gesto.
class BotonSaltoExpresivo extends StatefulWidget {
  const BotonSaltoExpresivo({
    super.key,
    required this.icono,
    required this.onPressed,
    required this.tooltip,
    required this.direccion,
  });

  final IconData icono;
  final VoidCallback onPressed;
  final String tooltip;

  /// -1 para "anterior", 1 para "siguiente".
  final double direccion;

  @override
  State<BotonSaltoExpresivo> createState() => _BotonSaltoExpresivoState();
}

class _BotonSaltoExpresivoState extends State<BotonSaltoExpresivo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _impulso =
      AnimationController.unbounded(vsync: this);

  bool _encima = false;
  bool _pulsado = false;

  @override
  void dispose() {
    _impulso.dispose();
    super.dispose();
  }

  Movimiento get _movimiento => EstiloNeoFy.de(context).movimiento;

  bool get _habilitado => _movimiento.seMueve && !modoRendimiento.value;

  void _asentar({bool rapido = false}) {
    final destino = !_habilitado
        ? 0.0
        : _pulsado
            ? -1.0
            : _encima
                ? 1.0
                : 0.0;
    if (!_habilitado) {
      _impulso.value = 0;
      return;
    }
    _impulso.animateWith(
      SpringSimulation(
        rapido ? _movimiento.espacialRapido : _movimiento.espacialNormal,
        _impulso.value,
        destino,
        _impulso.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
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
          animation: _impulso,
          builder: (context, _) {
            final t = _impulso.value.clamp(-1.0, 1.0);
            final empuje = t > 0 ? 2.5 * t : 0.0;
            final escala = t < 0 ? 1 + 0.12 * t : 1.0;
            return IconButton(
              tooltip: widget.tooltip,
              onPressed: widget.onPressed,
              icon: Transform.translate(
                offset: Offset(widget.direccion * empuje, 0),
                child: Transform.scale(
                  scale: escala,
                  child: Icon(widget.icono, color: esquema.onSurface),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
