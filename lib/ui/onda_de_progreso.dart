import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/settings.dart';
import '../core/temas.dart';

const double kLongitudDeOnda = 40;

const double kGrosorDeOnda = 4;

const double kGrosorDeOndaHover = 9;

const double kAmplitudDeOnda = 3;

const double kHuecoTrasElPulgar = 6;

const double kAnchoDelPulgar = 4;

const double kAltoDelPulgar = 16;

const double kAltoDelPulgarHover = 24;

const double kAlcanceDeLaOnda = 150;

const double kApagadoJuntoAlPulgar = 26;

const double kAltoDeLaBarra = 22;

/// Distancia vertical al centro del trazo para activar el hover del pulgar.
/// Más allá, la zona sigue siendo clicable para el seek, pero no crece.
const double kCercaDelTrazo = 6;

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
    this.clavePista,
  });

  final double valor;
  final double maximo;
  final bool enMarcha;
  final ValueChanged<double>? onCambio;
  final ValueChanged<double>? onFinDelCambio;

  /// Identifica la canción que suena. Al cambiar, la barra vuelve al
  /// principio con una animación en vez de saltar de golpe.
  final Object? clavePista;

  @override
  State<BarraDeProgreso> createState() => _BarraDeProgresoState();
}

class _BarraDeProgresoState extends State<BarraDeProgreso>
    with TickerProviderStateMixin {
  late final AnimationController _fase;
  late final AnimationController _amplitud;
  late final AnimationController _pintada;
  late final AnimationController _sobre;

  bool _arrastrando = false;
  bool _rebobinando = false;
  bool _encima = false;
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
    _sobre = AnimationController.unbounded(vsync: this);
  }

  double get _fraccionDelWidget => widget.maximo <= 0
      ? 0
      : (widget.valor / widget.maximo).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(covariant BarraDeProgreso viejo) {
    super.didUpdateWidget(viejo);
    _sincronizar(cambioDePista: _cambioDePista(viejo));
    _revisarLaOnda();
  }

  bool _cambioDePista(BarraDeProgreso viejo) =>
      widget.clavePista != null &&
      viejo.clavePista != null &&
      widget.clavePista != viejo.clavePista;

  @override
  void dispose() {
    _fase.stop();
    _amplitud.stop();
    _pintada.stop();
    _sobre.stop();
    _fase.dispose();
    _amplitud.dispose();
    _pintada.dispose();
    _sobre.dispose();
    super.dispose();
  }

  void _asentarSobre() {
    final movimiento = EstiloNeoFy.de(context).movimiento;
    final destino = movimiento.seMueve && !modoRendimiento.value
        ? (_arrastrando ? 1.15 : (_encima ? 1.0 : 0.0))
        : 0.0;
    if (!movimiento.seMueve || modoRendimiento.value) {
      _sobre.value = 0;
      return;
    }
    _sobre.animateWith(
      SpringSimulation(
        _arrastrando ? movimiento.espacialRapido : movimiento.espacialNormal,
        _sobre.value,
        destino,
        _sobre.velocity,
      ),
    );
  }

  void _sincronizar({bool cambioDePista = false}) {
    final nueva = _fraccionDelWidget;
    final anterior = _objetivo;
    _objetivo = nueva;

    final acabaDeTerminar = !_arrastrando &&
        anterior >= kSeAcabaLaCancion &&
        nueva <= kVuelveAEmpezar;

    // Al cambiar de canción la barra estaba donde el usuario la dejara y la
    // nueva empieza de cero: ese salto es el "popeo" que se veía. Se
    // rebobina con el mismo muelle que al terminar una canción.
    final empiezaDeCero = cambioDePista &&
        !_arrastrando &&
        nueva <= kVuelveAEmpezar &&
        _pintada.value > kVuelveAEmpezar;

    // El reproductor a veces pone el progreso a 0 un fotograma antes de
    // cambiar el URI, y a veces apaga `enMarcha` en ese mismo fotograma.
    // Si esperamos al URI o a que siga sonando, `_pintada` ya está en 0 y
    // el rebobinado no tiene de dónde partir.
    final saltoAlCero = !_arrastrando &&
        nueva <= 0.02 &&
        _pintada.value > kVuelveAEmpezar;

    if ((acabaDeTerminar || empiezaDeCero || saltoAlCero) && !_rebobinando) {
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
          SpringSimulation(movimiento.espacialNormal, _pintada.value, 0, 0),
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

        return SizedBox(
          height: kAltoDeLaBarra,
          child: MouseRegion(
            onHover: (e) {
              // Solo crece el pulgar si el cursor está cerca del trazo; el
              // resto de la zona alta sigue sirviendo para hacer seek.
              final cerca =
                  (e.localPosition.dy - kAltoDeLaBarra / 2).abs() <=
                      kCercaDelTrazo;
              if (cerca == _encima) return;
              _encima = cerca;
              _asentarSobre();
            },
            onExit: (_) {
              if (!_encima) return;
              _encima = false;
              _asentarSobre();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) {
                _arrastrando = true;
                if (_pintada.isAnimating) _pintada.stop();
                _asentarSobre();
                _revisarLaOnda();
                avisar(d.localPosition, fin: false);
              },
              onHorizontalDragUpdate: (d) =>
                  avisar(d.localPosition, fin: false),
              onHorizontalDragEnd: (_) {
                _arrastrando = false;
                _asentarSobre();
                _revisarLaOnda();
                widget.onFinDelCambio?.call(widget.valor);
                _lanzarAvance();
              },
              onTapUp: (d) {
                avisar(d.localPosition, fin: false);
                avisar(d.localPosition, fin: true);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: kMargenLateral),
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                      [_fase, _amplitud, _pintada, _sobre]),
                  builder: (context, _) => CustomPaint(
                    size: Size(ancho, kAltoDeLaBarra),
                    painter: PintorDeOnda(
                      fraccion: _pintada.value.clamp(0.0, 1.0),
                      fase: _fase.value,
                      amplitud: _amplitud.value,
                      sobre: _sobre.value.clamp(0.0, 1.2),
                      activo: esquema.primary,
                      pista: esquema.outlineVariant,
                    ),
                  ),
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
    required this.sobre,
    required this.activo,
    required this.pista,
  });

  final double fraccion;
  final double fase;
  final double amplitud;
  final double sobre;
  final Color activo;
  final Color pista;

  /// El trazo no cambia con el hover: solo crece el pulgar.
  double get _grosor => kGrosorDeOnda;

  double get _altoPulgar =>
      kAltoDelPulgar + (kAltoDelPulgarHover - kAltoDelPulgar) * sobre;

  @override
  void paint(Canvas canvas, Size size) {
    final medio = size.height / 2;
    final utilizable = size.width - kAnchoDelPulgar;
    final recorrido = kAnchoDelPulgar / 2 + utilizable * fraccion;

    final trazoActivo = Paint()
      ..color = activo
      ..strokeWidth = _grosor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final trazoPista = Paint()
      ..color = pista
      ..strokeWidth = _grosor
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
            height: _altoPulgar,
          ),
          const Radius.circular(kAnchoDelPulgar / 2),
        ),
        Paint()..color = activo,
      );
    }
  }

  double _alturaDeLaOnda(double alto) {
    final cabe = (alto - _grosor) / 2;
    return kAmplitudDeOnda < cabe ? kAmplitudDeOnda : cabe;
  }

  @override
  bool shouldRepaint(PintorDeOnda viejo) =>
      viejo.fraccion != fraccion ||
      viejo.fase != fase ||
      viejo.amplitud != amplitud ||
      viejo.sobre != sobre ||
      viejo.activo != activo ||
      viejo.pista != pista;
}
