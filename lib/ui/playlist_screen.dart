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

  /// Offset en elementos **crudos**: una página de 50 puede dejarnos menos
  /// pistas tras descartar las no reproducibles, y avanzar por las que quedan
  /// se saltaría canciones.
  int _offset = 0;

  /// Esta playlist se está leyendo por el sidecar porque la Web API la deniega.
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

  /// Scroll infinito de 50 en 50. Una playlist de miles de canciones nunca
  /// llega entera a memoria; solo el trozo que se ha mirado.
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
      // Spotify capó el Modo Desarrollo en febrero de 2026: solo deja leer las
      // canciones de playlists propias o colaborativas. Las ajenas dan 403 sin
      // más explicación, y "Forbidden" a secas no le dice nada a nadie.
      // Con el sidecar en marcha este 403 ya no debería llegar hasta aquí:
      // solo queda como mensaje para cuando el sidecar no está disponible.
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

  /// Vía oficial primero; el sidecar solo cuando Spotify se niegue.
  ///
  /// El 403 llega en playlists que no son tuyas, que es exactamente el caso que
  /// el sidecar resuelve leyendo por el protocolo interno de librespot. Una vez
  /// que una playlist ha caído por esa vía, las siguientes páginas van directas
  /// al sidecar en lugar de volver a comerse el 403.
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
                      // Merece decirlo: esta lista no viene de la API oficial.
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
              // Escuchar aquí la uri que suena es lo que mueve el título
              // verde de una canción a la siguiente. Antes se leía del estado
              // en `build` sin escuchar nada, así que se quedaba clavado en la
              // canción con la que se abrió la pantalla.
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
                        // Reproducir desde el contexto de la playlist (y no la
                        // canción suelta) para que "siguiente" siga la lista.
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
