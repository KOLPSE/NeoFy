import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import 'art_image.dart';
import 'desplegable_en_sitio.dart';
import 'like_button.dart';
import 'now_playing_bar.dart' show formatMs;
import 'texto_traducido.dart';

class TrackActions {
  const TrackActions({
    this.onPlay,
    this.onQueue,
    this.onAddToPlaylist,
    this.onRemove,
  });

  final VoidCallback? onPlay;
  final VoidCallback? onQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onRemove;
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.actions,
    this.likes,
    this.isCurrent = false,
    this.leadingNumber,
    this.showArt = true,
    this.contentPadding,
  });

  final Track track;
  final TrackActions actions;
  final bool isCurrent;
  final int? leadingNumber;

  final LikedStore? likes;

  final bool showArt;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DesplegableEnSitio(
      icono: Icons.more_vert,
      tooltip: 'Más opciones',
      opciones: [
        if (actions.onQueue != null)
          OpcionEnSitio(
            icono: Icons.queue_music,
            texto: 'Añadir a la cola',
            onTap: actions.onQueue!,
          ),
        if (actions.onAddToPlaylist != null)
          OpcionEnSitio(
            icono: Icons.playlist_add,
            texto: 'Añadir a una playlist',
            onTap: actions.onAddToPlaylist!,
          ),
        if (actions.onRemove != null)
          OpcionEnSitio(
            icono: Icons.remove_circle_outline,
            texto: 'Quitar de esta playlist',
            onTap: actions.onRemove!,
            destructiva: true,
            confirmacion: '¿Quitar «${track.name}» de esta playlist?',
            textoConfirmar: 'Quitar',
          ),
      ],
      constructor: (context, disparador) => ListTile(
        dense: true,
        onTap: actions.onPlay,
        contentPadding: contentPadding,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingNumber != null)
              SizedBox(
                width: 28,
                child: Text(
                  '$leadingNumber',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.right,
                ),
              ),
            const SizedBox(width: 8),
            ArtImage(url: showArt ? track.artSmall : null, size: 40),
          ],
        ),
        title: Text(
          track.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isCurrent
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary, fontWeight: FontWeight.w600)
              : null,
        ),
        subtitle: Text(
          track.artists,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (likes != null && track.uri.isNotEmpty)
              LikeButton(likes: likes!, uri: track.uri, pista: track),
            Text(formatMs(track.durationMs), style: theme.textTheme.bodySmall),
            disparador,
          ],
        ),
      ),
    );
  }
}

Future<Playlist?> pickPlaylist(BuildContext context, List<Playlist> playlists) {
  return showDialogTraducido<Playlist>(
    context: context,
    builder: (context) => AlertDialog(
      title: T('Añadir a una playlist'),
      content: SizedBox(
        width: 360,
        height: 400,
        child: playlists.isEmpty
            ? const Center(child: T('No hay playlists cargadas.'))
            : ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final pl = playlists[i];
                  return ListTile(
                    dense: true,
                    leading: ArtImage(url: pl.art, size: 32),
                    title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(pl),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: T('Cancelar'),
        ),
      ],
    ),
  );
}

class PlaylistSearchTile extends StatelessWidget {
  const PlaylistSearchTile({
    super.key,
    required this.playlist,
    required this.onTap,
    this.trailing,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitulo = playlist.owner.isNotEmpty
        ? 'Playlist • ${playlist.owner}'
        : (playlist.trackCount > 0 ? '${playlist.trackCount} canciones' : 'Playlist');

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          ArtImage(url: playlist.art, size: 40),
        ],
      ),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: T(
        subtitulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class ArtistSearchTile extends StatelessWidget {
  const ArtistSearchTile({
    super.key,
    required this.artista,
    required this.onTap,
    this.trailing,
  });

  final Artist artista;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitulo = artista.followers > 0
        ? 'Artista · ${formatearCuenta(artista.followers)} seguidores'
        : 'Artista';

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          ArtImage(url: artista.art, size: 40),
        ],
      ),
      title: Text(
        artista.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: T(
        subtitulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
    );
  }
}
