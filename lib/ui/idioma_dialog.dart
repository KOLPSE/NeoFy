import 'dart:async';

import 'package:flutter/material.dart';

import '../core/idiomas_spotify.dart';
import '../core/settings.dart';
import 'texto_traducido.dart';

class BotonDeIdioma extends StatelessWidget {
  const BotonDeIdioma({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  T('Idioma', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    nombreIdiomaPreferido(settings.idiomaPreferido),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => unawaited(mostrarSelectorDeIdioma(context, settings)),
              child: T('Cambiar'),
            ),
          ],
        );
      },
    );
  }
}

Future<void> mostrarSelectorDeIdioma(BuildContext context, Settings settings) {
  return showDialogTraducido<void>(
    context: context,
    builder: (context) => _DialogoDeIdioma(settings: settings),
  );
}

class _DialogoDeIdioma extends StatefulWidget {
  const _DialogoDeIdioma({required this.settings});

  final Settings settings;

  @override
  State<_DialogoDeIdioma> createState() => _DialogoDeIdiomaState();
}

class _DialogoDeIdiomaState extends State<_DialogoDeIdioma> {
  final _busqueda = TextEditingController();
  final _focoBusqueda = FocusNode();
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() => _filtro = _busqueda.text));
  }

  @override
  void dispose() {
    _focoBusqueda.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _elegir(String codigo) async {
    await widget.settings.setIdiomaPreferido(codigo);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferido = widget.settings.idiomaPreferido;
    final lista = idiomasFiltrados(_filtro);

    return AlertDialog(
      title: T('Idioma de Spotify'),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CampoTextoTraducido(
              controller: _busqueda,
              focusNode: _focoBusqueda,
              label: '',
              hint: 'Buscar idioma o código (es_ES, en_US…)',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: const OutlineInputBorder(),
            ),
            const SizedBox(height: 8),
            T(
              'Formato de la API de Spotify: idioma_PAÍS. Si no hay traducción, '
              'Spotify responde en inglés americano.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _FilaDeIdioma(
                    nombre: nombreIdiomaPreferido(kIdiomaSistema),
                    codigo: 'Automático',
                    elegido: preferido.isEmpty,
                    onTap: () => _elegir(kIdiomaSistema),
                  ),
                  const Divider(height: 16),
                  if (lista.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: T(
                        'Ningún idioma coincide con «$_filtro».',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final idioma in lista)
                    _FilaDeIdioma(
                      nombre: idioma.nombre,
                      codigo: idioma.codigo,
                      elegido: preferido == idioma.codigo,
                      onTap: () => _elegir(idioma.codigo),
                    ),
                ],
              ),
            ),
          ],
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

class _FilaDeIdioma extends StatelessWidget {
  const _FilaDeIdioma({
    required this.nombre,
    required this.codigo,
    required this.elegido,
    required this.onTap,
  });

  final String nombre;
  final String codigo;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(
              elegido ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: elegido
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre, style: theme.textTheme.bodyMedium),
                  if (codigo == 'Automático')
                    T(
                      codigo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      codigo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
