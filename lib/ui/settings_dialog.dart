import 'dart:async';

import 'package:flutter/material.dart';

import '../core/resource_monitor.dart';
import '../core/settings.dart';
import '../core/updater.dart';

/// Ajustes: lo que gasta la app, el modo rendimiento y las actualizaciones.
///
/// El consumo se enseña aquí y no en una barra permanente porque es un dato de
/// diagnóstico, no algo que haga falta mirar mientras escuchas música.
///
/// Casi todo lo que hay dentro es de la app entera: la memoria y la CPU las
/// gasta un único proceso, el modo rendimiento toca la caché de imágenes y la
/// actualización trae un solo binario. Lo que depende de cómo esté sonando la
/// música entra por [bloquesExtra]: reiniciar la salida de librespot siempre,
/// y el estado de yt-dlp solo cuando la cuenta va por la vía libre.
Future<void> mostrarAjustes(
  BuildContext context, {
  required ResourceMonitor monitor,
  required Settings settings,
  required Updater updater,
  required Future<void> Function() onSalirParaActualizar,
  List<Widget> bloquesExtra = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogoAjustes(
      monitor: monitor,
      settings: settings,
      updater: updater,
      onSalirParaActualizar: onSalirParaActualizar,
      bloquesExtra: bloquesExtra,
    ),
  );
}

class _DialogoAjustes extends StatelessWidget {
  const _DialogoAjustes({
    required this.monitor,
    required this.settings,
    required this.updater,
    required this.onSalirParaActualizar,
    required this.bloquesExtra,
  });

  final ResourceMonitor monitor;
  final Settings settings;
  final Updater updater;

  /// Cerrar la app en cuanto arranque el instalador: no puede sobrescribir un
  /// ejecutable en uso.
  final Future<void> Function() onSalirParaActualizar;

  /// Bloques que el llamador añade según cómo esté reproduciendo la app.
  final List<Widget> bloquesExtra;

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
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
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
                  const Divider(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.discordRpcEnabled,
                    onChanged: (v) => unawaited(settings.setDiscordRpcEnabled(v)),
                    title: const Text('Mostrar en Discord (Rich Presence)'),
                    subtitle: Text(
                      'Enseña en tu perfil de Discord la canción que suena, la '
                      'siguiente de la cola y un botón a GitHub.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (settings.discordRpcEnabled) ...[
                    const SizedBox(height: 8),
                    _CampoDiscordClientId(settings: settings),
                  ],
                ],
              ),
            ),
            for (final bloque in bloquesExtra) ...[
              const Divider(height: 12),
              bloque,
            ],
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

/// Salida de emergencia para cuando la música se queda muda. Reinicia
/// librespot, así que **no sirve en la vía libre**, que reproduce en este mismo
/// proceso. Se pasa por `mostrarAjustes(bloquesExtra:)`.
///
/// La app ya reinicia el audio sola al cambiar la salida del sistema o al ver
/// un error del backend en el log, pero no todo se detecta: un driver que se
/// atasca o una aplicación que se queda el dispositivo en modo exclusivo no
/// avisan a nadie. Esto es lo mismo que hacía el usuario cerrando y abriendo la
/// app, pero sin perder la sesión ni la canción.
class ReiniciarAudioDeNeoFy extends StatefulWidget {
  const ReiniciarAudioDeNeoFy({super.key, required this.onReiniciar});

  final Future<void> Function() onReiniciar;

  @override
  State<ReiniciarAudioDeNeoFy> createState() => _ReiniciarAudioState();
}

class _ReiniciarAudioState extends State<ReiniciarAudioDeNeoFy> {
  bool _enMarcha = false;

  Future<void> _reiniciar() async {
    setState(() => _enMarcha = true);
    try {
      await widget.onReiniciar();
    } finally {
      if (mounted) setState(() => _enMarcha = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Audio', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                _enMarcha
                    ? 'Reabriendo la salida…'
                    : 'Si deja de oírse, vuelve a abrir la salida sin cerrar '
                        'NeoFy. Sigue por donde iba.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _enMarcha ? null : () => unawaited(_reiniciar()),
          child: const Text('Reiniciar'),
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
                  Text(
                    'NeoFy ${updater.versionActual}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    switch (estado) {
                      EstadoActualizacion.buscando => 'Buscando…',
                      EstadoActualizacion.alDia => 'Estás al día',
                      // Donde no se instala sola (Linux), el aviso tiene que
                      // decir qué hacer: si no, informa de una novedad y deja
                      // al usuario sin ninguna forma de cogerla.
                      EstadoActualizacion.disponible => Updater.seInstalaSolo
                          ? 'Hay una versión nueva: ${updater.versionDisponible}'
                          : 'Hay una versión nueva (${updater.versionDisponible}). '
                              'Actualiza con ${Updater.comandoDeActualizacion}',
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
            if (estado == EstadoActualizacion.disponible &&
                Updater.seInstalaSolo)
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

class _CampoDiscordClientId extends StatefulWidget {
  const _CampoDiscordClientId({required this.settings});

  final Settings settings;

  @override
  State<_CampoDiscordClientId> createState() => _CampoDiscordClientIdState();
}

class _CampoDiscordClientIdState extends State<_CampoDiscordClientId> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.discordClientId);
  }

  @override
  void didUpdateWidget(covariant _CampoDiscordClientId oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.discordClientId != _controller.text) {
      _controller.text = widget.settings.discordClientId;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Client ID de Discord',
        hintText: 'Pega aquí el Client ID de tu aplicación',
        helperText:
            'Crea una app en el Discord Developer Portal con un asset llamado "logo"',
        helperMaxLines: 2,
        helperStyle: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (valor) =>
          unawaited(widget.settings.setDiscordClientId(valor)),
    );
  }
}

