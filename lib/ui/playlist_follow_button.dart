import 'dart:async';

import 'package:flutter/material.dart';

import '../core/followed_playlists_store.dart';
import '../core/models.dart';
import '../core/spotify_api.dart';
import 'corazon_animado.dart';

class PlaylistFollowButton extends StatefulWidget {
  const PlaylistFollowButton({
    super.key,
    required this.followed,
    required this.playlist,
    this.esPropia = false,
    this.onCambio,
    this.size = 20,
  });

  final FollowedPlaylistsStore followed;
  final Playlist playlist;
  final bool esPropia;
  final void Function(Playlist playlist, bool ahoraSeguida)? onCambio;
  final double size;

  @override
  State<PlaylistFollowButton> createState() => _PlaylistFollowButtonState();
}

class _PlaylistFollowButtonState extends State<PlaylistFollowButton> {
  @override
  void initState() {
    super.initState();
    widget.followed.addListener(_sincronizar);
    unawaited(widget.followed.ensureKnown(widget.playlist.id));
  }

  @override
  void didUpdateWidget(covariant PlaylistFollowButton old) {
    super.didUpdateWidget(old);
    if (old.playlist.id == widget.playlist.id) return;
    unawaited(widget.followed.ensureKnown(widget.playlist.id));
    setState(() {});
  }

  @override
  void dispose() {
    widget.followed.removeListener(_sincronizar);
    super.dispose();
  }

  void _sincronizar() {
    if (mounted) setState(() {});
  }

  Future<void> _pulsar() async {
    final seguida = widget.followed.isFollowed(widget.playlist.id) ?? false;
    if (widget.esPropia && seguida) {
      _toast('Es tuya: para quitarla usa el menú de «Mis playlists».');
      return;
    }
    if (!widget.followed.canModify) {
      _avisarFaltaPermiso();
      return;
    }
    try {
      await widget.followed.toggle(widget.playlist.id);
      final ahoraSeguida = widget.followed.isFollowed(widget.playlist.id) ?? false;
      widget.onCambio?.call(widget.playlist, ahoraSeguida);
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is ApiException && e.isForbidden
          ? 'Spotify no dejó cambiar tus playlists: ${e.message}'
          : 'No se pudo cambiar: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  void _avisarFaltaPermiso() {
    final reauth = widget.followed.onReauth;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text(
        'Tu sesión se inició sin permiso para editar tus playlists. Hay que volver '
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
    final seguida = widget.followed.isFollowed(widget.playlist.id) ?? false;
    final tooltip = widget.esPropia && seguida
        ? 'Es tuya, ya está en tu biblioteca'
        : seguida
            ? 'Quitar de mis playlists'
            : 'Guardar en mis playlists';
    return CorazonAnimado(
      lleno: seguida,
      size: widget.size,
      tooltip: tooltip,
      onTap: _pulsar,
    );
  }
}
