import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import 'art_image.dart';
import 'like_button.dart';
import 'now_playing_bar.dart' show formatMs;

/// Acciones que puede ofrecer una fila de canción. Se pasan las que apliquen:
/// "quitar" solo tiene sentido dentro de una playlist propia.
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
  });

  final Track track;
  final TrackActions actions;
  final bool isCurrent;
  final int? leadingNumber;

  /// Estado de "me gusta" compartido por toda la app. Sin él no se pinta el
  /// corazón, que es lo que quieren los tests de alto y cualquier lista que no
  /// tenga sesión detrás.
  final LikedStore? likes;

  /// Con `false` se pinta el hueco en vez de la carátula. Lo usan las listas
  /// muy largas para no tener miles de imágenes descargándose y decodificándose
  /// solo porque el usuario ha pasado el scroll por encima.
  final bool showArt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      onTap: actions.onPlay,
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
          // 40 px en listas: se pide la variante de 64 px de Spotify, no la de
          // 640. Es la diferencia entre una lista que ocupa megas y una que no.
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
            LikeButton(likes: likes!, uri: track.uri),
          Text(formatMs(track.durationMs), style: theme.textTheme.bodySmall),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            tooltip: 'Más opciones',
            onSelected: (value) {
              switch (value) {
                case 'queue':
                  actions.onQueue?.call();
                case 'add':
                  actions.onAddToPlaylist?.call();
                case 'remove':
                  actions.onRemove?.call();
              }
            },
            itemBuilder: (context) => [
              if (actions.onQueue != null)
                const PopupMenuItem(value: 'queue', child: Text('Añadir a la cola')),
              if (actions.onAddToPlaylist != null)
                const PopupMenuItem(value: 'add', child: Text('Añadir a una playlist')),
              if (actions.onRemove != null)
                const PopupMenuItem(value: 'remove', child: Text('Quitar de esta playlist')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Diálogo para elegir a qué playlist va una canción.
Future<Playlist?> pickPlaylist(BuildContext context, List<Playlist> playlists) {
  return showDialog<Playlist>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Añadir a una playlist'),
      content: SizedBox(
        width: 360,
        height: 400,
        child: playlists.isEmpty
            ? const Center(child: Text('No hay playlists cargadas.'))
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
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}
