import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/art_cache.dart';
import '../core/settings.dart';
import '../core/tema_store.dart';
import '../core/temas.dart';

class FondoDelTema extends StatelessWidget {
  const FondoDelTema({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final estilo = EstiloNeoFy.de(context);
    final fondo = estilo.fondo;
    final esquema = Theme.of(context).colorScheme;

    if (!fondo.hayAlgoQuePintar) return child;

    return ValueListenableBuilder<bool>(
      valueListenable: modoRendimiento,
      builder: (context, rendimiento, _) {
        if (rendimiento) {
          return ColoredBox(color: esquema.surface, child: child);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: esquema.surface),
            if (fondo.degradado.length >= 2)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _alineacion(fondo.anguloDegradado + 180),
                    end: _alineacion(fondo.anguloDegradado),
                    colors: fondo.degradado,
                  ),
                ),
              ),
            if (fondo.imagen != null)
              _ImagenDeFondo(
                ruta: estilo.rutaDeRecurso(fondo.imagen!),
                fondo: fondo,
              ),
            if (fondo.usarCaratula) _CaratulaDeFondo(fondo: fondo),
            if (fondo.oscurecer > 0)
              ColoredBox(
                color: (esquema.brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white)
                    .withValues(alpha: fondo.oscurecer),
              ),
            child,
          ],
        );
      },
    );
  }
}

class _ImagenDeFondo extends StatelessWidget {
  const _ImagenDeFondo({required this.ruta, required this.fondo});

  final String? ruta;
  final FondoDeTema fondo;

  @override
  Widget build(BuildContext context) {
    final destino = ruta;
    if (destino == null) return const SizedBox.shrink();
    final fichero = File(destino);
    if (!fichero.existsSync()) return const SizedBox.shrink();
    return _conDesenfoque(
      fondo,
      Opacity(
        opacity: fondo.opacidad,
        child: Image.file(
          fichero,
          fit: _ajuste(fondo.ajuste),
          repeat: fondo.ajuste == AjusteDeFondo.repetir
              ? ImageRepeat.repeat
              : ImageRepeat.noRepeat,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _CaratulaDeFondo extends StatelessWidget {
  const _CaratulaDeFondo({required this.fondo});

  final FondoDeTema fondo;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: caratulaDeFondo,
      builder: (context, url, _) {
        if (url == null) return const SizedBox.shrink();
        return FutureBuilder<File?>(
          future: ArtCache.file(url),
          builder: (context, snap) {
            final fichero = snap.data;
            if (fichero == null) return const SizedBox.shrink();
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: _conDesenfoque(
                fondo,
                Opacity(
                  key: ValueKey(fichero.path),
                  opacity: fondo.opacidad,
                  child: Image.file(
                    fichero,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Widget _conDesenfoque(FondoDeTema fondo, Widget hijo) {
  if (fondo.desenfoque <= 0) return hijo;
  return ImageFiltered(
    imageFilter: ui.ImageFilter.blur(
      sigmaX: fondo.desenfoque,
      sigmaY: fondo.desenfoque,
      tileMode: TileMode.decal,
    ),
    child: hijo,
  );
}

BoxFit _ajuste(AjusteDeFondo ajuste) => switch (ajuste) {
      AjusteDeFondo.cubrir => BoxFit.cover,
      AjusteDeFondo.contener => BoxFit.contain,
      AjusteDeFondo.estirar => BoxFit.fill,
      AjusteDeFondo.centrar => BoxFit.none,
      AjusteDeFondo.repetir => BoxFit.none,
    };

Alignment _alineacion(double grados) {
  final radianes = grados * math.pi / 180;
  return Alignment(math.cos(radianes), math.sin(radianes));
}

const double _altoDelReflejo = 72;

class PanelDeCristal extends StatelessWidget {
  const PanelDeCristal({
    super.key,
    required this.child,
    this.forma,
    this.margen = EdgeInsets.zero,
    this.conSombra = true,
  });

  final Widget child;
  final BorderRadius? forma;
  final EdgeInsets margen;
  final bool conSombra;

  @override
  Widget build(BuildContext context) {
    final estilo = EstiloNeoFy.de(context);
    final esquema = Theme.of(context).colorScheme;
    final cristal = estilo.cristal;
    final radio = forma ?? BorderRadius.circular(cristal.radio);

    if (!cristal.activo) {
      return Padding(
        padding: margen,
        child: Material(
          color: esquema.surfaceContainer,
          borderRadius: forma,
          child: child,
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: modoRendimiento,
      builder: (context, rendimiento, _) {
        if (rendimiento) {
          return Padding(
            padding: margen,
            child: Material(
              color: esquema.surfaceContainer,
              borderRadius: forma,
              child: child,
            ),
          );
        }
        return Padding(
          padding: margen,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radio,
              boxShadow: conSombra
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 16,
                        spreadRadius: -10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: radio,
              child: BackdropFilter(
                filter: _filtroDeCristal(cristal),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: esquema.surfaceContainer
                              .withValues(alpha: cristal.opacidad),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: _altoDelReflejo,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: cristal.brillo),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Material(color: Colors.transparent, child: child),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _RimDeCristal(
                            radio: radio,
                            intensidad: cristal.borde,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

ui.ImageFilter _filtroDeCristal(Cristal cristal) {
  final desenfoque = ui.ImageFilter.blur(
    sigmaX: cristal.desenfoque,
    sigmaY: cristal.desenfoque,
    tileMode: TileMode.mirror,
  );
  if (cristal.saturacion == 1) return desenfoque;
  return ui.ImageFilter.compose(
    outer: _saturacion(cristal.saturacion),
    inner: desenfoque,
  );
}

ColorFilter _saturacion(double s) {
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  final ir = (1 - s) * lr;
  final ig = (1 - s) * lg;
  final ib = (1 - s) * lb;
  return ColorFilter.matrix(<double>[
    ir + s, ig, ib, 0, 0,
    ir, ig + s, ib, 0, 0,
    ir, ig, ib + s, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

class _RimDeCristal extends CustomPainter {
  const _RimDeCristal({required this.radio, required this.intensidad});

  final BorderRadius radio;
  final double intensidad;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensidad <= 0) return;
    final rect = Offset.zero & size;
    final rrect = radio.toRRect(rect).deflate(0.6);
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          Colors.white.withValues(alpha: intensidad),
          Colors.white.withValues(alpha: intensidad * 0.22),
          Colors.white.withValues(alpha: intensidad * 0.55),
        ],
        const [0, 0.5, 1],
      );
    canvas.drawRRect(rrect, pincel);
  }

  @override
  bool shouldRepaint(_RimDeCristal viejo) =>
      viejo.intensidad != intensidad || viejo.radio != radio;
}
