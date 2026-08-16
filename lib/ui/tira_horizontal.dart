import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TiraHorizontal extends StatefulWidget {
  const TiraHorizontal({
    super.key,
    required this.alto,
    required this.itemCount,
    required this.itemBuilder,
    this.centroDeFlechas,
  });

  final double alto;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  final double? centroDeFlechas;

  @override
  State<TiraHorizontal> createState() => _TiraHorizontalState();
}

class _TiraHorizontalState extends State<TiraHorizontal> {
  static const _margen = EdgeInsets.symmetric(horizontal: 16);

  static const _radioFlecha = 18.0;

  final _controlador = ScrollController();

  bool _hayIzquierda = false;
  bool _hayDerecha = false;

  @override
  void initState() {
    super.initState();
    _controlador.addListener(_revisarExtremos);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarExtremos());
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _revisarExtremos() {
    if (!mounted || !_controlador.hasClients) return;
    final pos = _controlador.position;
    final izquierda = pos.pixels > 1;
    final derecha = pos.pixels < pos.maxScrollExtent - 1;
    if (izquierda == _hayIzquierda && derecha == _hayDerecha) return;
    setState(() {
      _hayIzquierda = izquierda;
      _hayDerecha = derecha;
    });
  }

  void _desplazar(double signo) {
    if (!_controlador.hasClients) return;
    final pos = _controlador.position;
    final salto = pos.viewportDimension * 0.8;
    final destino = (pos.pixels + signo * salto)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _controlador.animateTo(destino,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _rueda(PointerSignalEvent evento) {
    if (evento is! PointerScrollEvent || !_controlador.hasClients) return;
    final delta = evento.scrollDelta.dy != 0
        ? evento.scrollDelta.dy
        : evento.scrollDelta.dx;
    final pos = _controlador.position;
    final destino =
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (destino == pos.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(evento, (_) {
      if (_controlador.hasClients) _controlador.jumpTo(destino);
    });
  }

  @override
  Widget build(BuildContext context) {
    final centro = widget.centroDeFlechas ?? widget.alto / 2;
    return SizedBox(
      height: widget.alto,
      child: Listener(
        onPointerSignal: _rueda,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _revisarExtremos());
            return false;
          },
          child: Stack(
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.builder(
                  controller: _controlador,
                  scrollDirection: Axis.horizontal,
                  padding: _margen,
                  itemCount: widget.itemCount,
                  itemBuilder: widget.itemBuilder,
                ),
              ),
              if (_hayIzquierda)
                _Flecha(
                  icono: Icons.chevron_left,
                  tooltip: 'Ver lo anterior',
                  centro: centro,
                  izquierda: true,
                  radio: _radioFlecha,
                  onTap: () => _desplazar(-1),
                ),
              if (_hayDerecha)
                _Flecha(
                  icono: Icons.chevron_right,
                  tooltip: 'Ver más',
                  centro: centro,
                  izquierda: false,
                  radio: _radioFlecha,
                  onTap: () => _desplazar(1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Flecha extends StatelessWidget {
  const _Flecha({
    required this.icono,
    required this.tooltip,
    required this.centro,
    required this.izquierda,
    required this.radio,
    required this.onTap,
  });

  final IconData icono;
  final String tooltip;
  final double centro;
  final bool izquierda;
  final double radio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: izquierda ? 2 : null,
      right: izquierda ? null : 2,
      top: centro - radio,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: radio * 2,
              height: radio * 2,
              child: Icon(icono, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
