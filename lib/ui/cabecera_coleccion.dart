import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/settings.dart';
import 'art_image.dart';
import 'texto_traducido.dart';

class CabeceraColeccion extends StatelessWidget {
  const CabeceraColeccion({
    super.key,
    required this.titulo,
    required this.detalle,
    this.portada,
    this.caratula,
    this.onPlay,
    this.acciones = const [],
  });

  final String? portada;
  final Widget? caratula;
  final Widget titulo;
  final Widget detalle;
  final VoidCallback? onPlay;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacta = constraints.maxWidth < 600;
        final size = compacta ? 88.0 : 152.0;
        final fondo = colors.surfaceContainer;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: colors.surfaceContainerHigh),
                ),
                if (portada != null)
                  Positioned.fill(
                    left: constraints.maxWidth * .42,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: modoRendimiento,
                      builder: (context, rendimiento, _) => rendimiento
                          ? const SizedBox.shrink()
                          : RepaintBoundary(
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 28,
                                  sigmaY: 28,
                                ),
                                child: ArtImage(
                                  url: portada,
                                  size: 192,
                                  radius: 0,
                                ),
                              ),
                            ),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.bottomRight,
                        colors: [fondo, fondo.withValues(alpha: 0.72)],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(compacta ? 16 : 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox.square(
                        dimension: size,
                        child: caratula ?? ArtImage(url: portada, size: size),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DefaultTextStyle.merge(
                              style:
                                  (compacta
                                          ? theme.textTheme.headlineSmall
                                          : theme.textTheme.headlineLarge)
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                        letterSpacing: -0.6,
                                      ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              child: titulo,
                            ),
                            const SizedBox(height: 8),
                            DefaultTextStyle.merge(
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              child: detalle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onPlay != null || acciones.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    if (onPlay != null)
                      FilledButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const T('Reproducir'),
                      ),
                    if (onPlay != null && acciones.isNotEmpty)
                      const SizedBox(width: 8),
                    ...acciones,
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
