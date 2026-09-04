import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/followed_playlists_store.dart';
import '../core/idiomas_spotify.dart';
import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'artist_favorite_button.dart';
import 'playlist_follow_button.dart';
import 'texto_traducido.dart';
import 'track_tile.dart';

enum SearchFilter {
  todo('Todo'),
  artistas('Artistas'),
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
    required this.followed,
    required this.favoritos,
    required this.sidecar,
    required this.localeEfectivo,
    this.onAbrirPlaylist,
    this.onAbrirArtista,
    this.onCambioSeguimiento,
    this.autofocus = true,
  });

  final SpotifyApi api;
  final PlayerController player;
  final List<Playlist> playlists;
  final LikedStore likes;
  final FollowedPlaylistsStore followed;
  final ArtistasFavoritosStore favoritos;

  /// De aquí salen los "éxitos del idioma" que se muestran con la caja
  /// vacía: la Web API en modo desarrollo no sirve las editoriales, así
  /// que el Top 50 del país se lee por librespot.
  final MetadataSidecar sidecar;

  /// Locale vigente (`es_ES`…); decide el Top 50 del país. Se compara en
  /// cada build para recargar la lista si el usuario cambia de idioma.
  final String localeEfectivo;

  final void Function(Playlist)? onAbrirPlaylist;
  final void Function(Artist)? onAbrirArtista;
  final void Function(Playlist, bool)? onCambioSeguimiento;
  final bool autofocus;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Track> _tracks = [];
  final List<Playlist> _playlists = [];
  final List<Artist> _artistas = [];

  // La pantalla abre en "Más escuchadas": con la caja vacía enseña el
  // Top 50 del idioma, y al escribir salta sola a "Todo".
  SearchFilter _filter = SearchFilter.masEscuchadas;
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  int _offset = 0;
  int _searchId = 0;

  List<Track>? _top50;
  String? _errorTop50;
  bool _cargandoTop50 = false;
  String _localeDelTop50 = '';

  @override
  void initState() {
    super.initState();
    widget.sidecar.addListener(_alCambiarSidecar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _asegurarTop50());
  }

  @override
  void didUpdateWidget(covariant SearchScreen viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.sidecar != widget.sidecar) {
      viejo.sidecar.removeListener(_alCambiarSidecar);
      widget.sidecar.addListener(_alCambiarSidecar);
    }
    if (viejo.localeEfectivo != widget.localeEfectivo &&
        widget.localeEfectivo != _localeDelTop50) {
      _top50 = null;
      _asegurarTop50();
    }
  }

  @override
  void dispose() {
    widget.sidecar.removeListener(_alCambiarSidecar);
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alCambiarSidecar() {
    // El sidecar se arranca en paralelo al login; cuando queda listo ya
    // se pueden pedir los éxitos.
    if (widget.sidecar.ready && _top50 == null && mounted) _asegurarTop50();
  }

  void _reiniciarResultados() {
    _tracks.clear();
    _playlists.clear();
    _artistas.clear();
    _offset = 0;
    _hasMore = _query.isNotEmpty;
    _error = null;
  }

  void _onChanged(String value) {
    final q = value.trim();
    // Al escribir se busca en todo; al vaciar la caja vuelve el Top 50.
    final filtro = q.isEmpty
        ? SearchFilter.masEscuchadas
        : (_filter == SearchFilter.masEscuchadas && _query.isEmpty
            ? SearchFilter.todo
            : _filter);
    if (filtro != _filter) setState(() => _filter = filtro);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = q;
      _reiniciarResultados();
      unawaited(_search());
    });
  }

  Future<void> _asegurarTop50() async {
    if (!mounted ||
        !widget.sidecar.ready ||
        _top50 != null ||
        _cargandoTop50) {
      return;
    }
    setState(() {
      _cargandoTop50 = true;
      _errorTop50 = null;
    });
    final locale = widget.localeEfectivo;
    try {
      ApiPage<Track> pagina;
      try {
        pagina = await widget.sidecar
            .playlistItems(playlistTop50ParaLocale(locale), limit: 50);
      } catch (_) {
        // Si la editorial del país falla (id retirado, región sin lista),
        // queda el global.
        pagina = await widget.sidecar.playlistItems(kTop50Global, limit: 50);
      }
      if (!mounted) return;
      setState(() {
        _top50 = pagina.items;
        _localeDelTop50 = locale;
      });
    } catch (e) {
      if (mounted) setState(() => _errorTop50 = '$e');
    } finally {
      if (mounted) setState(() => _cargandoTop50 = false);
    }
  }

  void _cambiarFiltro(SearchFilter nuevo) {
    if (_filter == nuevo) return;
    _debounce?.cancel();
    setState(() {
      _filter = nuevo;
      _reiniciarResultados();
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
        types = const ['artist', 'track', 'playlist'];
      case SearchFilter.artistas:
        types = const ['artist'];
      case SearchFilter.canciones:
      case SearchFilter.masEscuchadas:
        types = const ['track'];
      case SearchFilter.playlists:
        types = const ['playlist'];
    }

    try {
      final res =
          await widget.api.search(_query, types: types, limit: 10, offset: _offset);
      if (!mounted || currentId != _searchId) return;

      setState(() {
        switch (_filter) {
          case SearchFilter.todo:
            _artistas.addAll(res.artists.items);
            _tracks.addAll(res.tracks.items);
            _playlists.addAll(res.playlists.items);
            _offset += max(
              max(res.artists.rawCount, res.tracks.rawCount),
              res.playlists.rawCount,
            );
            _hasMore =
                res.artists.hasMore || res.tracks.hasMore || res.playlists.hasMore;
          case SearchFilter.artistas:
            _artistas.addAll(res.artists.items);
            _offset += res.artists.rawCount;
            _hasMore = res.artists.hasMore;
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
    unawaited(() async {
      final t = await traducirTexto(context, message);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
    }());
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

  bool get _vacio => _tracks.isEmpty && _playlists.isEmpty && _artistas.isEmpty;

  int _calcularTotalItems() {
    final boton = _hasMore ? 1 : 0;
    switch (_filter) {
      case SearchFilter.canciones:
      case SearchFilter.masEscuchadas:
        return _tracks.length + boton;
      case SearchFilter.playlists:
        return _playlists.length + boton;
      case SearchFilter.artistas:
        return _artistas.length + boton;
      case SearchFilter.todo:
        final headAr = _artistas.isNotEmpty ? 1 : 0;
        final headPl = _playlists.isNotEmpty ? 1 : 0;
        final headTr = _tracks.isNotEmpty ? 1 : 0;
        return headAr +
            _artistas.length +
            headPl +
            _playlists.length +
            headTr +
            _tracks.length +
            boton;
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
      case SearchFilter.artistas:
        if (i >= _artistas.length) return _botonCargarMas();
        return _tileArtista(_artistas[i]);
      case SearchFilter.todo:
        return _construirItemTodo(context, i, currentUri);
    }
  }

  Widget _construirItemTodo(BuildContext context, int i, String? currentUri) {
    var idx = i;
    if (_artistas.isNotEmpty) {
      if (idx == 0) return const _HeaderSeccion('Artistas');
      idx -= 1;
      if (idx < _artistas.length) {
        return _tileArtista(_artistas[idx]);
      }
      idx -= _artistas.length;
    }

    if (_playlists.isNotEmpty) {
      if (idx == 0) return const _HeaderSeccion('Playlists');
      idx -= 1;
      if (idx < _playlists.length) {
        return _tilePlaylist(_playlists[idx]);
      }
      idx -= _playlists.length;
    }

    if (_tracks.isNotEmpty) {
      if (idx == 0) return const _HeaderSeccion('Canciones');
      idx -= 1;
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlaylistFollowButton(
            followed: widget.followed,
            playlist: pl,
            esPropia: pl.ownerId.isNotEmpty && pl.ownerId == widget.player.currentUserId,
            size: 18,
            onCambio: widget.onCambioSeguimiento,
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _tileArtista(Artist a) {
    return ArtistSearchTile(
      artista: a,
      onTap: () => widget.onAbrirArtista?.call(a),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtistFavoriteButton(
            favoritos: widget.favoritos,
            artista: a,
            size: 18,
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
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
                child: T('Ver más resultados'),
              ),
      ),
    );
  }

  /// Con la caja vacía y "Más escuchadas" activo: el Top 50 del país del
  /// idioma, pedido al sidecar. Sin sidecar, la pantalla clásica.
  Widget _cuerpoTop50(ThemeData theme) {
    if (!widget.sidecar.ready) {
      return Center(
        child: T(
          'Escribe para buscar en NeoFy.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_errorTop50 != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorTop50!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _asegurarTop50,
              child: T('Reintentar'),
            ),
          ],
        ),
      );
    }
    final top = _top50;
    if (top == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (top.isEmpty) {
      return Center(
        child: T(
          'Escribe para buscar en NeoFy.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: widget.player.currentUri,
      builder: (context, currentUri, _) => ListView.builder(
        controller: _scroll,
        itemCount: top.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return const _HeaderSeccion('Lo más escuchado en tu idioma');
          final t = top[i - 1];
          return TrackTile(
            track: t,
            likes: widget.likes,
            leadingNumber: i,
            isCurrent: currentUri != null && currentUri == t.uri,
            actions: TrackActions(
              onPlay: () => widget.player.playLista(
                [for (final r in top) r.uri],
                desde: i - 1,
              ),
              onQueue: () async {
                await widget.player.addToQueue(t.uri);
                _toast('Añadida a la cola');
              },
              onAddToPlaylist: () => _addToPlaylist(t),
            ),
          );
        },
      ),
    );
  }

  Widget _cuerpoResultados(ThemeData theme) {
    if (_query.isEmpty) {
      if (_filter == SearchFilter.masEscuchadas) return _cuerpoTop50(theme);
      return Center(
        child: T(
          'Escribe para buscar en NeoFy.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_vacio) {
      return Center(
        child: T(
          _loading ? 'Buscando…' : 'Sin resultados.',
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
              hintText: 'Buscar artistas, canciones, playlists…',
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
                          _reiniciarResultados();
                          _query = '';
                          _filter = SearchFilter.masEscuchadas;
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
                    label: T(filter.label),
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
      child: T(
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
