import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/settings.dart';
import '../core/tema_store.dart';
import '../core/temas_incluidos.dart';
import 'texto_traducido.dart';

class BotonDeTemas extends StatelessWidget {
  const BotonDeTemas({super.key, required this.temas, required this.settings});

  final TemaStore temas;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: temas,
      builder: (context, _) {
        final seleccionado = temas.siguiendoAlSistema
            ? kIdTemaDelSistema
            : temas.idSeleccionado;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            T('Tema', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            T(
              'Elige entre NeoFy Claro, NeoFy Nocturno o seguir la apariencia del sistema.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<String>(
                  value: kIdTemaDelSistema,
                  icon: Icon(Icons.brightness_auto_outlined, size: 18),
                  label: T('Automático'),
                ),
                ButtonSegment<String>(
                  value: kIdTemaClaro,
                  icon: Icon(Icons.light_mode_outlined, size: 18),
                  label: T('Claro'),
                ),
                ButtonSegment<String>(
                  value: kIdTemaNocturno,
                  icon: Icon(Icons.dark_mode_outlined, size: 18),
                  label: T('Oscuro'),
                ),
              ],
              selected: {seleccionado},
              onSelectionChanged: (sel) =>
                  unawaited(temas.seleccionar(sel.first)),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<bool>(
              valueListenable: menusEnElemento,
              builder: (context, activo, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: activo,
                onChanged: (v) => unawaited(settings.setMenusEnElemento(v)),
                title: const T('Menús dentro del elemento'),
                subtitle: T(
                  'Los menús se despliegan ocupando el hueco del propio '
                  'elemento en vez de flotar encima.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
