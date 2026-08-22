import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/settings.dart';
import '../core/temas.dart';

const double kLongitudDeOnda = 40;

const double kGrosorDeOnda = 4;

const double kAmplitudDeOnda = 3;

const double kHuecoTrasElPulgar = 6;

const double kAnchoDelPulgar = 4;

const double kAltoDelPulgar = 16;

const double kAlcanceDeLaOnda = 150;

const double kApagadoJuntoAlPulgar = 26;

const double kAltoDeLaBarra = 22;

const double kMargenLateral = 10;

const double kSeAcabaLaCancion = 0.995;

const double kVuelveAEmpezar = 0.15;

/// El progreso del reproductor llega a tirones (~250 ms). Por debajo de esta
/// holgura la barra sigue ella sola a tiempo real; un recálculo se vería
/// a saltos. Un seek de verdad queda por encima y ahí sí se coloca.
const double kHolguraDeSincroniaMs = 400;

class BarraDeProgreso extends StatefulWidget {
  const BarraDeProgreso({
    super.key,
    required this.valor,
    required this.maximo,
    required this.enMarcha,
    required this.onCambio,
    required this.onFinDelCambio,
  });

  final double valor;
  final double maximo;
  final bool enMarcha;
  final ValueChanged<double>? onCambio;
  final ValueChanged<double>? onFinDelCambio;

  @override
  State<BarraDeProgreso> createState() => _BarraDeProgresoState();
}

