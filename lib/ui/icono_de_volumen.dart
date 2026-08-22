import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/settings.dart';
import '../core/temas.dart';

class IconoDeVolumen extends StatefulWidget {
  const IconoDeVolumen({
    super.key,
    required this.volumen,
    required this.muteado,
    this.tamano = 20,
    this.color,
  });

  final double volumen;
  final bool muteado;
  final double tamano;
  final Color? color;

  @override
  State<IconoDeVolumen> createState() => _IconoDeVolumenState();
}

class _IconoDeVolumenState extends State<IconoDeVolumen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dibujo =
      AnimationController.unbounded(vsync: this, value: _destino);

  @override
  void didUpdateWidget(covariant IconoDeVolumen viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.volumen == widget.volumen && viejo.muteado == widget.muteado) {
      return;
    }
    _asentar();
  }

  @override
  void dispose() {
    _dibujo.dispose();
    super.dispose();
  }

  /// 0 = mute, 1 = una onda, 2 = las dos. No son tres iconos: es un
  /// continuo, para que el cambio no sea un recorte de imagen a imagen.
  double get _destino {
    if (widget.muteado || widget.volumen <= 0) return 0;
    if (widget.volumen < 50) return 0.6 + 0.4 * (widget.volumen / 50);
    return 1.0 + (widget.volumen - 50) / 50;
  }

  void _asentar() {
    final movimiento = EstiloNeoFy.de(context).movimiento;
    if (!movimiento.seMueve || modoRendimiento.value) {
      _dibujo.value = _destino;
      return;
    }
    _dibujo.animateWith(
      SpringSimulation(
        movimiento.efecto,
        _dibujo.value,
        _destino,
        _dibujo.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color;
    return AnimatedBuilder(
      animation: _dibujo,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.tamano),
        painter: PintorDeVolumen(
          nivel: _dibujo.value,
          color: color ?? Colors.white,
        ),
      ),
    );
  }
}

class PintorDeVolumen extends CustomPainter {
  const PintorDeVolumen({required this.nivel, required this.color});

  final double nivel;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final s = size.width;
    final altavoz = Path()
      ..moveTo(s * 0.18, s * 0.40)
      ..lineTo(s * 0.34, s * 0.40)
      ..lineTo(s * 0.52, s * 0.24)
      ..lineTo(s * 0.52, s * 0.76)
      ..lineTo(s * 0.34, s * 0.60)
      ..lineTo(s * 0.18, s * 0.60)
      ..close();
    canvas.drawPath(altavoz, fill);

    final ondas = nivel.clamp(0.0, 2.0);
    if (ondas > 0.02) {
      final a1 = (ondas / 0.9).clamp(0.0, 1.0);
      _arco(canvas, Offset(s * 0.56, s * 0.50), s * 0.16, a1, paint);
      final a2 = ((ondas - 1.0) / 0.9).clamp(0.0, 1.0);
      if (a2 > 0) {
        _arco(canvas, Offset(s * 0.56, s * 0.50), s * 0.28, a2, paint);
      }
    }

    final mute = (1.0 - ondas).clamp(0.0, 1.0);
    if (mute > 0.02) {
      final slash = Paint()
        ..color = color.withValues(alpha: mute)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.10
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(s * 0.22, s * 0.22),
        Offset(
          s * 0.22 + (s * 0.56) * mute,
          s * 0.22 + (s * 0.56) * mute,
        ),
        slash,
      );
    }
  }

  void _arco(Canvas canvas, Offset c, double radio, double alpha, Paint base) {
    final p = Paint()
      ..color = base.color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = base.strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radio * (0.85 + 0.15 * alpha)),
      -math.pi / 3,
      2 * math.pi / 3,
      false,
      p,
    );
  }

  @override
  bool shouldRepaint(PintorDeVolumen viejo) =>
      viejo.nivel != nivel || viejo.color != color;
}
