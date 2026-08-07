import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Fila horizontal de tarjetas **con alguna forma de moverse por ella**.
///
/// Una `ListView` horizontal metida dentro de una vertical es, con un ratón, un
/// callejón sin salida, y por tres motivos a la vez:
///
/// 1. Flutter no permite arrastrar con el ratón salvo que se le diga
///    expresamente (`dragDevices` trae solo dedo, lápiz y trackpad).
/// 2. La rueda manda el desplazamiento en `dy`, y una lista horizontal solo
///    mira `dx`: el evento se lo acaba quedando la lista de la portada, así que
///    lo que se mueve es la página entera y la tira se queda donde estaba.
/// 3. Sin barra ni flechas, nada indica que haya más contenido a la derecha.
///
/// El resultado era una tira cortada por el borde derecho y sin manera de
/// llegar al resto. Aquí se arregla por las tres vías.
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

  /// A qué altura van las flechas. Por defecto, al centro de la tira; las
  /// tarjetas llevan texto debajo, así que lo natural es pasarle el centro de
  /// la carátula para que no queden bailando sobre las letras.
  final double? centroDeFlechas;

  @override
  State<TiraHorizontal> createState() => _TiraHorizontalState();
}

class _TiraHorizontalState extends State<TiraHorizontal> {
  /// Margen a los lados. Deja hueco para que la primera y la última tarjeta no
  /// queden pegadas al borde ni tapadas del todo por las flechas.
  static const _margen = EdgeInsets.symmetric(horizontal: 16);

  static const _radioFlecha = 18.0;

  final _controlador = ScrollController();

  bool _hayIzquierda = false;
  bool _hayDerecha = false;

  @override
  void initState() {
    super.initState();
    _controlador.addListener(_revisarExtremos);
    // Hasta que no hay layout no se sabe si el contenido cabe o no.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarExtremos());
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  /// ¿Queda contenido a cada lado? De eso depende que se enseñe cada flecha.
  void _revisarExtremos() {
    if (!mounted || !_controlador.hasClients) return;
    final pos = _controlador.position;
    // Un píxel de margen: el final de una animación no siempre cae en el
    // máximo exacto, y una flecha parpadeando sería peor que no tenerla.
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
    // Casi una pantalla, no una entera: dejar una tarjeta a la vista mantiene
    // el hilo de por dónde ibas.
    final salto = pos.viewportDimension * 0.8;
    final destino = (pos.pixels + signo * salto)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _controlador.animateTo(destino,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  /// La rueda del ratón, mapeada al eje horizontal.
  ///
  /// Hay que registrarse en el `PointerSignalResolver` en vez de mover la lista
  /// y ya está: si no, el evento se lo queda **además** la lista vertical de la
  /// portada y se mueven las dos cosas a la vez. Y solo se registra si la tira
  /// puede moverse de verdad hacia ese lado; tocando el extremo, el evento se
  /// deja pasar para que la rueda siga bajando por la página, que es lo que
  /// espera quien está recorriendo la portada.
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
          // Salta cuando cambia el tamaño de la ventana o el número de
          // tarjetas: sin esto, las flechas se quedarían con la respuesta del
          // primer layout.
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
                  // Arrastrar con el ratón es lo primero que prueba todo el
                  // mundo en escritorio, y por defecto no está permitido.
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
