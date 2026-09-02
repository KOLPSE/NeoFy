import 'dart:async';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/spotify_api.dart';
import 'corazon_animado.dart';
import 'texto_traducido.dart';

class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.likes,
    required this.uri,
    this.pista,
    this.size = 20,
    this.caja = 36,
  });

  final LikedStore likes;
  final String uri;
  final Track? pista;
  final double size;
  final double caja;

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
      await widget.likes.toggle(widget.uri, pista: widget.pista);
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is ApiException && e.isForbidden
          ? 'Spotify no dejó cambiar tus favoritos: ${e.message}'
          : 'No se pudo cambiar: $e';
      final t = await traducirTexto(context, mensaje);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _avisarFaltaPermiso() {
    final reauth = widget.likes.onReauth;
    unawaited(() async {
      final t = await traducirTexto(
        context,
        'Tu sesión se inició sin permiso para editar favoritos. Hay que volver '
        'a pasar por Spotify otra vez.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(t),
        action: reauth == null
            ? null
            : SnackBarAction(
                label: 'Iniciar sesión',
                onPressed: () => unawaited(reauth()),
              ),
      ));
    }());
  }

  @override
  Widget build(BuildContext context) {
    final lleno = widget.likes.isSaved(widget.uri) ?? false;
    return CorazonAnimado(
      lleno: lleno,
      size: widget.size,
      caja: widget.caja,
      tooltip: lleno ? 'Quitar de tus me gusta' : 'Guardar en tus me gusta',
      onTap: _pulsar,
    );
  }
}
