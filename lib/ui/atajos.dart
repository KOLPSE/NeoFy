import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
