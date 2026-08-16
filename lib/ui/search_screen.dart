import 'dart:async';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.api,
    required this.player,
    required this.playlists,
    required this.likes,
  });

  final SpotifyApi api;
  final PlayerController player;
  final List<Playlist> playlists;
  final LikedStore likes;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Track> _results = [];

  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  int _offset = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value.trim();
      _results.clear();
      _offset = 0;
      _hasMore = _query.isNotEmpty;
      unawaited(_search());
    });
  }

  Future<void> _search() async {
    if (_loading || _query.isEmpty) return;
    setState(() => _loading = true);
    try {
      final page = await widget.api.searchTracks(_query, limit: 10, offset: _offset);
      if (!mounted) return;
      setState(() {
        _results.addAll(page.items);
        _offset += page.rawCount;
        _hasMore = page.hasMore;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _addToPlaylist(Track track) async {
    final pl = await pickPlaylist(context, widget.playlists);
    if (pl == null) return;
    try {
      await widget.api.addToPlaylist(pl.id, [track.uri]);
      _toast('Añadida a ${pl.name}');
    } catch (e) {
      _toast('No se pudo añadir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar canciones…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _results.clear();
                          _query = '';
                          _offset = 0;
                          _hasMore = false;
                        });
                      },
                    ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _loading
                        ? 'Buscando…'
                        : _query.isEmpty
                            ? 'Escribe para buscar en Spotify.'
                            : 'Sin resultados.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ValueListenableBuilder<String?>(
                  valueListenable: widget.player.currentUri,
                  builder: (context, currentUri, _) => ListView.builder(
                  controller: _scroll,
                  itemCount: _results.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _results.length) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(
                                  onPressed: _search,
                                  child: const Text('Ver más resultados'),
                                ),
                        ),
                      );
                    }
                    final t = _results[i];
                    return TrackTile(
                      track: t,
                      likes: widget.likes,
                      isCurrent: currentUri != null && currentUri == t.uri,
                      actions: TrackActions(
                        onPlay: () => widget.player.playTrack(t.uri),
                        onQueue: () async {
                          await widget.player.addToQueue(t.uri);
                          _toast('Añadida a la cola');
                        },
                        onAddToPlaylist: () => _addToPlaylist(t),
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
