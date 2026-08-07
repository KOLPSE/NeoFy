import 'dart:async';

import 'package:flutter/material.dart';

import '../core/resource_monitor.dart';
import '../core/settings.dart';

/// Ajustes: lo que gasta la app y el modo rendimiento. Nada más.
///
/// El consumo se enseña aquí y no en una barra permanente porque es un dato de
/// diagnóstico, no algo que haga falta mirar mientras escuchas música.
Future<void> mostrarAjustes(
  BuildContext context, {
  required ResourceMonitor monitor,
  required Settings settings,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogoAjustes(monitor: monitor, settings: settings),
  );
}

class _DialogoAjustes extends StatelessWidget {
  const _DialogoAjustes({required this.monitor, required this.settings});

  final ResourceMonitor monitor;
  final Settings settings;

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
