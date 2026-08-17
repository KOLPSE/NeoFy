import 'dart:async';

import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/carpetas_store.dart';
import '../core/home_store.dart';
import '../core/librespot.dart';
import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/resource_monitor.dart';
import '../core/settings.dart';
import '../core/updater.dart';
import '../core/spotify_api.dart';
import '../core/yt_auth.dart';
import 'art_image.dart';
import 'conectar_youtube.dart';
import 'artist_screen.dart';
import 'home_screen.dart';
import 'liked_screen.dart';
import 'now_playing_bar.dart';
import 'settings_dialog.dart';
import 'playlist_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';

enum _View { home, search, queue, liked, playlist, artist }

bool hayQuePedirMas({
  required bool quedanPaginas,
  required bool cargando,
  required bool hayError,
  required bool desborda,
  required bool seccionAbierta,
}) {
  if (!quedanPaginas || cargando || hayError) return false;
  if (!seccionAbierta) return false;
  return !desborda;
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.librespot,
    required this.sidecar,
    required this.likes,
    required this.home,
    required this.carpetas,
    required this.ram,
    required this.settings,
    required this.updater,
    required this.onSalirParaActualizar,
    required this.onReiniciarAudio,
    required this.onLogout,
    required this.onReauth,
    required this.ytAuth,
  });

  final SpotifyApi api;
  final SpotifyAuth auth;
  final PlayerController player;
  final LikedStore likes;
  final HomeStore home;
  final CarpetasStore carpetas;
  final ResourceMonitor ram;
  final Settings settings;
  final Updater updater;

  final Future<void> Function() onSalirParaActualizar;

  final Future<void> Function() onReiniciarAudio;
  final LibrespotManager librespot;
  final MetadataSidecar sidecar;
  final Future<void> Function() onLogout;
  final Future<void> Function() onReauth;

  final YtAuth ytAuth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scroll = ScrollController();
  final List<Playlist> _playlists = [];

  _View _view = _View.home;
  Playlist? _selected;

  Artist? _artista;
  bool _loading = false;
  bool _hasMore = true;
  bool _playlistsExpanded = true;
  String? _error;

  final Set<String> _carpetasPlegadas = {};

  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
      unawaited(_loadMore());
    }
  }

  void _revisarSiCargarMas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final conScroll = _scroll.hasClients && _scroll.position.maxScrollExtent > 0;
      if (!hayQuePedirMas(
        quedanPaginas: _hasMore,
        cargando: _loading,
        hayError: _error != null,
        desborda: conScroll,
        seccionAbierta: _playlistsExpanded,
      )) {
        return;
      }
      unawaited(_loadMore());
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await widget.api.myPlaylists(limit: 50, offset: _offset);
      if (!mounted) return;
      setState(() {
        _playlists.addAll(page.items);
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

  Future<void> _crearPlaylist() async {
    final nombre = await _pedirNombre(context);
    if (nombre == null || nombre.trim().isEmpty) return;
    try {
      final pl = await widget.api.createPlaylist(nombre.trim());
      if (!mounted) return;
      setState(() {
        _playlists.insert(0, pl);
        _offset++;
        _view = _View.playlist;
        _selected = pl;
      });
    } catch (e) {
      _avisar('No se pudo crear: $e');
    }
  }

  Future<void> _borrarPlaylist(Playlist pl) async {
    final mia = pl.ownerId.isNotEmpty && pl.ownerId == widget.player.currentUserId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mia ? 'Eliminar la playlist' : 'Quitarla de tu biblioteca'),
        content: Text(mia
            ? '«${pl.name}» desaparecerá de tu biblioteca. Spotify la guarda '
                'unos días y se puede recuperar desde la web.'
            : '«${pl.name}» es de ${pl.owner.isEmpty ? "otra persona" : pl.owner}: '
                'se quita de tu biblioteca, pero la original no se toca.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(mia ? 'Eliminar' : 'Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.unfollowPlaylist(pl.id);
      if (!mounted) return;
      setState(() {
        _playlists.removeWhere((p) => p.id == pl.id);
        if (_offset > 0) _offset--;
        if (_selected?.id == pl.id) {
          _selected = null;
          _view = _View.home;
        }
      });
      await widget.carpetas.quitarPlaylist(pl.id);
    } catch (e) {
      _avisar('No se pudo quitar: $e');
    }
  }

  Future<String?> _pedirNombre(
    BuildContext context, {
    String titulo = 'Nueva playlist',
    String etiqueta = 'Nombre',
    String boton = 'Crear',
    String pista = 'Mi playlist',
    String inicial = '',
  }) {
    final controlador = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: controlador,
          autofocus: true,
          decoration: InputDecoration(
            labelText: etiqueta,
            hintText: pista,
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controlador.text),
            child: Text(boton),
          ),
        ],
      ),
    ).whenComplete(() {
      controlador.dispose();
    });
  }

  Future<void> _crearCarpeta() async {
    final nombre = await _pedirNombre(
      context,
      titulo: 'Nueva carpeta',
      etiqueta: 'Nombre de la carpeta',
      pista: 'Mi carpeta',
    );
    if (nombre == null || nombre.trim().isEmpty) return;
    await widget.carpetas.crearCarpeta(nombre.trim());
  }

  Future<void> _renombrarCarpeta(Carpeta carpeta) async {
    final nombre = await _pedirNombre(
      context,
      titulo: 'Renombrar carpeta',
      etiqueta: 'Nombre de la carpeta',
      boton: 'Guardar',
      pista: 'Mi carpeta',
      inicial: carpeta.nombre,
    );
    if (nombre == null || nombre.trim().isEmpty) return;
    await widget.carpetas.renombrarCarpeta(carpeta.id, nombre.trim());
  }

  Future<void> _borrarCarpeta(Carpeta carpeta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar la carpeta'),
        content: Text('«${carpeta.nombre}» desaparece, pero sus playlists no '
            'se borran: vuelven a la lista.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _carpetasPlegadas.remove(carpeta.id);
    await widget.carpetas.borrarCarpeta(carpeta.id);
  }

  Future<void> _moverPlaylist(Playlist pl) async {
    const fuera = '__fuera__';
    final elegida = await showDialog<String>(
      context: context,
      builder: (context) {
        final carpetas = widget.carpetas.carpetas;
        final actual = widget.carpetas.carpetaDe(pl.id);
        return SimpleDialog(
          title: const Text('Mover a carpeta'),
          children: [
            for (final c in carpetas)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(c.id),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(c.nombre,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (c.id == actual?.id)
                      const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(fuera),
              child: Row(
                children: [
                  const Expanded(child: Text('Fuera de cualquier carpeta')),
                  if (actual == null) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (elegida == null) return;
    await widget.carpetas.moverPlaylist(pl.id, elegida == fuera ? null : elegida);
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    _revisarSiCargarMas();
    return _scaffold(context);
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([widget.player, widget.carpetas]),
                  builder: (context, _) => _Sidebar(
                    playlists: _playlists,
                    carpetas: widget.carpetas.carpetas,
                    carpetasPlegadas: _carpetasPlegadas,
                    scroll: _scroll,
                    loading: _loading,
                    error: _error,
                    view: _view,
                    selected: _selected,
                    expanded: _playlistsExpanded,
                    playingContextUri: widget.player.state.contextUri,
                    onToggleExpanded: () =>
                        setState(() => _playlistsExpanded = !_playlistsExpanded),
                    onToggleCarpeta: (id) => setState(() {
                      if (!_carpetasPlegadas.add(id)) {
                        _carpetasPlegadas.remove(id);
                      }
                    }),
                    onSelectView: (v) => setState(() {
                      _view = v;
                      _selected = null;
                    }),
                    onSelectPlaylist: (pl) => setState(() {
                      _view = _View.playlist;
                      _selected = pl;
                    }),
                    onLogout: widget.onLogout,
                    onCreatePlaylist: _crearPlaylist,
                    onCreateCarpeta: _crearCarpeta,
                    onDeletePlaylist: _borrarPlaylist,
                    onRenombrarCarpeta: _renombrarCarpeta,
                    onBorrarCarpeta: _borrarCarpeta,
                    onMoverPlaylist: _moverPlaylist,
                    ram: widget.ram,
                    settings: widget.settings,
                    updater: widget.updater,
                    onSalirParaActualizar: widget.onSalirParaActualizar,
                    onReiniciarAudio: widget.onReiniciarAudio,
                    ytAuth: widget.ytAuth,
                    sinPremium: widget.player.premiumChecked &&
                        !widget.player.isPremium,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _content()),
              ],
            ),
          ),
          const Divider(height: 1),
          NowPlayingBar(
            player: widget.player,
            librespot: widget.librespot,
            likes: widget.likes,
            home: widget.home,
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (_view) {
      case _View.home:
        return HomeScreen(
          home: widget.home,
          player: widget.player,
          likes: widget.likes,
          onReauth: widget.onReauth,
          onAbrirArtista: (a) => setState(() {
            _artista = a;
            _view = _View.artist;
          }),
        );
      case _View.search:
        return SearchScreen(
          api: widget.api,
          player: widget.player,
          playlists: _playlists,
          likes: widget.likes,
          onAbrirPlaylist: (pl) => setState(() {
            _view = _View.playlist;
            _selected = pl;
          }),
        );
      case _View.queue:
        return QueueScreen(
          api: widget.api,
          player: widget.player,
          likes: widget.likes,
        );
      case _View.liked:
        return LikedScreen(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          playlists: _playlists,
          likes: widget.likes,
          onReauth: widget.onReauth,
        );
      case _View.playlist:
        final pl = _selected;
        if (pl == null) return const SizedBox.shrink();
        return PlaylistScreen(
          key: ValueKey(pl.id),
          api: widget.api,
          player: widget.player,
          sidecar: widget.sidecar,
          playlist: pl,
          likes: widget.likes,
        );
      case _View.artist:
        final a = _artista;
        if (a == null) return const SizedBox.shrink();
        return ArtistScreen(
          key: ValueKey(a.id),
          api: widget.api,
          player: widget.player,
          likes: widget.likes,
          artist: a,
        );
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.playlists,
    required this.carpetas,
    required this.carpetasPlegadas,
    required this.scroll,
    required this.loading,
    required this.error,
    required this.view,
    required this.selected,
    required this.expanded,
    required this.playingContextUri,
    required this.onToggleExpanded,
    required this.onToggleCarpeta,
    required this.onSelectView,
    required this.onSelectPlaylist,
    required this.onLogout,
    required this.onCreatePlaylist,
    required this.onCreateCarpeta,
    required this.onDeletePlaylist,
    required this.onRenombrarCarpeta,
    required this.onBorrarCarpeta,
    required this.onMoverPlaylist,
    required this.ram,
    required this.settings,
    required this.updater,
    required this.onSalirParaActualizar,
    required this.onReiniciarAudio,
    required this.ytAuth,
    required this.sinPremium,
  });

  final List<Playlist> playlists;
  final List<Carpeta> carpetas;
  final Set<String> carpetasPlegadas;
  final ScrollController scroll;
  final bool loading;
  final String? error;
  final _View view;
  final Playlist? selected;
  final bool expanded;
  final String? playingContextUri;
  final VoidCallback onToggleExpanded;
  final void Function(String carpetaId) onToggleCarpeta;
  final void Function(_View) onSelectView;
  final void Function(Playlist) onSelectPlaylist;
  final Future<void> Function() onLogout;
  final Future<void> Function() onCreatePlaylist;
  final Future<void> Function() onCreateCarpeta;
  final Future<void> Function(Playlist) onDeletePlaylist;
  final Future<void> Function(Carpeta) onRenombrarCarpeta;
  final Future<void> Function(Carpeta) onBorrarCarpeta;
  final Future<void> Function(Playlist) onMoverPlaylist;
  final ResourceMonitor ram;
  final Settings settings;
  final Updater updater;
  final Future<void> Function() onSalirParaActualizar;
  final Future<void> Function() onReiniciarAudio;
  final YtAuth ytAuth;

  final bool sinPremium;

  Playlist? get _playing {
    final uri = playingContextUri;
    if (uri == null) return null;
    for (final pl in playlists) {
      if (pl.uri == uri) return pl;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = _playing;

    return SizedBox(
      width: 244,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'NeoFy',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _NavTile(
            icon: Icons.home,
            label: 'Inicio',
            selected: view == _View.home,
            onTap: () => onSelectView(_View.home),
          ),
          _NavTile(
            icon: Icons.search,
            label: 'Buscar',
            selected: view == _View.search,
            onTap: () => onSelectView(_View.search),
          ),
          _NavTile(
            icon: Icons.favorite,
            label: 'Canciones que te gustan',
            selected: view == _View.liked,
            onTap: () => onSelectView(_View.liked),
          ),
          _NavTile(
            icon: Icons.queue_music,
            label: 'Cola',
            selected: view == _View.queue,
            onTap: () => onSelectView(_View.queue),
          ),
          const Divider(height: 16),
          _SectionHeader(
            label: 'TUS PLAYLISTS',
            expanded: expanded,
            onTap: onToggleExpanded,
            onCreatePlaylist: onCreatePlaylist,
            onCreateCarpeta: onCreateCarpeta,
          ),
          if (expanded)
            Expanded(
              child: error != null && playlists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    )
                  : _listaDePlaylists(context),
            )
          else ...[
            if (playing != null)
              _PlaylistTile(
                playlist: playing,
                selected: view == _View.playlist && selected?.id == playing.id,
                playing: true,
                hayCarpetas: carpetas.isNotEmpty,
                onTap: () => onSelectPlaylist(playing),
                onDelete: () => onDeletePlaylist(playing),
                onMover: () => onMoverPlaylist(playing),
              ),
            const Spacer(),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => unawaited(
                      mostrarAjustes(
                        context,
                        monitor: ram,
                        settings: settings,
                        updater: updater,
                        onSalirParaActualizar: onSalirParaActualizar,
                        bloquesExtra: [
                          if (sinPremium) ConectarYouTubeMusic(auth: ytAuth),
                          ReiniciarAudioDeNeoFy(onReiniciar: onReiniciarAudio),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Ajustes'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Salir'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  ListView _listaDePlaylists(BuildContext context) {
    final porId = {for (final pl in playlists) pl.id: pl};
    final enCarpeta = <String>{
      for (final c in carpetas) ...c.playlistIds,
    };
    final entradas = <_EntradaSidebar>[];
    for (final c in carpetas) {
      var cargadas = 0;
      for (final plId in c.playlistIds) {
        if (porId.containsKey(plId)) cargadas++;
      }
      entradas.add(_EntradaCarpeta(c, cargadas: cargadas));
      if (!carpetasPlegadas.contains(c.id)) {
        for (final plId in c.playlistIds) {
          final pl = porId[plId];
          if (pl != null) entradas.add(_EntradaPlaylist(pl, indentada: true));
        }
      }
    }
    for (final pl in playlists) {
      if (!enCarpeta.contains(pl.id)) {
        entradas.add(_EntradaPlaylist(pl));
      }
    }
    return ListView.builder(
      controller: scroll,
      itemCount: entradas.length + (loading ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= entradas.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return switch (entradas[i]) {
          _EntradaCarpeta(:final carpeta, cargadas: final cargadas) => _CarpetaTile(
              carpeta: carpeta,
              cargadas: cargadas,
              plegada: carpetasPlegadas.contains(carpeta.id),
              onTap: () => onToggleCarpeta(carpeta.id),
              onRenombrar: () => onRenombrarCarpeta(carpeta),
              onBorrar: () => onBorrarCarpeta(carpeta),
            ),
          _EntradaPlaylist(:final playlist, indentada: final indentada) =>
            _PlaylistTile(
              playlist: playlist,
              selected: view == _View.playlist && selected?.id == playlist.id,
              playing: playlist.uri == playingContextUri,
              hayCarpetas: carpetas.isNotEmpty,
              indentada: indentada,
              onTap: () => onSelectPlaylist(playlist),
              onDelete: () => onDeletePlaylist(playlist),
              onMover: () => onMoverPlaylist(playlist),
            ),
        };
      },
    );
  }
}

sealed class _EntradaSidebar {}

class _EntradaCarpeta extends _EntradaSidebar {
  _EntradaCarpeta(this.carpeta, {required this.cargadas});
  final Carpeta carpeta;

  final int cargadas;
}

class _EntradaPlaylist extends _EntradaSidebar {
  _EntradaPlaylist(this.playlist, {this.indentada = false});
  final Playlist playlist;

  final bool indentada;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.expanded,
    required this.onTap,
    required this.onCreatePlaylist,
    required this.onCreateCarpeta,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;
  final Future<void> Function() onCreatePlaylist;
  final Future<void> Function() onCreateCarpeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Nueva playlist o carpeta',
              icon: Icon(Icons.add, size: 18, color: theme.colorScheme.onSurfaceVariant),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'playlist') {
                  unawaited(onCreatePlaylist());
                } else {
                  unawaited(onCreateCarpeta());
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'playlist',
                  child: Text('Nueva playlist'),
                ),
                PopupMenuItem(
                  value: 'carpeta',
                  child: Text('Nueva carpeta'),
                ),
              ],
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.selected,
    required this.playing,
    required this.onTap,
    required this.onDelete,
    required this.onMover,
    this.hayCarpetas = false,
    this.indentada = false,
  });

  final Playlist playlist;
  final bool selected;
  final bool playing;
  final bool hayCarpetas;
  final bool indentada;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = ListTile(
      dense: true,
      selected: selected,
      leading: ArtImage(url: playlist.art, size: 32),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: playing
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: Text('${playlist.trackCount} canciones',
          style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playing)
            Icon(Icons.volume_up, size: 16, color: theme.colorScheme.primary),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 16),
            tooltip: 'Opciones',
            onSelected: (v) {
              if (v == 'mover') {
                onMover();
              } else {
                onDelete();
              }
            },
            itemBuilder: (context) => [
              if (hayCarpetas)
                const PopupMenuItem(
                  value: 'mover',
                  child: Text('Mover a carpeta...'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Quitar de tu biblioteca'),
              ),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
    if (!indentada) return tile;
    return Padding(padding: const EdgeInsets.only(left: 20), child: tile);
  }
}

class _CarpetaTile extends StatelessWidget {
  const _CarpetaTile({
    required this.carpeta,
    required this.cargadas,
    required this.plegada,
    required this.onTap,
    required this.onRenombrar,
    required this.onBorrar,
  });

  final Carpeta carpeta;

  final int cargadas;
  final bool plegada;
  final VoidCallback onTap;
  final VoidCallback onRenombrar;
  final VoidCallback onBorrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = carpeta.playlistIds.length;
    return ListTile(
      dense: true,
      selected: false,
      leading: Icon(
        plegada ? Icons.folder : Icons.folder_open,
        size: 20,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        carpeta.nombre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        cargadas == total
            ? '$total playlists'
            : '$cargadas de $total playlists',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            plegada ? Icons.expand_more : Icons.expand_less,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 16),
            tooltip: 'Opciones',
            onSelected: (v) {
              if (v == 'renombrar') {
                onRenombrar();
              } else {
                onBorrar();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'renombrar',
                child: Text('Renombrar'),
              ),
              PopupMenuItem(
                value: 'borrar',
                child: Text('Eliminar carpeta'),
              ),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      leading: Icon(icon, size: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
