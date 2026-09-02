import 'dart:async';

import 'package:flutter/material.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/models.dart';
import 'corazon_animado.dart';

class ArtistFavoriteButton extends StatefulWidget {
  const ArtistFavoriteButton({
    super.key,
    required this.favoritos,
    required this.artista,
    this.size = 20,
    this.caja = 36,
  });

  final ArtistasFavoritosStore favoritos;
  final Artist artista;
  final double size;
  final double caja;

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
    await widget.favoritos.toggle(widget.artista);
  }

  @override
  Widget build(BuildContext context) {
    final lleno = widget.favoritos.esFavorito(widget.artista.id);
    return CorazonAnimado(
      lleno: lleno,
      size: widget.size,
      caja: widget.caja,
      tooltip: lleno
          ? 'Quitar de tus artistas favoritos'
          : 'Añadir a tus artistas favoritos',
      onTap: () => unawaited(_pulsar()),
    );
  }
}
