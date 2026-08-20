import 'dart:async';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/spotify_api.dart';
import 'corazon_animado.dart';

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

class _LikeButtonState extends State<LikeButton> {
  @override
  void initState() {
    super.initState();
    widget.likes.addListener(_sincronizar);
    widget.likes.ensureKnown(widget.uri);
  }

  @override
  void didUpdateWidget(covariant LikeButton old) {
    super.didUpdateWidget(old);
    if (old.uri == widget.uri) return;
    widget.likes.ensureKnown(widget.uri);
    setState(() {});
  }

  @override
  void dispose() {
    widget.likes.removeListener(_sincronizar);
    super.dispose();
  }

  void _sincronizar() {
    if (mounted) setState(() {});
  }

  Future<void> _pulsar() async {
    if (!widget.likes.canModify) {
      _avisarFaltaPermiso();
      return;
    }
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
    final lleno = widget.likes.isSaved(widget.uri) ?? false;
    return CorazonAnimado(
      lleno: lleno,
      size: widget.size,
      tooltip: lleno ? 'Quitar de tus me gusta' : 'Guardar en tus me gusta',
      onTap: _pulsar,
    );
  }
}
