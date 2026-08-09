import 'package:flutter/material.dart';

import '../core/app_mode.dart';
import '../core/settings.dart';

/// Aloja los dos shells (NeoFy y NeoTube) y hace un fundido entre ambos: el
/// saliente se desvanece, el entrante aparece.
///
/// Los dos widgets que recibe (`neofy`, `neotube`) se mantienen **montados**
/// una vez que NeoTube se activa por primera vez — es un segundo modo con su
/// propio estado (scroll, vista seleccionada...), no una pantalla que se
/// reconstruye cada vez que se alterna. `NeoTube` empieza sin montar porque
/// hasta que no se pulsa una vez no hace falta pagar su coste.
///
/// Reacciona a [modoApp] en vez de recibir el modo por parámetro: quien
/// cambia de modo es el botón de cada barra lateral (`ModeToggleText`), que
/// solo toca `Settings.setModo`.
class ModeHost extends StatefulWidget {
  const ModeHost({super.key, required this.neofy, required this.neotube});

  final Widget neofy;
  final Widget neotube;

  @override
  State<ModeHost> createState() => _ModeHostState();
}

class _ModeHostState extends State<ModeHost> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final CurvedAnimation _curva = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOut,
  );

  /// El modo que se ve en reposo (o hacia el que se está animando).
  late AppMode _entrante = modoApp.value;

  /// No nulo solo mientras dura la animación: el modo que se está yendo.
  AppMode? _saliente;

  bool _neotubeMontado = modoApp.value == AppMode.neotube;

  @override
  void initState() {
    super.initState();
    modoApp.addListener(_alCambiarModo);
  }

  @override
  void dispose() {
    modoApp.removeListener(_alCambiarModo);
    _curva.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _alCambiarModo() async {
    final destino = modoApp.value;
    if (destino == _entrante) return;
    setState(() {
      _saliente = _entrante;
      _entrante = destino;
      if (destino == AppMode.neotube) _neotubeMontado = true;
    });
    await _ctrl.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _saliente = null;
      _ctrl.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curva,
      builder: (context, _) => Stack(
        children: [
          if (_neotubeMontado) _capa(modo: AppMode.neotube, child: widget.neotube),
          _capa(modo: AppMode.neofy, child: widget.neofy),
        ],
      ),
    );
  }

  Widget _capa({required AppMode modo, required Widget child}) {
    final double opacidad;
    final bool activo;
    if (modo == _saliente) {
      opacidad = 1 - _curva.value;
      activo = false;
    } else if (modo == _entrante) {
      opacidad = _saliente == null ? 1 : _curva.value;
      activo = true;
    } else {
      // Montado pero en pausa: es el otro modo, invisible.
      opacidad = 0;
      activo = false;
    }
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !activo,
        // ⚠️ `IgnorePointer` solo tapa el **ratón**. El modo que está detrás
        // seguía siendo alcanzable por teclado (su árbol de foco sigue vivo:
        // está montado, no desmontado), y con él un `TextField` invisible podía
        // quedarse el foco y tragarse lo que se escribiera en el modo visible.
        // Excluirlo del foco es la otra mitad del aislamiento; la primera es
        // que los atajos se escuchen por encima de los dos (`ui/atajos.dart`).
        child: ExcludeFocus(
          excluding: !activo,
          // Y que un lector de pantalla tampoco lea el modo que no se ve.
          child: ExcludeSemantics(
            excluding: !activo,
            // El límite de repintado va DENTRO de Opacity y no fuera: así el
            // compositor cachea el shell ya rasterizado (con su fondo,
            // tarjetas, carátulas...) y en cada frame del fundido solo cambia
            // el alfa de esa imagen — no vuelve a pintar cada tarjeta 60 veces
            // en 350 ms.
            child: Opacity(opacity: opacidad, child: RepaintBoundary(child: child)),
          ),
        ),
      ),
    );
  }
}
