import 'dart:async';

import 'package:flutter/material.dart';

import '../core/resource_monitor.dart';
import '../core/settings.dart';
import '../core/updater.dart';
import '../core/neoreport.dart';
import 'texto_traducido.dart';

Future<void> mostrarAjustes(
  BuildContext context, {
  required ResourceMonitor monitor,
  required Settings settings,
  required Updater updater,
  required Future<void> Function() onSalirParaActualizar,
  String? trackUri,
  List<Widget> bloquesExtra = const [],
}) {
  return showDialogTraducido<void>(
    context: context,
    builder: (context) => _DialogoAjustes(
      monitor: monitor,
      settings: settings,
      updater: updater,
      onSalirParaActualizar: onSalirParaActualizar,
      trackUri: trackUri,
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
    required this.trackUri,
    required this.bloquesExtra,
  });

  final ResourceMonitor monitor;
  final Settings settings;
  final Updater updater;
  final String? trackUri;

  final Future<void> Function() onSalirParaActualizar;

  final List<Widget> bloquesExtra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: T('Ajustes'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: monitor,
                builder: (context, _) {
                  final uso = monitor.uso;
                  return Row(
                    children: [
                      Expanded(
                        child: _Medida(
                          icono: Icons.memory,
                          etiqueta: 'RAM',
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
                      onChanged: (v) =>
                          unawaited(settings.setPerformanceMode(v)),
                      title: T('Modo rendimiento'),
                      subtitle: T(
                        'Elimina las portadas por cuadrados de color',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Divider(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.discordRpcEnabled,
                      onChanged: (v) =>
                          unawaited(settings.setDiscordRpcEnabled(v)),
                      title: T('Rich Presence'),
                      subtitle: T(
                        'Muestra en tu perfil de Discord la canción que estás escuchando.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
              _EnviarReporte(neoreport: NeoReport(), trackUri: trackUri),
              const Divider(height: 12),
              _Actualizaciones(
                updater: updater,
                onSalirParaActualizar: onSalirParaActualizar,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: T('Cerrar'),
        ),
      ],
    );
  }
}

class _EnviarReporte extends StatefulWidget {
  const _EnviarReporte({required this.neoreport, required this.trackUri});
  final NeoReport neoreport;
  final String? trackUri;

  @override
  State<_EnviarReporte> createState() => _EnviarReporteState();
}

class _EnviarReporteState extends State<_EnviarReporte> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'bug';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Escribe un título y una descripción.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = await widget.neoreport.enviar(
        title: _title.text,
        body: _body.text,
        category: _category,
        trackUri: widget.trackUri,
      );
      if (mounted) {
        _title.clear();
        _body.clear();
        setState(
          () => _error =
              'Reporte enviado. Continúa en NeoReport para consultar o vincular tu cuenta de Discord.',
        );
      }
      try {
        await widget.neoreport.abrir(uri);
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                _error = 'Reporte enviado. No se pudo abrir el navegador: $uri',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(alignment: Alignment.centerLeft, child: T('Enviar un reporte')),
      const SizedBox(height: 8),
      TextField(
        controller: _title,
        maxLength: 300,
        decoration: const InputDecoration(labelText: 'Título'),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _category,
        decoration: const InputDecoration(labelText: 'Tipo'),
        items: const [
          DropdownMenuItem(value: 'bug', child: Text('Error')),
          DropdownMenuItem(value: 'crash', child: Text('Cierre inesperado')),
          DropdownMenuItem(value: 'idea', child: Text('Sugerencia')),
          DropdownMenuItem(value: 'other', child: Text('Otro')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _category = value);
        },
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _body,
        minLines: 3,
        maxLines: 5,
        maxLength: 65536,
        decoration: const InputDecoration(labelText: 'Descripción'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy ? null : _send,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send),
        label: Text(_busy ? 'Enviando…' : 'Enviar y vincular con Discord'),
      ),
    ],
  );
}

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
              T('Audio', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              T(
                _enMarcha
                    ? 'Reabriendo la salida…'
                    : 'Si deja de escucharse, vuelve a abrir la salida.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _enMarcha ? null : () => unawaited(_reiniciar()),
          child: T('Reiniciar'),
        ),
      ],
    );
  }
}

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
                  if (estado == EstadoActualizacion.fallo &&
                      updater.error != null)
                    Text(
                      updater.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    T(
                      switch (estado) {
                        EstadoActualizacion.buscando => 'Buscando…',
                        EstadoActualizacion.alDia => 'Estás al día',
                        EstadoActualizacion.disponible =>
                          Updater.seInstalaSolo
                              ? 'Hay una versión nueva: ${updater.versionDisponible}'
                              : 'Hay una versión nueva (${updater.versionDisponible}). '
                                    'Descárgala desde GitHub o actualiza tu paquete de Linux.',
                        EstadoActualizacion.descargando =>
                          'Descargando… ${(updater.progreso * 100).round()} %',
                        EstadoActualizacion.listaParaInstalar =>
                          'Instalando; NeoFy se reiniciará',
                        EstadoActualizacion.fallo => 'No se pudo comprobar',
                        EstadoActualizacion.reposo =>
                          'Comprobar si hay novedades',
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
                child: T('Actualizar'),
              )
            else if (estado != EstadoActualizacion.descargando &&
                estado != EstadoActualizacion.listaParaInstalar)
              OutlinedButton(
                onPressed: estado == EstadoActualizacion.buscando
                    ? null
                    : () => unawaited(updater.buscar()),
                child: T('Buscar'),
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
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
  late final FocusNode _foco;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.discordClientId);
    _foco = FocusNode()..addListener(_alPerderElFoco);
  }

  void _alPerderElFoco() {
    if (!_foco.hasFocus) _guardar();
  }

  void _guardar() =>
      unawaited(widget.settings.setDiscordClientId(_controller.text));

  @override
  void didUpdateWidget(covariant _CampoDiscordClientId oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.discordClientId != _controller.text) {
      _controller.text = widget.settings.discordClientId;
    }
  }

  @override
  void dispose() {
    _foco.removeListener(_alPerderElFoco);
    _foco.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CampoTextoTraducido(
      controller: _controller,
      focusNode: _foco,
      label: 'Client ID de Discord',
      hint: 'Pega aquí el Client ID de tu aplicación',
      helper:
          'Crea una app en el Discord Developer Portal con un asset llamado "logo"',
      helperMaxLines: 2,
      helperStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onSubmitted: (_) => _guardar(),
    );
  }
}
