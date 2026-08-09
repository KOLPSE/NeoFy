import 'package:flutter/material.dart';

import '../core/app_mode.dart';
import '../core/settings.dart';

/// El nombre de la app, convertido en el interruptor entre NeoFy y NeoTube.
///
/// Cada instancia vive dentro de **su propio** shell (una en la barra lateral
/// de NeoFy, otra en la de NeoTube) y en reposo muestra siempre la identidad
/// de ese shell — no la lee de [modoApp] en cada build, porque mientras un
/// shell está fuera de la vista (deslizado por `ModeHost`) no debe cambiar de
/// texto solo. Al pulsar, se borra letra a letra el nombre propio y se
/// escribe el del otro modo; terminada la animación se dispara [onTap], que
/// es quien de verdad cambia [modoApp] y arranca la caída/entrada de la UI.
/// "Neo" es común a los dos nombres y se queda fijo — lo que se borra y se
/// reescribe es solo el sufijo ("Fy" / "Tube").
///
/// Sin paquetes de animación de texto: mismo patrón que `like_button.dart`
/// (`AnimationController` + `AnimatedBuilder`), calculando la subcadena a
/// mostrar en cada frame.
class ModeToggleText extends StatefulWidget {
  const ModeToggleText({
    super.key,
    required this.modo,
    required this.onTap,
    this.onSufijoBorrado,
  });

  /// La identidad de **este** shell: no cambia durante la vida del widget.
  final AppMode modo;

  /// Se llama cuando termina la animación de borrado/escritura. Aquí es
  /// donde el llamador cambia [modoApp] y dispara la transición de la UI.
  final VoidCallback onTap;

  /// Se llama a mitad de la animación, justo cuando el sufijo propio ya
  /// se ha borrado del todo y antes de empezar a escribir el del otro modo.
  /// Es el hueco para soltar la RAM del modo que se está dejando (caché de
  /// imágenes) sin que se note: la atención está en esta esquina, no en el
  /// contenido, así que el parpadeo de un redecodificado ahí no se ve.
  final VoidCallback? onSufijoBorrado;

  @override
  State<ModeToggleText> createState() => _ModeToggleTextState();
}

class _ModeToggleTextState extends State<ModeToggleText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  static const _prefijo = 'Neo';

  String get _sufijoPropio => widget.modo == AppMode.neotube ? 'Tube' : 'Fy';
  String get _sufijoOtro => widget.modo == AppMode.neotube ? 'Fy' : 'Tube';

  @override
  void initState() {
    super.initState();
    // Cuando este shell vuelve a ser el activo, el texto tiene que estar ya
    // en reposo (su propio nombre) para la próxima vez que se pulse. Ocurre
    // mientras el shell está fuera de la vista, así que el salto no se nota.
    modoApp.addListener(_alCambiarModoGlobal);
  }

  void _alCambiarModoGlobal() {
    if (modoApp.value == widget.modo && _ctrl.value != 0) {
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    modoApp.removeListener(_alCambiarModoGlobal);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pulsar() async {
    if (_ctrl.isAnimating) return;
    await _ctrl.animateTo(0.5, duration: const Duration(milliseconds: 350));
    widget.onSufijoBorrado?.call();
    await _ctrl.animateTo(1, duration: const Duration(milliseconds: 350));
    widget.onTap();
  }

  String _textoEn(double t) {
    final propio = _sufijoPropio;
    final otro = _sufijoOtro;
    if (t <= 0.5) {
      final quedan = (propio.length * (1 - t / 0.5)).round();
      return _prefijo + propio.substring(0, quedan.clamp(0, propio.length));
    }
    final escritos = (otro.length * ((t - 0.5) / 0.5)).round();
    return _prefijo + otro.substring(0, escritos.clamp(0, otro.length));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: _pulsar,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => Text(
                  _textoEn(_ctrl.value),
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
