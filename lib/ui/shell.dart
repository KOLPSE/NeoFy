import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth.dart';
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
import 'art_image.dart';
import 'artist_screen.dart';
import 'home_screen.dart';
import 'liked_screen.dart';
import 'now_playing_bar.dart';
import 'settings_dialog.dart';
import 'playlist_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';

enum _View { home, search, queue, liked, playlist, artist }

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
    required this.ram,
    required this.settings,
    required this.updater,
    required this.onSalirParaActualizar,
    required this.onReiniciarAudio,
    required this.onLogout,
    required this.onReauth,
  });

  final SpotifyApi api;
  final SpotifyAuth auth;
  final PlayerController player;
  final LikedStore likes;
  final HomeStore home;
  final ResourceMonitor ram;
  final Settings settings;
  final Updater updater;

  /// Cerrar NeoFy para que el instalador pueda sobrescribir el ejecutable.
  final Future<void> Function() onSalirParaActualizar;

  /// Reabre la salida de audio sin cerrar la app. Ver `_reiniciarAudio` en
  /// `main.dart`.
  final Future<void> Function() onReiniciarAudio;
  final LibrespotManager librespot;
  final MetadataSidecar sidecar;
  final Future<void> Function() onLogout;
  final Future<void> Function() onReauth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scroll = ScrollController();
  final List<Playlist> _playlists = [];

  _View _view = _View.home;
  Playlist? _selected;

  /// El artista abierto desde la portada. No hay entrada en el panel lateral
  /// para esto: se llega pulsando su foto y se sale volviendo a Inicio.
  Artist? _artista;
  bool _loading = false;
  bool _hasMore = true;
  bool _playlistsExpanded = true;
  String? _error;

  /// Offset en elementos **crudos**, no en los que sobreviven al filtro.
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

  /// Las playlists se traen de 50 en 50 conforme se hace scroll, no todas de
  /// golpe: una cuenta con cientos de listas no tiene por qué caber en memoria.
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

  /// Crea una playlist y te lleva a ella.
  Future<void> _crearPlaylist() async {
    final nombre = await _pedirNombre(context);
    if (nombre == null || nombre.trim().isEmpty) return;
    try {
      final pl = await widget.api.createPlaylist(nombre.trim());
      if (!mounted) return;
      setState(() {
        // Arriba del todo: Spotify devuelve las playlists por fecha de adición
        // y la recién creada es la más reciente.
        _playlists.insert(0, pl);
        // El offset avanza también: si no, la siguiente página repetiría una.
        _offset++;
        _view = _View.playlist;
        _selected = pl;
      });
    } catch (e) {
      _avisar('No se pudo crear: $e');
    }
  }

  /// Quita una playlist de tu biblioteca.
  ///
  /// En Spotify no existe "borrar": es dejar de seguirla. Para las tuyas el
  /// efecto es el mismo, y por eso se avisa antes.
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
        // Si estabas dentro de la que acabas de quitar, no puedes quedarte ahí.
        if (_selected?.id == pl.id) {
          _selected = null;
          _view = _View.home;
        }
      });
    } catch (e) {
      _avisar('No se pudo quitar: $e');
    }
  }

  Future<String?> _pedirNombre(BuildContext context) {
    final controlador = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva playlist'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Mi playlist',
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
            child: const Text('Crear'),
          ),
        ],
      ),
    ).whenComplete(() {
      // Cuerpo con llaves a propósito: `whenComplete` espera al futuro que le
      // devuelva el callback, y aquí no debe devolver ninguno.
      controlador.dispose();
    });
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
    );
  }

  /// ¿Está el usuario escribiendo?
  ///
  /// En escritorio, una tecla llega **por dos vías a la vez**: como evento de
  /// teclado al árbol de foco y como texto al campo por el canal de entrada del
  /// motor. Sin esta comprobación, escribir un espacio en el buscador metería
  /// el espacio *y además* pausaría la música.
  static bool get _escribiendo {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _alPulsarTecla(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Las teclas multimedia se registran además a nivel de sistema en el runner
    // de C++ para que funcionen con la app de fondo; esto cubre el caso de
    // tenerla delante, que es el que llega por el árbol de foco.
    switch (event.logicalKey) {
      case LogicalKeyboardKey.mediaPlayPause:
        unawaited(widget.player.togglePlay());
      case LogicalKeyboardKey.mediaTrackNext:
        unawaited(widget.player.next());
      case LogicalKeyboardKey.mediaTrackPrevious:
        unawaited(widget.player.previous());
      case LogicalKeyboardKey.space:
        if (_escribiendo) return KeyEventResult.ignored;
        unawaited(widget.player.togglePlay());
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _alPulsarTecla,
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // El panel se repinta con el estado del reproductor porque
                // necesita saber qué playlist suena para dejarla a la vista
                // cuando la sección está plegada.
                AnimatedBuilder(
                  animation: widget.player,
                  builder: (context, _) => _Sidebar(
                    playlists: _playlists,
                    scroll: _scroll,
                    loading: _loading,
                    error: _error,
                    view: _view,
                    selected: _selected,
                    expanded: _playlistsExpanded,
                    playingContextUri: widget.player.state.contextUri,
                    onToggleExpanded: () =>
                        setState(() => _playlistsExpanded = !_playlistsExpanded),
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
                    onDeletePlaylist: _borrarPlaylist,
                    ram: widget.ram,
                    settings: widget.settings,
                    updater: widget.updater,
                    onSalirParaActualizar: widget.onSalirParaActualizar,
                    onReiniciarAudio: widget.onReiniciarAudio,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _content()),
              ],
            ),
          ),
          const Divider(height: 1),
          NowPlayingBar(player: widget.player, librespot: widget.librespot),
        ],
      ),
    );
  }

  /// Se construye solo la vista activa en vez de un IndexedStack: mantener las
  /// cuatro vivas a la vez significaría mantener vivas sus listas y sus imágenes.
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
          // La clave obliga a reconstruir el State al cambiar de artista: sin
          // ella, abrir otro dejaría la lista del anterior en pantalla.
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
    required this.scroll,
    required this.loading,
    required this.error,
    required this.view,
    required this.selected,
    required this.expanded,
    required this.playingContextUri,
    required this.onToggleExpanded,
    required this.onSelectView,
    required this.onSelectPlaylist,
    required this.onLogout,
    required this.onCreatePlaylist,
    required this.onDeletePlaylist,
    required this.ram,
    required this.settings,
    required this.updater,
    required this.onSalirParaActualizar,
    required this.onReiniciarAudio,
  });

  final List<Playlist> playlists;
  final ScrollController scroll;
  final bool loading;
  final String? error;
  final _View view;
  final Playlist? selected;
  final bool expanded;
  final String? playingContextUri;
  final VoidCallback onToggleExpanded;
  final void Function(_View) onSelectView;
  final void Function(Playlist) onSelectPlaylist;
  final Future<void> Function() onLogout;
  final Future<void> Function() onCreatePlaylist;
  final Future<void> Function(Playlist) onDeletePlaylist;
  final ResourceMonitor ram;
  final Settings settings;
  final Updater updater;
  final Future<void> Function() onSalirParaActualizar;
  final Future<void> Function() onReiniciarAudio;

  /// La playlist que está sonando, si es una de las del panel. Es la que se
  /// deja a la vista cuando la sección está plegada.
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('NeoFy',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
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
            onCreate: onCreatePlaylist,
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
                  : ListView.builder(
                      controller: scroll,
                      // +1 para el indicador de "cargando más" al final.
                      itemCount: playlists.length + (loading ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= playlists.length) {
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
                        final pl = playlists[i];
                        return _PlaylistTile(
                          playlist: pl,
                          selected: view == _View.playlist && selected?.id == pl.id,
                          playing: pl.uri == playingContextUri,
                          onTap: () => onSelectPlaylist(pl),
                          onDelete: () => onDeletePlaylist(pl),
                        );
                      },
                    ),
            )
          else ...[
            // Plegada, pero la que suena se queda siempre a la vista: es el
            // único motivo por el que plegar no te hace perder el hilo.
            if (playing != null)
              _PlaylistTile(
                playlist: playing,
                selected: view == _View.playlist && selected?.id == playing.id,
                playing: true,
                onTap: () => onSelectPlaylist(playing),
                onDelete: () => onDeletePlaylist(playing),
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
                        onReiniciarAudio: onReiniciarAudio,
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.expanded,
    required this.onTap,
    required this.onCreate,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;
  final Future<void> Function() onCreate;

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
            // El "+" va fuera del InkWell de la cabecera: pulsarlo no debe
            // plegar la sección de paso.
            IconButton(
              tooltip: 'Nueva playlist',
              icon: const Icon(Icons.add, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () => unawaited(onCreate()),
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
  });

  final Playlist playlist;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
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
            onSelected: (_) => onDelete(),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('Quitar de tu biblioteca'),
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
