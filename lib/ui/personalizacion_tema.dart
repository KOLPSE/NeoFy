import 'dart:async';

import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../core/tema_store.dart';
import '../core/temas.dart';
import '../core/temas_incluidos.dart';
import 'texto_traducido.dart';

/// Sección anidada bajo Temas: colores propios de Material y el
/// comportamiento de los menús.
class PersonalizacionTema extends StatelessWidget {
  const PersonalizacionTema({
    super.key,
    required this.temas,
    required this.settings,
  });

  final TemaStore temas;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([temas, settings]),
      builder: (context, _) {
        final activo = temas.porId(temas.idSeleccionado);
        final esMaterial =
            activo != null && esTemaMaterial(activo.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            T('Personalización', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            T(
              esMaterial
                  ? 'Colores de ${activo.nombre}. «Crear una plantilla» los '
                      'guarda como un tema de la comunidad.'
                  : 'Cómo se abren los menús. Los colores propios son para '
                      'los temas de Material: elige uno y pulsa «Crear una '
                      'plantilla» para guardarlos.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (esMaterial) ...[
              const SizedBox(height: 12),
              _EditorDeColores(temas: temas, idTema: activo.id),
            ],
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: menusEnElemento,
              builder: (context, activo, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: activo,
                onChanged: (v) => unawaited(settings.setMenusEnElemento(v)),
                title: T('Menús dentro del elemento'),
                subtitle: T(
                  'Los menús se despliegan ocupando el hueco del propio '
                  'elemento en vez de flotar encima.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EditorDeColores extends StatelessWidget {
  const _EditorDeColores({required this.temas, required this.idTema});

  final TemaStore temas;
  final String idTema;

  @override
  Widget build(BuildContext context) {
    final base = temaIncluidoPorId(idTema)!;
    final retoques = temas.retoquesDe(idTema);
    final oscuro = base.esOscuro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilaDeColor(
          temas: temas,
          idTema: idTema,
          clave: 'primario',
          etiqueta: 'Acento',
          porDefecto: base.colores.primario,
          actual: parsearColor(retoques['primario']) ??
              base.colores.primario,
          sugeridos: _acentos,
        ),
        const SizedBox(height: 10),
        _FilaDeColor(
          temas: temas,
          idTema: idTema,
          clave: 'fondo',
          etiqueta: 'Fondo',
          porDefecto: base.colores.fondo,
          actual:
              parsearColor(retoques['fondo']) ?? base.colores.fondo,
          sugeridos: oscuro ? _fondosOscuros : _fondosClaros,
        ),
        const SizedBox(height: 10),
        _FilaDeColor(
          temas: temas,
          idTema: idTema,
          clave: 'panel',
          etiqueta: 'Paneles',
          porDefecto: base.colores.panel,
          actual:
              parsearColor(retoques['panel']) ?? base.colores.panel,
          sugeridos: oscuro ? _panelesOscuros : _panelesClaros,
        ),
        if (retoques.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(temas.restablecerColores(idTema)),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: T('Volver a los colores de fábrica'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilaDeColor extends StatelessWidget {
  const _FilaDeColor({
    required this.temas,
    required this.idTema,
    required this.clave,
    required this.etiqueta,
    required this.porDefecto,
    required this.actual,
    required this.sugeridos,
  });

  final TemaStore temas;
  final String idTema;
  final String clave;
  final String etiqueta;
  final Color porDefecto;
  final Color actual;
  final List<Color> sugeridos;

  Future<void> _pedirColorLibre(BuildContext context) async {
    final hex = await showDialogTraducido<String>(
      context: context,
      builder: (ctx) => const _DialogoColorPropio(),
    );
    if (!context.mounted) return;
    if (hex == null) return;
    final color = parsearColor(hex);
    if (color == null) return;
    await temas.personalizar(idTema, clave, aHex(color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esDeFabrica =
        actual.toARGB32() == porDefecto.toARGB32();
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: T(etiqueta, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final color in sugeridos)
                _MuestraDeColor(
                  color: color,
                  elegido: actual.toARGB32() == color.toARGB32(),
                  onTap: () => unawaited(
                    temas.personalizar(idTema, clave, aHex(color)),
                  ),
                ),
              _MuestraDeColor(
                color: actual,
                elegido: !esDeFabrica &&
                    !sugeridos.any(
                        (c) => c.toARGB32() == actual.toARGB32()),
                icono: Icons.edit_outlined,
                tooltip: 'Color propio…',
                onTap: () => _pedirColorLibre(context),
              ),
              if (!esDeFabrica)
                _MuestraDeColor(
                  color: porDefecto,
                  elegido: false,
                  icono: Icons.undo,
                  tooltip: 'De fábrica',
                  onTap: () =>
                      unawaited(temas.personalizar(idTema, clave, null)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialogoColorPropio extends StatefulWidget {
  const _DialogoColorPropio();

  @override
  State<_DialogoColorPropio> createState() => _DialogoColorPropioState();
}

class _DialogoColorPropioState extends State<_DialogoColorPropio> {
  late final TextEditingController _controlador = TextEditingController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _aplicar() => Navigator.of(context).pop(_controlador.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: T('Color propio'),
      content: TextField(
        controller: _controlador,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '#1DB954',
          prefixText: 'Hex ',
        ),
        onSubmitted: (_) => _aplicar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: T('Cancelar'),
        ),
        FilledButton(
          onPressed: _aplicar,
          child: T('Aplicar'),
        ),
      ],
    );
  }
}

class _MuestraDeColor extends StatelessWidget {
  const _MuestraDeColor({
    required this.color,
    required this.elegido,
    required this.onTap,
    this.icono,
    this.tooltip,
  });

  final Color color;
  final bool elegido;
  final VoidCallback onTap;
  final IconData? icono;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muestra = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: elegido
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: elegido ? 2 : 1,
          ),
        ),
        child: icono == null
            ? (elegido
                ? Icon(Icons.check,
                    size: 14, color: contrasteSobre(color))
                : null)
            : Icon(icono,
                size: 14, color: contrasteSobre(color)),
      ),
    );
    if (tooltip == null) return muestra;
    return Tooltip(message: tooltip!, child: muestra);
  }
}

String aHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

const _acentos = [
  Color(0xFF1DB954),
  Color(0xFF65558F),
  Color(0xFF0A84FF),
  Color(0xFF00897B),
  Color(0xFFE91E63),
  Color(0xFFFF6D00),
  Color(0xFFE53935),
  Color(0xFF8E24AA),
];

const _fondosOscuros = [
  Color(0xFF141218),
  Color(0xFF000000),
  Color(0xFF121212),
  Color(0xFF0F1A2B),
  Color(0xFF1A1023),
  Color(0xFF101A12),
];

const _fondosClaros = [
  Color(0xFFFDF7FF),
  Color(0xFFFFFFFF),
  Color(0xFFF5F5F5),
  Color(0xFFFFF5F0),
  Color(0xFFF0F4FF),
  Color(0xFFF0FFF4),
];

const _panelesOscuros = [
  Color(0xFF211F24),
  Color(0xFF0A0A0A),
  Color(0xFF1C1C1C),
  Color(0xFF182639),
  Color(0xFF27193A),
  Color(0xFF1A2A1E),
];

const _panelesClaros = [
  Color(0xFFF2ECF4),
  Color(0xFFF0F0F0),
  Color(0xFFE8E8E8),
  Color(0xFFFFE8DE),
  Color(0xFFE0EAFF),
  Color(0xFFE0F5E8),
];