class _BarraDeProgresoState extends State<BarraDeProgreso>
    with TickerProviderStateMixin {
  late final AnimationController _fase;
  late final AnimationController _amplitud;
  late final AnimationController _pintada;

  bool _arrastrando = false;
  bool _rebobinando = false;
  late double _objetivo = _fraccionDelWidget;

  @override
  void initState() {
    super.initState();
    _fase = AnimationController.unbounded(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _amplitud = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: 0,
    );
    _pintada = AnimationController.unbounded(
      vsync: this,
      value: _fraccionDelWidget,
    );
  }

  double get _fraccionDelWidget => widget.maximo <= 0
      ? 0
      : (widget.valor / widget.maximo).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(covariant BarraDeProgreso viejo) {
    super.didUpdateWidget(viejo);
    _sincronizar();
    _revisarLaOnda();
  }

  @override
  void dispose() {
    _fase.stop();
    _amplitud.stop();
    _pintada.stop();
    _fase.dispose();
    _amplitud.dispose();
    _pintada.dispose();
    super.dispose();
  }

  void _sincronizar() {
    final nueva = _fraccionDelWidget;
    final anterior = _objetivo;
    _objetivo = nueva;

    final acabaDeTerminar = !_arrastrando &&
        anterior >= kSeAcabaLaCancion &&
        nueva <= kVuelveAEmpezar;

    if (acabaDeTerminar && !_rebobinando) {
      _rebobinar();
      return;
    }
    if (_rebobinando) return;

    if (_arrastrando || !widget.enMarcha) {
      if (_pintada.isAnimating) _pintada.stop();
      _pintada.value = nueva;
      return;
    }

    final errorMs = (nueva - _pintada.value).abs() * widget.maximo;
    if (errorMs > kHolguraDeSincroniaMs) {
      if (_pintada.isAnimating) _pintada.stop();
      _pintada.value = nueva;
    }
    _lanzarAvance();
  }

  void _lanzarAvance() {
    if (_arrastrando || _rebobinando || !widget.enMarcha) return;
    if (widget.maximo <= 0) {
      _pintada.value = 0;
      return;
    }
    final restoMs = (1.0 - _pintada.value) * widget.maximo;
    if (restoMs <= 16) {
      if (_pintada.isAnimating) _pintada.stop();
      _pintada.value = 1.0;
      return;
    }
    if (_pintada.isAnimating) return;
    _pintada.animateTo(
      1.0,
      duration: Duration(milliseconds: restoMs.round()),
      curve: Curves.linear,
    );
  }

  void _rebobinar() {
    final movimiento = EstiloNeoFy.de(context).movimiento;
    if (!movimiento.seMueve || modoRendimiento.value) {
      _pintada.value = _objetivo;
      _lanzarAvance();
      return;
    }
    _rebobinando = true;
    _amplitud.value = 0;
    _fase.stop();
    _pintada
        .animateWith(
          SpringSimulation(movimiento.espacialRapido, _pintada.value, 0, -1.4),
        )
        .whenCompleteOrCancel(() {
      if (!mounted) return;
      _rebobinando = false;
      _pintada.value = _objetivo;
      _lanzarAvance();
    });
  }

  void _revisarLaOnda() {
    final debeOndular = _hayOnda &&
        widget.enMarcha &&
        !_arrastrando &&
        !_rebobinando &&
        _objetivo < kSeAcabaLaCancion &&
        !modoRendimiento.value;

    if (debeOndular) {
      if (!_fase.isAnimating) _fase.repeat(min: 0, max: 1, period: _periodo);
      if (_amplitud.value != 1) _amplitud.forward();
    } else {
      if (_fase.isAnimating) _fase.stop();
      if (_amplitud.value != 0) _amplitud.reverse();
    }
  }

  Duration get _periodo => const Duration(seconds: 1);

  bool get _hayOnda =>
      EstiloNeoFy.de(context).progreso == EstiloDeProgreso.onda;

  @override
  Widget build(BuildContext context) {
    _revisarLaOnda();
    _lanzarAvance();
    final esquema = Theme.of(context).colorScheme;

    if (!_hayOnda) {
      return AnimatedBuilder(
        animation: _pintada,
        builder: (context, _) => SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: (_pintada.value * widget.maximo).clamp(0.0, widget.maximo),
            max: widget.maximo,
            onChangeStart: widget.onCambio == null
                ? null
                : (_) {
                    _arrastrando = true;
                    if (_pintada.isAnimating) _pintada.stop();
                  },
            onChanged: widget.onCambio == null
                ? null
                : (v) {
                    _pintada.value =
                        widget.maximo <= 0 ? 0 : v / widget.maximo;
                    widget.onCambio!(v);
                  },
            onChangeEnd: (v) {
              _arrastrando = false;
              widget.onFinDelCambio?.call(v);
              _lanzarAvance();
            },
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final ancho = (cons.maxWidth - kMargenLateral * 2).clamp(1.0, 1e6);

        void avisar(Offset local, {required bool fin}) {
          if (widget.onCambio == null) return;
          final fraccion =
              ((local.dx - kMargenLateral) / ancho).clamp(0.0, 1.0);
          final valor = fraccion * widget.maximo;
          if (fin) {
            widget.onFinDelCambio?.call(valor);
          } else {
            widget.onCambio?.call(valor);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            _arrastrando = true;
            if (_pintada.isAnimating) _pintada.stop();
            _revisarLaOnda();
            avisar(d.localPosition, fin: false);
          },
          onHorizontalDragUpdate: (d) => avisar(d.localPosition, fin: false),
          onHorizontalDragEnd: (_) {
            _arrastrando = false;
            _revisarLaOnda();
            widget.onFinDelCambio?.call(widget.valor);
            _lanzarAvance();
          },
          onTapUp: (d) {
            avisar(d.localPosition, fin: false);
            avisar(d.localPosition, fin: true);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kMargenLateral),
            child: AnimatedBuilder(
              animation: Listenable.merge([_fase, _amplitud, _pintada]),
              builder: (context, _) => CustomPaint(
                size: Size(ancho, kAltoDeLaBarra),
                painter: PintorDeOnda(
                  fraccion: _pintada.value.clamp(0.0, 1.0),
                  fase: _fase.value,
                  amplitud: _amplitud.value,
                  activo: esquema.primary,
                  pista: esquema.outlineVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

double envolventeDeLaOnda(double atrasDelCabezal) {
  if (atrasDelCabezal <= 0 || atrasDelCabezal >= kAlcanceDeLaOnda) return 0;
  final sube = (atrasDelCabezal / kApagadoJuntoAlPulgar).clamp(0.0, 1.0);
  final baja = ((kAlcanceDeLaOnda - atrasDelCabezal) /
          (kAlcanceDeLaOnda - kApagadoJuntoAlPulgar))
      .clamp(0.0, 1.0);
  final v = sube < baja ? sube : baja;
  return v * v * (3 - 2 * v);
}

class PintorDeOnda extends CustomPainter {
  const PintorDeOnda({
    required this.fraccion,
    required this.fase,
    required this.amplitud,
    required this.activo,
    required this.pista,
  });

  final double fraccion;
  final double fase;
  final double amplitud;
  final Color activo;
  final Color pista;

  @override
  void paint(Canvas canvas, Size size) {
    final medio = size.height / 2;
    final utilizable = size.width - kAnchoDelPulgar;
    final recorrido = kAnchoDelPulgar / 2 + utilizable * fraccion;

    final trazoActivo = Paint()
      ..color = activo
      ..strokeWidth = kGrosorDeOnda
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final trazoPista = Paint()
      ..color = pista
      ..strokeWidth = kGrosorDeOnda
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final finDeLaOnda =
        (recorrido - kAnchoDelPulgar / 2 - kHuecoTrasElPulgar).clamp(0.0, recorrido);
    final desdePista =
        recorrido + kAnchoDelPulgar / 2 + kHuecoTrasElPulgar;
    final hastaPista = size.width - kAnchoDelPulgar / 2;
    if (desdePista < hastaPista) {
      canvas.drawLine(
        Offset(desdePista, medio),
        Offset(hastaPista, medio),
        trazoPista,
      );
    }

    if (finDeLaOnda > kAnchoDelPulgar) {
      final alturaOnda = _alturaDeLaOnda(size.height) * amplitud;

      double alturaEn(double x) =>
          medio +
          math.sin(2 * math.pi * (x / kLongitudDeOnda - fase)) *
              alturaOnda *
              envolventeDeLaOnda(finDeLaOnda - x);

      final arranque = kAnchoDelPulgar / 2;
      final camino = Path()..moveTo(arranque, alturaEn(arranque));
      const paso = 2.0;
      for (var x = arranque + paso; x < finDeLaOnda; x += paso) {
        camino.lineTo(x, alturaEn(x));
      }
      camino.lineTo(finDeLaOnda, medio);
      canvas.drawPath(camino, trazoActivo);
    }

    {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(recorrido, medio),
            width: kAnchoDelPulgar,
            height: kAltoDelPulgar,
          ),
          const Radius.circular(kAnchoDelPulgar / 2),
        ),
        Paint()..color = activo,
      );
    }
  }

  double _alturaDeLaOnda(double alto) {
    final cabe = (alto - kGrosorDeOnda) / 2;
    return kAmplitudDeOnda < cabe ? kAmplitudDeOnda : cabe;
  }


  @override
  bool shouldRepaint(PintorDeOnda viejo) =>
      viejo.fraccion != fraccion ||
      viejo.fase != fase ||
      viejo.amplitud != amplitud ||
      viejo.activo != activo ||
      viejo.pista != pista;
}
