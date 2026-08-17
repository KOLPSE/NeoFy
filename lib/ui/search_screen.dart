import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'track_tile.dart';

enum SearchFilter {
  todo('Todo'),
  canciones('Canciones'),
  playlists('Playlists'),
  masEscuchadas('Más escuchadas');

  const SearchFilter(this.label);
  final String label;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.api,
    required this.player,
    required this.playlists,
    required this.likes,
    this.onAbrirPlaylist,
    this.autofocus = true,
  });

  final SpotifyApi api;
  final PlayerController player;
  final List<Playlist> playlists;
  final LikedStore likes;
  final void Function(Playlist)? onAbrirPlaylist;
  final bool autofocus;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Track> _tracks = [];
  final List<Playlist> _playlists = [];

  SearchFilter _filter = SearchFilter.todo;
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  int _offset = 0;
  int _searchId = 0;

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
      _tracks.clear();
      _playlists.clear();
      _offset = 0;
      _hasMore = _query.isNotEmpty;
      _error = null;
      unawaited(_search());
    });
  }

  void _cambiarFiltro(SearchFilter nuevo) {
    if (_filter == nuevo) return;
    _debounce?.cancel();
    setState(() {
      _filter = nuevo;
      _tracks.clear();
      _playlists.clear();
      _offset = 0;
      _hasMore = _query.isNotEmpty;
      _error = null;
    });
    if (_query.isNotEmpty) {
      unawaited(_search());
    }
  }

  Future<void> _search() async {
    if (_loading || _query.isEmpty) return;
    setState(() => _loading = true);
    final currentId = ++_searchId;

    final List<String> types;
    switch (_filter) {
      case SearchFilter.todo:
        types = const ['track', 'playlist'];
      case SearchFilter.canciones:
      case SearchFilter.masEscuchadas:
        types = const ['track'];
      case SearchFilter.playlists:
        types = const ['playlist'];
    }

    try {
      final res = await widget.api.search(_query, types: types, limit: 10, offset: _offset);
      if (!mounted || currentId != _searchId) return;

      setState(() {
        switch (_filter) {
          case SearchFilter.todo:
            _tracks.addAll(res.tracks.items);
            _playlists.addAll(res.playlists.items);
            _offset += max(res.tracks.rawCount, res.playlists.rawCount);
            _hasMore = res.tracks.hasMore || res.playlists.hasMore;
          case SearchFilter.canciones:
            _tracks.addAll(res.tracks.items);
            _offset += res.tracks.rawCount;
            _hasMore = res.tracks.hasMore;
          case SearchFilter.playlists:
            _playlists.addAll(res.playlists.items);
            _offset += res.playlists.rawCount;
            _hasMore = res.playlists.hasMore;
          case SearchFilter.masEscuchadas:
            _tracks.addAll(res.tracks.items);
            _tracks.sort((a, b) => b.popularity.compareTo(a.popularity));
            _offset += res.tracks.rawCount;
            _hasMore = res.tracks.hasMore;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted && currentId == _searchId) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted && currentId == _searchId) {
        setState(() => _loading = false);
      }
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

  bool get _vacio => _tracks.isEmpty && _playlists.isEmpty;

  int _calcularTotalItems() {
    final boton = _hasMore ? 1 : 0;
    switch (_filter) {
      case SearchFilter.canciones:
      case SearchFilter.masEscuchadas:
        return _tracks.length + boton;
      case SearchFilter.playlists:
        return _playlists.length + boton;
      case SearchFilter.todo:
        final headPl = _playlists.isNotEmpty ? 1 : 0;
        final headTr = (_tracks.isNotEmpty && _playlists.isNotEmpty) ? 1 : 0;
        return headPl + _playlists.length + headTr + _tracks.length + boton;
    }
  }

  Widget _construirItem(BuildContext context, int i, String? currentUri) {
    switch (_filter) {
      case SearchFilter.canciones:
        if (i >= _tracks.length) return _botonCargarMas();
        return _tileTrack(_tracks[i], i, currentUri);
      case SearchFilter.masEscuchadas:
        if (i >= _tracks.length) return _botonCargarMas();
        return _tileTrack(_tracks[i], i, currentUri, orden: i + 1);
      case SearchFilter.playlists:
        if (i >= _playlists.length) return _botonCargarMas();
        return _tilePlaylist(_playlists[i]);
      case SearchFilter.todo:
        return _construirItemTodo(context, i, currentUri);
    }
  }

  Widget _construirItemTodo(BuildContext context, int i, String? currentUri) {
    var idx = i;
    if (_playlists.isNotEmpty) {
      if (idx == 0) return const _HeaderSeccion('Playlists');
      idx -= 1;
      if (idx < _playlists.length) {
        return _tilePlaylist(_playlists[idx]);
      }
      idx -= _playlists.length;
    }

    if (_tracks.isNotEmpty) {
      if (_playlists.isNotEmpty) {
        if (idx == 0) return const _HeaderSeccion('Canciones');
        idx -= 1;
      }
      if (idx < _tracks.length) {
        return _tileTrack(_tracks[idx], idx, currentUri);
      }
      idx -= _tracks.length;
    }

    return _botonCargarMas();
  }

  Widget _tileTrack(Track t, int indice, String? currentUri, {int? orden}) {
    return TrackTile(
      track: t,
      likes: widget.likes,
      leadingNumber: orden,
      isCurrent: currentUri != null && currentUri == t.uri,
      actions: TrackActions(
        onPlay: () => widget.player.playLista(
          [for (final r in _tracks) r.uri],
          desde: indice,
        ),
        onQueue: () async {
          await widget.player.addToQueue(t.uri);
          _toast('Añadida a la cola');
        },
        onAddToPlaylist: () => _addToPlaylist(t),
      ),
    );
  }

  Widget _tilePlaylist(Playlist pl) {
    return PlaylistSearchTile(
      playlist: pl,
      onTap: () => widget.onAbrirPlaylist?.call(pl),
    );
  }

  Widget _botonCargarMas() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _search,
                child: const Text('Ver más resultados'),
              ),
      ),
    );
  }

  Widget _cuerpoResultados(ThemeData theme) {
    if (_vacio) {
      return Center(
        child: Text(
          _loading
              ? 'Buscando…'
              : _query.isEmpty
                  ? 'Escribe para buscar en Spotify.'
                  : 'Sin resultados.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ValueListenableBuilder<String?>(
      valueListenable: widget.player.currentUri,
      builder: (context, currentUri, _) {
        final total = _calcularTotalItems();
        return ListView.builder(
          controller: _scroll,
          itemCount: total,
          itemBuilder: (context, i) => _construirItem(context, i, currentUri),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: widget.autofocus,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar canciones, playlists…',
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
                          _tracks.clear();
                          _playlists.clear();
                          _query = '';
                          _offset = 0;
                          _hasMore = false;
                          _error = null;
                        });
                      },
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final filter in SearchFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter.label),
                    selected: _filter == filter,
                    onSelected: (selected) {
                      if (selected && _filter != filter) {
                        _cambiarFiltro(filter);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Expanded(
          child: _cuerpoResultados(theme),
        ),
      ],
    );
  }
}

class _HeaderSeccion extends StatelessWidget {
  const _HeaderSeccion(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        titulo,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
