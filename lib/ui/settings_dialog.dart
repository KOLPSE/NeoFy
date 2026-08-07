import 'dart:async';

import 'package:flutter/material.dart';

import '../core/resource_monitor.dart';
import '../core/settings.dart';
import '../core/updater.dart';

/// Ajustes: lo que gasta la app y el modo rendimiento. Nada más.
///
/// El consumo se enseña aquí y no en una barra permanente porque es un dato de
/// diagnóstico, no algo que haga falta mirar mientras escuchas música.
Future<void> mostrarAjustes(
  BuildContext context, {
  required ResourceMonitor monitor,
  required Settings settings,
  required Updater updater,
  required Future<void> Function() onSalirParaActualizar,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogoAjustes(
      monitor: monitor,
      settings: settings,
      updater: updater,
      onSalirParaActualizar: onSalirParaActualizar,
    ),
  );
}

class _DialogoAjustes extends StatelessWidget {
  const _DialogoAjustes({
    required this.monitor,
    required this.settings,
    required this.updater,
    required this.onSalirParaActualizar,
  });

  final ResourceMonitor monitor;
  final Settings settings;
  final Updater updater;

  /// Cerrar la app en cuanto arranque el instalador: no puede sobrescribir un
  /// ejecutable en uso.
  final Future<void> Function() onSalirParaActualizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Ajustes'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Se repinta con cada muestra del monitor (cada 3 s); es lo único
            // vivo del diálogo.
            AnimatedBuilder(
              animation: monitor,
              builder: (context, _) {
                final uso = monitor.uso;
                return Row(
                  children: [
                    Expanded(
                      child: _Medida(
                        icono: Icons.memory,
                        etiqueta: 'Memoria',
                        valor: UsoDeRecursos.mb(uso.total),
                      ),
                    ),
                    Expanded(
                      child: _Medida(
                        icono: Icons.speed,
                        etiqueta: 'CPU',
                        valor: '${uso.cpu.toStringAsFixed(1)} %',
                      ),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 28),
            AnimatedBuilder(
              animation: settings,
              builder: (context, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.performanceMode,
                onChanged: (v) => unawaited(settings.setPerformanceMode(v)),
                title: const Text('Modo rendimiento'),
                subtitle: Text(
                  'Sustituye las carátulas por mosaicos de color y apaga el '
                  'lector de metadatos. El audio no se toca.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const Divider(height: 12),
            _Actualizaciones(
              updater: updater,
              onSalirParaActualizar: onSalirParaActualizar,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Versión instalada y actualización en un clic.
class _Actualizaciones extends StatelessWidget {
  const _Actualizaciones({
    required this.updater,
    required this.onSalirParaActualizar,
  });

  final Updater updater;
  final Future<void> Function() onSalirParaActualizar;

  Future<void> _actualizar(BuildContext context) async {
    await updater.descargar();
    if (updater.estado != EstadoActualizacion.listaParaInstalar) return;
    if (await updater.instalar()) {
      // El instalador ya está corriendo; la app tiene que quitarse de en medio.
      await onSalirParaActualizar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: updater,
      builder: (context, _) {
        final estado = updater.estado;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('NeoFy ${updater.versionActual}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    switch (estado) {
                      EstadoActualizacion.buscando => 'Buscando…',
                      EstadoActualizacion.alDia => 'Estás al día',
                      EstadoActualizacion.disponible =>
                        'Hay una versión nueva: ${updater.versionDisponible}',
                      EstadoActualizacion.descargando =>
                        'Descargando… ${(updater.progreso * 100).round()} %',
                      EstadoActualizacion.listaParaInstalar =>
                        'Instalando; NeoFy se reiniciará',
                      EstadoActualizacion.fallo =>
                        updater.error ?? 'No se pudo comprobar',
                      EstadoActualizacion.reposo => 'Comprobar si hay novedades',
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: estado == EstadoActualizacion.disponible
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (estado == EstadoActualizacion.descargando) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      minHeight: 3,
                      value: updater.progreso > 0 ? updater.progreso : null,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (estado == EstadoActualizacion.disponible)
              FilledButton(
                onPressed: () => _actualizar(context),
                child: const Text('Actualizar'),
              )
            else if (estado != EstadoActualizacion.descargando &&
                estado != EstadoActualizacion.listaParaInstalar)
              OutlinedButton(
                onPressed: estado == EstadoActualizacion.buscando
                    ? null
                    : () => unawaited(updater.buscar()),
                child: const Text('Buscar'),
              ),
          ],
        );
      },
    );
  }
}

class _Medida extends StatelessWidget {
  const _Medida({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icono, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 6),
        Text(valor, style: theme.textTheme.titleLarge),
        Text(
          etiqueta,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
