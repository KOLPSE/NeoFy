import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Los atajos de teclado de la ventana, **para toda la app y una sola vez**.
///
/// Vive por encima del shell y no dentro, que es donde estuvo al principio.
/// Se subió aquí cuando había un segundo modo montado en paralelo y el `Focus`
/// del shell de Spotify seguía tragándose el espacio con el otro en pantalla;
/// ese segundo modo ya no está, pero el sitio sigue siendo el bueno: un evento
/// que un `Focus` ignora sube a sus **ancestros** y nunca a un hermano, así que
/// escucharlo arriba es lo único que garantiza que la tecla llegue siempre.
class AtajosDeReproduccion extends StatefulWidget {
  const AtajosDeReproduccion({
    super.key,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  @override
  State<AtajosDeReproduccion> createState() => _AtajosDeReproduccionState();

  /// ¿Está el usuario escribiendo?
  ///
  /// En escritorio, una tecla llega **por dos vías a la vez**: como evento de
  /// teclado al árbol de foco y como texto al campo por el canal de entrada
  /// del motor. Sin esta comprobación, escribir un espacio en un buscador
  /// metería el espacio *y además* pausaría la música.
  static bool get escribiendo {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }
}

class _AtajosDeReproduccionState extends State<AtajosDeReproduccion> {
  final FocusNode _nodo = FocusNode(debugLabel: 'atajos');

  @override
  void dispose() {
    _nodo.dispose();
    super.dispose();
  }

  KeyEventResult _alPulsarTecla(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Las teclas multimedia se registran además a nivel de sistema en el
    // runner de C++ para que funcionen con la app de fondo; esto cubre el caso
    // de tenerla delante, que es el que llega por el árbol de foco.
    switch (event.logicalKey) {
      case LogicalKeyboardKey.mediaPlayPause:
        widget.onPlayPause();
      case LogicalKeyboardKey.mediaTrackNext:
        widget.onNext();
      case LogicalKeyboardKey.mediaTrackPrevious:
        widget.onPrevious();
      case LogicalKeyboardKey.space:
        if (AtajosDeReproduccion.escribiendo) return KeyEventResult.ignored;
        widget.onPlayPause();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _nodo,
      autofocus: true,
      onKeyEvent: _alPulsarTecla,
      child: widget.child,
    );
  }
}
