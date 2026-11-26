import 'dart:async';

import 'package:flutter/material.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/models.dart';
import '../core/spotify_api.dart';
import 'texto_traducido.dart';

class ArtistFavoriteButton extends StatefulWidget {
  const ArtistFavoriteButton({
    super.key,
    required this.favoritos,
    required this.artista,
    this.compacto = false,
  });

  final ArtistasFavoritosStore favoritos;
  final Artist artista;
  final bool compacto;

  @override
  State<ArtistFavoriteButton> createState() => _ArtistFavoriteButtonState();
}

class _ArtistFavoriteButtonState extends State<ArtistFavoriteButton> {
  @override
  void initState() {
    super.initState();
    widget.favoritos.addListener(_sincronizar);
  }

  @override
  void didUpdateWidget(covariant ArtistFavoriteButton old) {
    super.didUpdateWidget(old);
    if (old.favoritos == widget.favoritos) return;
    old.favoritos.removeListener(_sincronizar);
    widget.favoritos.addListener(_sincronizar);
  }

  @override
  void dispose() {
    widget.favoritos.removeListener(_sincronizar);
    super.dispose();
  }

  void _sincronizar() {
    if (mounted) setState(() {});
  }

  Future<void> _pulsar() async {
    if (!widget.favoritos.canModify) {
      _avisarFaltaPermiso();
      return;
    }
    try {
      await widget.favoritos.toggle(widget.artista);
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is ApiException && e.isForbidden
          ? 'Spotify no dejó actualizar tus artistas seguidos: ${e.message}'
          : 'No se pudo actualizar el seguimiento: $e';
      final t = await traducirTexto(context, mensaje);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _avisarFaltaPermiso() {
    final reauth = widget.favoritos.onReauth;
    unawaited(() async {
      final t = await traducirTexto(
        context,
        'Tu sesión se inició sin permiso para seguir artistas en Spotify. Hay '
        'que volver a pasar por Spotify otra vez.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(t),
          action: reauth == null
              ? null
              : SnackBarAction(
                  label: 'Iniciar sesión',
                  onPressed: () => unawaited(reauth()),
                ),
        ),
      );
    }());
  }

  @override
  Widget build(BuildContext context) {
    final siguiendo = widget.favoritos.esFavorito(widget.artista.id);
    final ocupado = widget.favoritos.estaEnCurso(widget.artista.id);
    final colores = Theme.of(context).colorScheme;

    return Tooltip(
      message: siguiendo
          ? 'Dejar de seguir en Spotify'
          : 'Seguir en Spotify',
      child: OutlinedButton(
        onPressed: ocupado ? null : () => unawaited(_pulsar()),
        style: OutlinedButton.styleFrom(
          visualDensity: widget.compacto
              ? VisualDensity.compact
              : VisualDensity.standard,
          padding: widget.compacto
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          minimumSize: Size(0, widget.compacto ? 30 : 38),
          side: BorderSide(
            color: siguiendo ? colores.outline : colores.onSurfaceVariant,
          ),
          shape: const StadiumBorder(),
          backgroundColor: siguiendo
              ? colores.surfaceContainerHighest.withValues(alpha: 0.35)
              : null,
        ),
        child: T(
          siguiendo ? 'Siguiendo' : 'Seguir',
          style: TextStyle(
            fontSize: widget.compacto ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: colores.onSurface,
          ),
        ),
      ),
    );
  }
}
