import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/tema_store.dart';
import '../core/temas.dart';
import '../core/temas_incluidos.dart';

class BotonDeTemas extends StatelessWidget {
  const BotonDeTemas({super.key, required this.temas});

  final TemaStore temas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: temas,
      builder: (context, _) {
        final activo = temas.porId(temas.idSeleccionado);
        final nombre = activo?.nombre ?? 'Automático (sigue al sistema)';
        final cuantos = temas.temasDeDisco.length;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Tema', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    cuantos == 0
                        ? nombre
                        : '$nombre · $cuantos de la comunidad instalado'
                            '${cuantos == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => unawaited(mostrarSelectorDeTemas(context, temas)),
              child: const Text('Cambiar'),
            ),
          ],
        );
      },
    );
  }
}

Future<void> mostrarSelectorDeTemas(BuildContext context, TemaStore temas) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogoDeTemas(temas: temas),
  );
}

class _DialogoDeTemas extends StatelessWidget {
  const _DialogoDeTemas({required this.temas});

  final TemaStore temas;

  Future<void> _abrirLaCarpeta() async {
    final carpeta = carpetaDeTemas();
    try {
      await launchUrl(Uri.file(carpeta.path));
    } catch (_) {}
  }

  Future<void> _crearEjemplo(BuildContext context) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      final creada = await crearTemaDeEjemplo();
      await temas.recargar();
      mensajero?.showSnackBar(
        SnackBar(
          content: Text('Plantilla creada en ${creada.path}'),
          action: SnackBarAction(label: 'Abrir', onPressed: _abrirLaCarpeta),
        ),
      );
    } catch (e) {
      mensajero?.showSnackBar(
        SnackBar(content: Text('No se pudo crear la plantilla: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Temas'),
      content: SizedBox(
        width: 460,
        child: AnimatedBuilder(
          animation: temas,
          builder: (context, _) {
            final deDisco = temas.temasDeDisco;
            final fallos = temas.fallos;
            final avisos = temas.avisos;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FilaDeTema(
                    nombre: 'Automático',
                    detalle: 'Claro u oscuro según Windows o tu escritorio',
                    muestra: null,
                    elegido: temas.siguiendoAlSistema,
                    onTap: () =>
                        unawaited(temas.seleccionar(kIdTemaDelSistema)),
                  ),
                  const Divider(height: 20),
                  Text('INCLUIDOS', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 6),
                  for (final tema in temasIncluidos)
                    _FilaDeTema(
                      nombre: tema.nombre,
                      detalle: tema.descripcion,
                      muestra: tema,
                      elegido: temas.idSeleccionado == tema.id,
                      onTap: () => unawaited(temas.seleccionar(tema.id)),
                    ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text('DE LA COMUNIDAD',
                            style: theme.textTheme.labelSmall),
                      ),
                      IconButton(
                        tooltip: 'Volver a leer la carpeta',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => unawaited(temas.recargar()),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (deDisco.isEmpty && fallos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Todavía no hay ninguno. Cada tema es una carpeta con '
                        'un $kNombreDelManifiesto dentro; se recargan solos al '
                        'guardar, sin cerrar NeoFy.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  for (final tema in deDisco)
                    _FilaDeTema(
                      nombre: tema.nombre,
                      detalle: [
                        if (tema.autor.isNotEmpty) 'de ${tema.autor}',
                        if (tema.version.isNotEmpty) 'v${tema.version}',
                        if (tema.descripcion.isNotEmpty) tema.descripcion,
                      ].join(' · '),
                      muestra: tema,
                      elegido: temas.idSeleccionado == tema.id,
                      aviso: avisos[tema.id]?.join('\n'),
                      onTap: () => unawaited(temas.seleccionar(tema.id)),
                    ),
                  for (final entrada in fallos.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${entrada.key}: ${entrada.value}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_abrirLaCarpeta()),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Abrir la carpeta'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_crearEjemplo(context)),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Crear una plantilla'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
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

class _FilaDeTema extends StatelessWidget {
  const _FilaDeTema({
    required this.nombre,
    required this.detalle,
    required this.muestra,
    required this.elegido,
    required this.onTap,
    this.aviso,
  });

  final String nombre;
  final String detalle;
  final Tema? muestra;
  final bool elegido;
  final VoidCallback onTap;
  final String? aviso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            _Muestra(tema: muestra),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nombre, style: theme.textTheme.bodyMedium),
                  if (detalle.isNotEmpty)
                    Text(
                      detalle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  if (aviso != null)
                    Text(
                      aviso!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.tertiary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              elegido ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: elegido
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Muestra extends StatelessWidget {
  const _Muestra({required this.tema});

  final Tema? tema;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = tema;
    if (t == null) {
      return Container(
        width: 44,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          gradient: const LinearGradient(
            colors: [Colors.white, Colors.black],
            stops: [0.5, 0.5],
          ),
        ),
      );
    }
    return Container(
      width: 44,
      height: 30,
      decoration: BoxDecoration(
        color: t.colores.fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            decoration: BoxDecoration(
              color: t.colores.panel,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(5),
                bottomLeft: Radius.circular(5),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: t.colores.primario,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
