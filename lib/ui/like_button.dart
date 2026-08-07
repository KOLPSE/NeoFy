import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/spotify_api.dart';

/// El rojo del corazón. No sale del `ColorScheme` a propósito: el tema de la
/// app es verde Spotify y este color tiene que ser el mismo en claro y oscuro.
const Color kColorFavorito = Color(0xFFE53935);

/// Corazón de "me gusta" que se llena como si le entrara líquido.
///
/// La animación se paga sola en atención pero no en CPU: la ondulación solo
/// corre **mientras** se está llenando o vaciando (unos 600 ms) y se para al
/// terminar. Con un temporizador por fila corriendo siempre, una playlist de
/// 3.000 canciones tendría decenas de animaciones vivas a la vez sin que nadie
/// las mire.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.likes,
    required this.uri,
    this.size = 20,
  });

  final LikedStore likes;
  final String uri;
  final double size;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with TickerProviderStateMixin {
  late final AnimationController _nivel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 420),
  );

  late final AnimationController _onda = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final CurvedAnimation _llenado = CurvedAnimation(
    parent: _nivel,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Hacia dónde va el corazón ahora mismo. Se compara con lo que dice el
  /// store para no repetir una animación que ya está en marcha.
  bool _lleno = false;

  @override
  void initState() {
    super.initState();
    // La ondulación no tiene por qué seguir corriendo cuando el vaso ya está
    // lleno (o vacío): ahí la superficie está quieta.
    _nivel.addStatusListener(_alTerminarElLlenado);
    widget.likes.addListener(_sincronizar);
    _adoptarEstadoDelStore();
    widget.likes.ensureKnown(widget.uri);
  }

  @override
  void didUpdateWidget(covariant LikeButton old) {
    super.didUpdateWidget(old);
    if (old.uri == widget.uri) return;
    // Las listas reciclan las filas: esta casilla ha pasado a ser otra canción,
    // y su corazón no tiene nada que ver con el de la anterior.
    _adoptarEstadoDelStore();
    widget.likes.ensureKnown(widget.uri);
  }

  @override
  void dispose() {
    widget.likes.removeListener(_sincronizar);
    // La curva se suscribe al controlador: sin soltarla queda un oyente vivo
    // por cada fila que haya pasado por pantalla.
    _llenado.dispose();
    _nivel.dispose();
    _onda.dispose();
    super.dispose();
  }

  void _alTerminarElLlenado(AnimationStatus s) {
    if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
      _onda.stop();
    }
  }

  /// Se planta en el estado que diga el store, sin animar.
  void _adoptarEstadoDelStore() {
    _lleno = widget.likes.isSaved(widget.uri) ?? false;
    _onda.stop();
    _nivel.value = _lleno ? 1 : 0;
  }

  /// Reacciona a los cambios que **no** vienen de este botón: la respuesta de
  /// la consulta en lote, la misma canción marcada desde otra pantalla, o la
  /// marcha atrás cuando la petición falla. Sin animación: no es el usuario
  /// llenando el corazón, es un dato que llega.
  void _sincronizar() {
    if (!mounted) return;
    final guardada = widget.likes.isSaved(widget.uri) ?? false;
    if (guardada == _lleno) return;
    setState(_adoptarEstadoDelStore);
  }

  void _animarHacia(bool lleno) {
    _lleno = lleno;
    _onda.repeat();
    if (lleno) {
      _nivel.forward();
    } else {
      _nivel.reverse();
    }
  }

  Future<void> _pulsar() async {
    if (!widget.likes.canModify) {
      _avisarFaltaPermiso();
      return;
    }
    final guardada = widget.likes.isSaved(widget.uri) ?? false;
    _animarHacia(!guardada);
    try {
      await widget.likes.toggle(widget.uri);
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is ApiException && e.isForbidden
          ? 'Spotify no dejó cambiar tus favoritos: ${e.message}'
          : 'No se pudo cambiar: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
    }
  }

  /// El caso de la sesión antigua: el permiso se pide desde que existe este
  /// botón, pero un token viejo no lo gana al renovarse. Sin este aviso, el
  /// síntoma sería un corazón que se llena y se vacía solo.
  void _avisarFaltaPermiso() {
    final reauth = widget.likes.onReauth;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text(
        'Tu sesión se inició sin permiso para editar favoritos. Hay que volver '
        'a pasar por Spotify una vez; no perderás nada.',
      ),
      action: reauth == null
          ? null
          : SnackBarAction(
              label: 'Iniciar sesión',
              onPressed: () => unawaited(reauth()),
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: _lleno ? 'Quitar de tus me gusta' : 'Guardar en tus me gusta',
      waitDuration: const Duration(milliseconds: 600),
      child: InkResponse(
        onTap: _pulsar,
        radius: 18,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            // La animación no debe arrastrar al repintado de la fila entera.
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_llenado, _onda]),
                builder: (context, _) {
                  final n = _llenado.value.clamp(0.0, 1.0);
                  return Transform.scale(
                    // Un golpe de escala a mitad de camino, que es lo que hace
                    // que el gesto se sienta como un "toma".
                    scale: 1 + 0.22 * math.sin(math.pi * n),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: widget.size,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        if (n > 0)
                          ClipPath(
                            clipper: _RecorteLiquido(nivel: n, fase: _onda.value),
                            child: Icon(
                              Icons.favorite,
                              size: widget.size,
                              color: kColorFavorito,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recorta por debajo de una superficie ondulada: lo que queda del corazón
/// relleno es justo el líquido que ha entrado.
class _RecorteLiquido extends CustomClipper<Path> {
  const _RecorteLiquido({required this.nivel, required this.fase});

  /// 0 vacío, 1 lleno.
  final double nivel;

  /// Desplazamiento de la onda, 0..1. Es lo que la hace correr.
  final double fase;

  /// Cuántas ondas caben a lo ancho del corazón. Dos se leen como líquido;
  /// más, como un zigzag.
  static const _ondas = 2;

  @override
  Path getClip(Size size) {
    if (nivel >= 1) return Path()..addRect(Offset.zero & size);

    // La cresta se aplana según se llena: al final el líquido está en reposo y
    // una onda a tope justo antes de completarse delataría el truco.
    final amplitud = size.height * 0.10 * (1 - nivel);
    final y = size.height * (1 - nivel);

    final path = Path()..moveTo(0, y);
    // Un punto por píxel: son 20, y así la curva sale limpia sin tener que
    // calcular puntos de control de Béziers.
    for (var x = 0.0; x <= size.width; x += 1) {
      final t = x / size.width;
      path.lineTo(x, y + amplitud * math.sin((t * _ondas + fase) * 2 * math.pi));
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_RecorteLiquido old) =>
      old.nivel != nivel || old.fase != fase;
}
