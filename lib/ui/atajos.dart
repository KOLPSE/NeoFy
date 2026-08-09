import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';

/// Los atajos de teclado de la ventana, **para toda la app y una sola vez**.
///
/// ⚠️ Antes vivían dentro de `AppShell`, y ahí estaba el fallo que se notaba
/// al usar NeoTube: los dos shells siguen montados a la vez (ver `ModeHost`,
/// que los cruza con un fundido y mantiene vivo el estado de los dos), así que
/// el `Focus` de NeoFy seguía escuchando el teclado con NeoTube en pantalla.
/// El espacio pausaba o reanudaba Spotify desde NeoTube — que es exactamente
/// lo reportado: "le doy al espacio y se reproduce una canción de NeoFy".
///
/// `IgnorePointer` no lo tapaba porque solo bloquea el ratón: un evento de
/// teclado no pasa por el árbol de punteros, va por el de foco. Y no bastaba
/// con que cada shell filtrara por su cuenta, porque un evento que un `Focus`
/// ignora sube a sus **ancestros**, nunca a un hermano: NeoTube no lo habría
/// recibido igualmente. La única forma de que la tecla llegue siempre a quien
/// manda es escucharla por encima de los dos y repartirla desde ahí.
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
  /// Un nodo propio en vez de `autofocus` a secas: hay que poder recuperar el
  /// foco a mano al cambiar de modo (ver [_alCambiarDeModo]).
  final FocusNode _nodo = FocusNode(debugLabel: 'atajos');

  @override
  void initState() {
    super.initState();
    modoApp.addListener(_alCambiarDeModo);
  }

  @override
  void dispose() {
    modoApp.removeListener(_alCambiarDeModo);
    _nodo.dispose();
    super.dispose();
  }

  /// ⚠️ Al cambiar de modo, el `ExcludeFocus` de `ModeHost` desengancha el foco
  /// de todo el shell que se va. Si quien lo tenía era un descendiente suyo, el
  /// foco sube al *scope* raíz — que está **por encima** de este nodo, así que
  /// las teclas dejarían de llegar aquí y el espacio se quedaría mudo hasta que
  /// el usuario pulsara algo. Se recupera en cuanto pasa.
  void _alCambiarDeModo() {
    if (!mounted) return;
    // Al final del frame: durante el cambio, `ModeHost` todavía está montando
    // el shell entrante y pedir foco a mitad no se sostiene.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_nodo.hasFocus && !AtajosDeReproduccion.escribiendo) {
        _nodo.requestFocus();
      }
    });
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
