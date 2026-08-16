import 'dart:async';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'art_image.dart';
import 'track_tile.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.api,
    required this.player,
    required this.sidecar,
    required this.playlist,
    required this.likes,
  });

  final SpotifyApi api;
  final PlayerController player;
  final MetadataSidecar sidecar;
  final Playlist playlist;
  final LikedStore likes;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final _scroll = ScrollController();
  final List<Track> _tracks = [];

  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  int _offset = 0;

  bool _viaSidecar = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        unawaited(_loadMore());
      }
    });
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await _pedirPagina();
      if (!mounted) return;
      setState(() {
        _tracks.addAll(page.items);
        _offset += page.rawCount;
        _hasMore = page.hasMore;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.isForbidden
          ? 'Spotify no deja ver las canciones de esta playlist.\n\n'
              'Es de ${widget.playlist.owner.isEmpty ? "otra persona" : widget.playlist.owner}, '
              'y una app en Modo Desarrollo solo puede leer el contenido de tus '
              'propias playlists.\n\n'
              '${widget.sidecar.error ?? "El lector de metadatos no está disponible"}.\n\n'
              'Sí puedes reproducirla entera con el botón de arriba.'
          : '$e');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ApiPage<Track>> _pedirPagina() async {
    if (_viaSidecar) {
      return widget.sidecar
          .playlistItems(widget.playlist.id, offset: _offset, limit: 50);
    }
    try {
      return await widget.api
          .playlistItems(widget.playlist.id, limit: 50, offset: _offset);
    } on ApiException catch (e) {
      if (!e.isForbidden || !widget.sidecar.ready) rethrow;
      final page = await widget.sidecar
          .playlistItems(widget.playlist.id, offset: _offset, limit: 50);
      if (mounted) setState(() => _viaSidecar = true);
      return page;
    }
  }

  Future<void> _remove(Track track) async {
    try {
      await widget.api.removeFromPlaylist(widget.playlist.id, [track.uri]);
      if (!mounted) return;
      setState(() => _tracks.removeWhere((t) => t.uri == track.uri));
      _toast('Quitada de ${widget.playlist.name}');
    } catch (e) {
      _toast('No se pudo quitar: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              ArtImage(url: widget.playlist.art, size: 96, radius: 6),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.playlist.name,
                        style: theme.textTheme.headlineSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.playlist.owner} · ${widget.playlist.trackCount} canciones'
                      '${_viaSidecar ? " · leída vía librespot" : ""}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => widget.player.playContext(widget.playlist.uri),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Reproducir'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _error != null && _tracks.isEmpty
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                )
              : ValueListenableBuilder<String?>(
                  valueListenable: widget.player.currentUri,
                  builder: (context, currentUri, _) => ListView.builder(
                  controller: _scroll,
                  itemCount: _tracks.length + (_loading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _tracks.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final t = _tracks[i];
                    return TrackTile(
                      track: t,
                      likes: widget.likes,
                      leadingNumber: i + 1,
                      isCurrent: currentUri != null && currentUri == t.uri,
                      actions: TrackActions(
                        onPlay: () => widget.player
                            .playContext(widget.playlist.uri, offset: i),
                        onQueue: () async {
                          await widget.player.addToQueue(t.uri);
                          _toast('Añadida a la cola');
                        },
                        onRemove: () => _remove(t),
                      ),
                    );
                  },
                ),
                ),
        ),
      ],
    );
  }
}
