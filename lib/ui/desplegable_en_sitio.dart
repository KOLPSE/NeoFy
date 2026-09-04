import 'dart:async';

import 'package:flutter/material.dart';

import '../core/settings.dart' show menusEnElemento, modoRendimiento;
import '../core/temas.dart';
import 'movimiento.dart';
import 'texto_traducido.dart';

/// Una opción de un [DesplegableEnSitio].
class OpcionEnSitio {
  const OpcionEnSitio({
    required this.icono,
    required this.texto,
    required this.onTap,
    this.destructiva = false,
    this.confirmacion,
    this.textoConfirmar,
  });

  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  /// La pinta del color de error (eliminar, quitar…).
  final bool destructiva;

  /// Si no es null, [onTap] espera a que se confirme. En el modo en sitio
  /// esa pregunta sustituye logo, nombre y subtítulo; si los menús flotan,
  /// sale un diálogo.
  final String? confirmacion;
  final String? textoConfirmar;
}

/// Menú contextual al estilo Material Expressive: en vez de flotar en un
/// overlay, las opciones (y el aviso de borrar) ocupan el hueco del propio
/// elemento — logo, nombre y «N canciones». Si el usuario apaga la
/// preferencia global, vuelve al [PopupMenuButton] de siempre.
///
/// [constructor] recibe el disparador ya montado y devuelve el elemento
/// cerrado con ese disparador colocado donde toque (lo normal es el
/// `trailing` de un [ListTile]).
class DesplegableEnSitio extends StatefulWidget {
  const DesplegableEnSitio({
    super.key,
    required this.opciones,
    required this.constructor,
    this.icono = Icons.more_horiz,
    this.tooltip = 'Opciones',
    this.colorIcono,
    this.paddingOpciones = const EdgeInsets.fromLTRB(8, 4, 4, 4),
  });

  final List<OpcionEnSitio> opciones;
  final Widget Function(BuildContext context, Widget disparador) constructor;
  final IconData icono;
  final String tooltip;
  final Color? colorIcono;
  final EdgeInsetsGeometry paddingOpciones;

  @override
  State<DesplegableEnSitio> createState() => _DesplegableEnSitioState();
}

class _DesplegableEnSitioState extends State<DesplegableEnSitio> {
  var _abierto = false;
  OpcionEnSitio? _pendiente;

  void _alternar() {
    setState(() {
      _abierto = !_abierto;
      if (!_abierto) _pendiente = null;
    });
  }

  void _cerrar() {
    if (!_abierto && _pendiente == null) return;
    setState(() {
      _abierto = false;
      _pendiente = null;
    });
  }

  Future<void> _elegir(OpcionEnSitio op, {required bool enSitio}) async {
    if (op.confirmacion != null) {
      if (enSitio) {
        setState(() => _pendiente = op);
        return;
      }
      final ok = await showDialogTraducido<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: T(op.confirmacion!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const T('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: T(op.textoConfirmar ?? 'Confirmar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _cerrar();
    op.onTap();
  }

  void _confirmarPendiente() {
    final op = _pendiente;
    if (op == null) return;
    _cerrar();
    op.onTap();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.opciones.isEmpty) {
      return widget.constructor(context, const SizedBox.shrink());
    }
    return ValueListenableBuilder<bool>(
      valueListenable: menusEnElemento,
      builder: (context, enSitio, _) {
        if (!enSitio) {
          return widget.constructor(context, _disparadorFlotante());
        }
        final mueve =
            EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value;
        return TapRegion(
          onTapOutside: _abierto ? (_) => _cerrar() : null,
          child: ClipRect(
            child: AnimatedSize(
              duration: mueve ? kDuracionDesplegable : Duration.zero,
              curve: kCurvaDesplegable,
              alignment: Alignment.topCenter,
              child: _abierto
                  ? _ocupandoElHueco(context)
                  : widget.constructor(context, _disparadorEnSitio()),
            ),
          ),
        );
      },
    );
  }

  Widget _disparadorFlotante() {
    return PopupMenuButton<int>(
      icon: Icon(widget.icono, size: 18, color: widget.colorIcono),
      tooltip: widget.tooltip,
      padding: EdgeInsets.zero,
      onSelected: (i) =>
          unawaited(_elegir(widget.opciones[i], enSitio: false)),
      itemBuilder: (context) => [
        for (var i = 0; i < widget.opciones.length; i++)
          PopupMenuItem(
            value: i,
            child: T(
              widget.opciones[i].texto,
              style: widget.opciones[i].destructiva
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _disparadorEnSitio() {
    return IconButton(
      onPressed: _alternar,
      tooltip: _abierto ? 'Cerrar' : widget.tooltip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        _abierto ? Icons.close : widget.icono,
        color: _abierto
            ? Theme.of(context).colorScheme.primary
            : widget.colorIcono,
      ),
    );
  }

  /// Sustituye logo, nombre y subtítulo: el disparador se queda a la derecha
  /// para que el ancla no se mueva.
  Widget _ocupandoElHueco(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: widget.paddingOpciones,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _pendiente == null
                  ? _listaOpciones(context)
                  : _avisoDeConfirmacion(context, _pendiente!),
            ),
            _disparadorEnSitio(),
          ],
        ),
      ),
    );
  }

  Widget _listaOpciones(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final op in widget.opciones)
          InkWell(
            onTap: () => unawaited(_elegir(op, enSitio: true)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    op.icono,
                    size: 18,
                    color: op.destructiva
                        ? esquema.error
                        : esquema.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: T(
                      op.texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: op.destructiva ? esquema.error : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _avisoDeConfirmacion(BuildContext context, OpcionEnSitio op) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          T(
            op.confirmacion!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _pendiente = null),
                child: const T('Cancelar'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _confirmarPendiente,
                child: T(op.textoConfirmar ?? 'Confirmar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
