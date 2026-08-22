import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../core/temas.dart';
import 'titulo_desplazable.dart';

class LineaDeArtistas extends StatefulWidget {
  const LineaDeArtistas({
    super.key,
    required this.artistas,
    required this.texto,
    this.estilo,
    this.onAbrir,
  });

  final List<ArtistaDePista> artistas;
  final String texto;
  final TextStyle? estilo;
  final void Function(ArtistaDePista artista)? onAbrir;

  @override
  State<LineaDeArtistas> createState() => _LineaDeArtistasState();
}

class _LineaDeArtistasState extends State<LineaDeArtistas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _avance;
  int? _sobre;

  @override
  void initState() {
    super.initState();
    _avance = AnimationController.unbounded(vsync: this, value: 0);
  }

  @override
  void didUpdateWidget(covariant LineaDeArtistas viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.texto != widget.texto) {
      _avance.stop();
      _avance.value = 0;
      _sobre = null;
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
    if (widget.artistas.isEmpty) {
      return TituloDesplazable(texto: widget.texto, estilo: widget.estilo);
    }

    return LayoutBuilder(
      builder: (context, restricciones) {
        final nombres = [
          for (final a in widget.artistas) a.name,
        ].join(', ');
        final medidor = TextPainter(
          text: TextSpan(text: nombres, style: estilo),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final hueco = restricciones.maxWidth;
        final anchoDelTexto = medidor.width;
        final altoDelTexto = medidor.height;
        medidor.dispose();
        final recorrido = anchoDelTexto - hueco;

        if (recorrido <= 0.5) {
          return _fila(estilo);
        }

        return MouseRegion(
          onEnter: (_) {
            _empezar(recorrido);
          },
          onExit: (_) {
            _sobre = null;
            _volver();
          },
          child: AnimatedBuilder(
            animation: _avance,
            builder: (context, _) {
              final desplazado = _avance.value.clamp(0.0, recorrido);
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
                      child: _fila(estilo),
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

  Widget _fila(TextStyle estilo) {
    final theme = Theme.of(context);
    final tenue = estilo.color ?? theme.colorScheme.onSurfaceVariant;
    final activo = theme.colorScheme.primary;

    final hijos = <Widget>[];
    for (var i = 0; i < widget.artistas.length; i++) {
      if (i > 0) {
        hijos.add(Text(', ', style: estilo, maxLines: 1, softWrap: false));
      }
      final a = widget.artistas[i];
      final sePuede = a.sePuedeAbrir && widget.onAbrir != null;
      final encima = _sobre == i;
      hijos.add(
        MouseRegion(
          cursor: sePuede
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: sePuede
              ? (_) => setState(() => _sobre = i)
              : null,
          onExit: sePuede
              ? (_) => setState(() {
                    if (_sobre == i) _sobre = null;
                  })
              : null,
          child: GestureDetector(
            onTap: sePuede ? () => widget.onAbrir!(a) : null,
            child: Text(
              a.name,
              maxLines: 1,
              softWrap: false,
              style: estilo.copyWith(
                color: encima && sePuede ? activo : tenue,
                decoration:
                    encima && sePuede ? TextDecoration.underline : null,
                decorationColor: activo,
              ),
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: hijos);
  }
}
