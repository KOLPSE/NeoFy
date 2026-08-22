import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../core/temas.dart';

const double kVelocidadDelTitulo = 45;

const Duration kVueltaDelTitulo = Duration(milliseconds: 260);

class TituloDesplazable extends StatefulWidget {
  const TituloDesplazable({
    super.key,
    required this.texto,
    this.estilo,
  });

  final String texto;
  final TextStyle? estilo;

  @override
  State<TituloDesplazable> createState() => _TituloDesplazableState();
}

class _TituloDesplazableState extends State<TituloDesplazable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _avance;

  bool _encima = false;

  @override
  void initState() {
    super.initState();
    _avance = AnimationController.unbounded(vsync: this, value: 0);
  }

  @override
  void didUpdateWidget(covariant TituloDesplazable viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.texto != widget.texto) {
      _avance.stop();
      _avance.value = 0;
    }
  }

  @override
  void dispose() {
    _avance.dispose();
    super.dispose();
  }

  bool get _puedeMoverse =>
      EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value;

  void _empezar(double recorrido) {
    if (!_puedeMoverse || recorrido <= 0) return;
    final velocidad =
        kVelocidadDelTitulo * EstiloNeoFy.de(context).movimiento.velocidad;
    final quedan = recorrido - _avance.value;
    if (quedan <= 0) return;
    _avance.animateTo(
      recorrido,
      duration: Duration(milliseconds: (quedan / velocidad * 1000).round()),
      curve: Curves.linear,
    );
  }

  void _volver() {
    if (!_puedeMoverse) {
      _avance.value = 0;
      return;
    }
    _avance.animateTo(0, duration: kVueltaDelTitulo, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final estilo =
        DefaultTextStyle.of(context).style.merge(widget.estilo);

    return LayoutBuilder(
      builder: (context, restricciones) {
        final medidor = TextPainter(
          text: TextSpan(text: widget.texto, style: estilo),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final hueco = restricciones.maxWidth;
        final anchoDelTexto = medidor.width;
        final altoDelTexto = medidor.height;
        medidor.dispose();
        final recorrido = anchoDelTexto - hueco;

        if (recorrido <= 0.5) {
          return Text(
            widget.texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.estilo,
          );
        }

        return MouseRegion(
          onEnter: (_) {
            _encima = true;
            _empezar(recorrido);
          },
          onExit: (_) {
            _encima = false;
            _volver();
          },
          child: AnimatedBuilder(
            animation: _avance,
            builder: (context, _) {
              final desplazado = _avance.value.clamp(0.0, recorrido);
              if (!_encima && desplazado <= 0.5) {
                return Text(
                  widget.texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.estilo,
                );
              }
              return SizedBox(
                height: altoDelTexto,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: anchoDelTexto,
                    maxWidth: anchoDelTexto,
                    minHeight: altoDelTexto,
                    maxHeight: altoDelTexto,
                    child: Transform.translate(
                      offset: Offset(-desplazado, 0),
                      child: Text(
                        widget.texto,
                        maxLines: 1,
                        softWrap: false,
                        style: widget.estilo,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
