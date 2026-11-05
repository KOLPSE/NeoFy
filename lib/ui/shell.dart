import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/auth.dart';
import '../core/carpetas_store.dart';
import '../core/followed_playlists_store.dart';
import '../core/home_store.dart';
import '../core/librespot.dart';
import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/resource_monitor.dart';
import '../core/settings.dart';
import '../core/tema_store.dart';
import '../core/temas.dart';
import '../core/updater.dart';
import '../core/spotify_api.dart';
import '../core/yt_auth.dart';
import 'album_screen.dart';
import 'art_image.dart';
import 'conectar_youtube.dart';
import 'cristal.dart';
import 'desplegable_en_sitio.dart';
import 'movimiento.dart';
import 'artist_screen.dart';
import 'home_screen.dart';
import 'liked_screen.dart';
import 'now_playing_bar.dart';
import 'idioma_dialog.dart';
import 'settings_dialog.dart';
import 'temas_dialog.dart';
import 'playlist_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';
import 'texto_traducido.dart';

enum _View { home, search, queue, liked, playlist, artist, album }

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
    required this.followed,
    required this.favoritos,
    required this.home,
    required this.carpetas,
    required this.ram,
    required this.settings,
    required this.temas,
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
  final FollowedPlaylistsStore followed;
  final ArtistasFavoritosStore favoritos;
  final HomeStore home;
  final CarpetasStore carpetas;
  final ResourceMonitor ram;
  final Settings settings;
  final TemaStore temas;
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
  Album? _album;
  Artist? _artistaOrigenAlbum;
  bool _loading = false;
  bool _hasMore = true;
  bool _playlistsExpanded = true;
  bool _artistasExpanded = true;
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
      widget.followed.seedFollowed(page.items.map((p) => p.id));
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

  void _alCambiarSeguimiento(Playlist pl, bool ahoraSeguida) {
    setState(() {
      if (ahoraSeguida) {
        if (!_playlists.any((p) => p.id == pl.id)) {
          _playlists.insert(0, pl);
          _offset++;
        }
      } else {
        _playlists.removeWhere((p) => p.id == pl.id);
        if (_offset > 0) _offset--;
        if (_selected?.id == pl.id) {
          _selected = null;
          _view = _View.home;
        }
      }
    });
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
    return showDialogTraducido<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: T(titulo),
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
            child: T('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controlador.text),
            child: T(boton),
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
    _carpetasPlegadas.remove(carpeta.id);
    await widget.carpetas.borrarCarpeta(carpeta.id);
  }

  Future<void> _moverPlaylist(Playlist pl) async {
    const fuera = '__fuera__';
    final elegida = await showDialogTraducido<String>(
      context: context,
      builder: (context) {
        final carpetas = widget.carpetas.carpetas;
        final actual = widget.carpetas.carpetaDe(pl.id);
        return SimpleDialog(
          title: T('Mover a carpeta'),
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
                  const Expanded(child: T('Fuera de cualquier carpeta')),
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
    unawaited(() async {
      final t = await traducirTexto(context, mensaje);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), duration: const Duration(seconds: 3)),
      );
    }());
  }

  @override
  Widget build(BuildContext context) {
    _revisarSiCargarMas();
    return _scaffold(context);
  }

  Widget _scaffold(BuildContext context) {
    final hayCristal = EstiloNeoFy.de(context).hayCristal;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _panelLateral(
                  hayCristal,
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      widget.carpetas,
                      widget.favoritos,
                      widget.settings,
                    ]),
                    builder: (context, _) => _EscuchaReproductor(
                      player: widget.player,
                      builder: (context, playingContextUri, sinPremium) =>
                          _Sidebar(
                        playlists: _playlists,
                        carpetas: widget.carpetas.carpetas,
                        carpetasPlegadas: _carpetasPlegadas,
                        scroll: _scroll,
                        loading: _loading,
                        error: _error,
                        view: _view,
                        selected: _selected,
                        expanded: _playlistsExpanded,
                        artistasFavoritos: widget.favoritos.artistas,
                        artistasExpanded: _artistasExpanded,
                        artistaSeleccionado:
                            _view == _View.artist ? _artista : null,
                        playingContextUri: playingContextUri,
                        player: widget.player,
                        plegado: widget.settings.sidebarPlegado,
                        onTogglePlegado: () => unawaited(widget.settings
                            .setSidebarPlegado(
                                !widget.settings.sidebarPlegado)),
                        onToggleExpanded: () => setState(
                            () => _playlistsExpanded = !_playlistsExpanded),
                        onToggleArtistas: () => setState(
                            () => _artistasExpanded = !_artistasExpanded),
                        onSelectArtista: _abrirArtista,
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
                        temas: widget.temas,
                        updater: widget.updater,
                        onSalirParaActualizar: widget.onSalirParaActualizar,
                        onReiniciarAudio: widget.onReiniciarAudio,
                        ytAuth: widget.ytAuth,
                        sinPremium: sinPremium,
                      ),
                    ),
                  ),
                ),
                if (!hayCristal) const VerticalDivider(width: 1),
                Expanded(child: _content()),
              ],
            ),
          ),
          if (!hayCristal) const Divider(height: 1),
          _panelInferior(
            hayCristal,
            NowPlayingBar(
              player: widget.player,
              librespot: widget.librespot,
              likes: widget.likes,
              home: widget.home,
              onAbrirArtista: _abrirArtista,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelLateral(bool hayCristal, Widget hijo) {
    // Altura infinita (acotada por el Row con stretch): el Column del
    // sidebar reparte el hueco y Ajustes/Salir quedan pegados al now playing.
    // No usar SizedBox.expand: el Row no es flex y el panel se comería el
    // contenido. El ancho lo pone el cajón (244 / 72). El cristal va
    // *dentro* del cajón, a 244 fijos, para no recrear el BackdropFilter
    // en cada fotograma del pliegue.
    final lleno = SizedBox(height: double.infinity, child: hijo);
    if (hayCristal) return lleno;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: lleno,
    );
  }

  Widget _panelInferior(bool hayCristal, Widget hijo) {
    if (!hayCristal) return hijo;
    return PanelDeCristal(
      margen: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: hijo,
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
              onAbrirArtista: _abrirArtista,
        );
      case _View.search:
        return SearchScreen(
          api: widget.api,
          player: widget.player,
          playlists: _playlists,
          likes: widget.likes,
          followed: widget.followed,
          favoritos: widget.favoritos,
          sidecar: widget.sidecar,
          localeEfectivo: widget.settings.localeEfectivo,
          onAbrirPlaylist: (pl) => setState(() {
            _view = _View.playlist;
            _selected = pl;
          }),
          onAbrirArtista: _abrirArtista,
          onCambioSeguimiento: _alCambiarSeguimiento,
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
          followed: widget.followed,
          onCambioSeguimiento: _alCambiarSeguimiento,
        );
      case _View.artist:
        final a = _artista;
        if (a == null) return const SizedBox.shrink();
        return ArtistScreen(
          key: ValueKey(a.id),
          api: widget.api,
          player: widget.player,
          likes: widget.likes,
          favoritos: widget.favoritos,
          artist: a,
          sidecar: widget.sidecar,
          onAbrirAlbum: (a) => _abrirAlbum(a, desdeArtista: _artista),
          onAbrirPlaylist: (pl) => setState(() {
            _view = _View.playlist;
            _selected = pl;
          }),
          onAbrirArtista: _abrirArtista,
        );
      case _View.album:
        final disco = _album;
        if (disco == null) return const SizedBox.shrink();
        return AlbumScreen(
          key: ValueKey(disco.id),
          api: widget.api,
          player: widget.player,
          likes: widget.likes,
          favoritos: widget.favoritos,
          album: disco,
          sidecar: widget.sidecar,
          artistaOrigen: _artistaOrigenAlbum,
          onAbrirArtista: _abrirArtista,
        );
    }
  }

  void _abrirArtista(Artist a) {
    setState(() {
      _artista = a;
      _artistaOrigenAlbum = null;
      _view = _View.artist;
    });
  }

  void _abrirAlbum(Album a, {Artist? desdeArtista}) {
    setState(() {
      _album = a;
      _artistaOrigenAlbum = desdeArtista;
      _view = _View.album;
    });
  }
}

/// Cajón que anima el ancho entre expandido y rail.
///
/// Nunca pinta los dos menús a la vez, y el expandido nunca se enseña
/// recortado: partir "NeoFy" / "Inicio" se leía fatal. Al plegar se pasa
/// al rail al instante (columna de 72) y el panel se estrecha a su
/// alrededor. Al desplegar, el rail aguanta hasta que el ancho ya cabe
/// el menú largo. Sin `Opacity` sobre el árbol: ese saveLayer iba a tirones.
class _CajonLateral extends StatefulWidget {
  const _CajonLateral({
    required this.plegado,
    required this.expandido,
    required this.rail,
  });

  final bool plegado;
  final Widget expandido;
  final Widget rail;

  @override
  State<_CajonLateral> createState() => _CajonLateralState();
}

class _CajonLateralState extends State<_CajonLateral>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ancho;
  final _claveRail = GlobalKey();

  static const _margenCristal = EdgeInsets.fromLTRB(10, 10, 0, 10);

  double get _destino =>
      widget.plegado ? _Sidebar.anchoRail : _Sidebar.anchoExpandido;

  @override
  void initState() {
    super.initState();
    _ancho = AnimationController.unbounded(
      vsync: this,
      value: _destino,
    );
  }

  @override
  void didUpdateWidget(_CajonLateral old) {
    super.didUpdateWidget(old);
    if (old.plegado != widget.plegado) {
      _asentar();
      return;
    }
    // Un hot reload a mitad del pliegue dejaba el expandido a 72 px.
    if (!_ancho.isAnimating && (_ancho.value - _destino).abs() > 0.5) {
      _ancho.value = _destino;
    }
  }

  void _asentar() {
    final movimiento = EstiloNeoFy.de(context).movimiento;
    if (!movimiento.seMueve || modoRendimiento.value) {
      _ancho.value = _destino;
      return;
    }
    unawaited(_ancho.animateTo(
      _destino,
      duration: kDuracionDesplegable,
      curve: kCurvaDesplegable,
    ));
  }

  @override
  void dispose() {
    _ancho.dispose();
    super.dispose();
  }

  Widget _railColumna() => SizedBox(
        width: _Sidebar.anchoRail,
        height: double.infinity,
        child: KeyedSubtree(key: _claveRail, child: widget.rail),
      );

  @override
  Widget build(BuildContext context) {
    final cristal = EstiloNeoFy.de(context).hayCristal;
    return AnimatedBuilder(
      animation: _ancho,
      child: widget.expandido,
      builder: (context, expandido) {
        final w = (_ancho.isAnimating ? _ancho.value : _destino)
            .clamp(_Sidebar.anchoRail, _Sidebar.anchoExpandido);
        // Durante toda la animación se ve el rail (iconos, sin texto que
        // partir). El menú largo solo entra ya a 244.
        final pintarRail = widget.plegado || _ancho.isAnimating;
        final hijoExpandido = expandido ?? widget.expandido;

        Widget interior;
        if (pintarRail) {
          interior = Align(
            alignment: Alignment.topLeft,
            child: _railColumna(),
          );
          if (!widget.plegado) {
            interior = Stack(
              fit: StackFit.expand,
              children: [
                interior,
                TickerMode(
                  enabled: false,
                  child: Offstage(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: _Sidebar.anchoExpandido,
                      maxWidth: _Sidebar.anchoExpandido,
                      child: hijoExpandido,
                    ),
                  ),
                ),
              ],
            );
          }
        } else {
          interior = RepaintBoundary(child: hijoExpandido);
        }

        if (!cristal) {
          return SizedBox(
            width: w,
            child: ClipRect(child: interior),
          );
        }

        final anchoCristal = _ancho.isAnimating
            ? _Sidebar.anchoExpandido
            : (pintarRail ? _Sidebar.anchoRail : _Sidebar.anchoExpandido);
        return SizedBox(
          width: _margenCristal.horizontal + w,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: _margenCristal.horizontal + anchoCristal,
              maxWidth: _margenCristal.horizontal + anchoCristal,
              child: PanelDeCristal(
                margen: _margenCristal,
                child: SizedBox(
                  width: anchoCristal,
                  height: double.infinity,
                  child: interior,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// El sondeo del reproductor avisa cada pocos segundos. El sidebar solo
/// necesita el contexto que está sonando y si hay que mostrar YouTube.
class _EscuchaReproductor extends StatefulWidget {
  const _EscuchaReproductor({
    required this.player,
    required this.builder,
  });

  final PlayerController player;
  final Widget Function(
    BuildContext context,
    String? playingContextUri,
    bool sinPremium,
  ) builder;

  @override
  State<_EscuchaReproductor> createState() => _EscuchaReproductorState();
}

class _EscuchaReproductorState extends State<_EscuchaReproductor> {
  String? _uri;
  bool _sinPremium = false;

  @override
  void initState() {
    super.initState();
    _leer();
    widget.player.addListener(_alReproductor);
  }

  @override
  void didUpdateWidget(_EscuchaReproductor old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      old.player.removeListener(_alReproductor);
      widget.player.addListener(_alReproductor);
      _alReproductor();
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_alReproductor);
    super.dispose();
  }

  void _leer() {
    _uri = widget.player.state.contextUri;
    _sinPremium =
        widget.player.premiumChecked && !widget.player.isPremium;
  }

  void _alReproductor() {
    final uri = widget.player.state.contextUri;
    final sin = widget.player.premiumChecked && !widget.player.isPremium;
    if (uri == _uri && sin == _sinPremium) return;
    _uri = uri;
    _sinPremium = sin;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _uri, _sinPremium);
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
    required this.artistasFavoritos,
    required this.artistasExpanded,
    required this.artistaSeleccionado,
    required this.playingContextUri,
    required this.player,
    required this.plegado,
    required this.onTogglePlegado,
    required this.onToggleExpanded,
    required this.onToggleArtistas,
    required this.onSelectArtista,
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
    required this.temas,
    required this.updater,
    required this.onSalirParaActualizar,
    required this.onReiniciarAudio,
    required this.ytAuth,
    required this.sinPremium,
  });

  static const double anchoExpandido = 244;
  static const double anchoRail = 72;

  final List<Playlist> playlists;
  final List<Carpeta> carpetas;
  final Set<String> carpetasPlegadas;
  final ScrollController scroll;
  final bool loading;
  final String? error;
  final _View view;
  final Playlist? selected;
  final bool expanded;
  final List<Artist> artistasFavoritos;
  final bool artistasExpanded;
  final Artist? artistaSeleccionado;
  final String? playingContextUri;
  final PlayerController player;
  final bool plegado;
  final VoidCallback onTogglePlegado;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleArtistas;
  final void Function(Artist) onSelectArtista;
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
  final TemaStore temas;
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
    return _CajonLateral(
      plegado: plegado,
      expandido: _contenidoExpandido(context),
      rail: _contenidoRail(context),
    );
  }

  void _abrirAjustes(BuildContext context) {
    unawaited(mostrarAjustes(
      context,
      monitor: ram,
      settings: settings,
      updater: updater,
      onSalirParaActualizar: onSalirParaActualizar,
      trackUri: player.state.track?.uri,
      bloquesExtra: [
        BotonDeTemas(temas: temas, settings: settings),
        BotonDeIdioma(settings: settings),
        if (sinPremium) ConectarYouTubeMusic(auth: ytAuth),
        ReiniciarAudioDeNeoFy(onReiniciar: onReiniciarAudio),
      ],
    ));
  }

  /// Las playlists en lista plana, en el mismo orden que el panel: primero
  /// las de las carpetas y luego las sueltas. Es lo que ve el rail.
  List<Playlist> _playlistsPlanas() {
    final porId = {for (final pl in playlists) pl.id: pl};
    final enCarpeta = <String>{for (final c in carpetas) ...c.playlistIds};
    return [
      for (final c in carpetas)
        for (final id in c.playlistIds) ?porId[id],
      for (final pl in playlists)
        if (!enCarpeta.contains(pl.id)) pl,
    ];
  }

  Widget _contenidoExpandido(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 8, 8),
          child: Tooltip(
            message: 'Contraer barra lateral',
            child: Pulsable(
              escalaSobre: 1.03,
              escalaPulsada: 0.96,
              child: InkWell(
                onTap: onTogglePlegado,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.graphic_eq,
                          color: theme.colorScheme.primary),
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
        const SizedBox(height: 8),
        // Un único hijo flexible en todo el Column. Antes había dos
        // hermanos flex (artistas y playlists) y el reparto los partía a
        // medias: el de artistas, al ser `loose`, devolvía la mitad que no
        // usaba y ese sobrante no lo recuperaba nadie. Ese era el hueco que
        // dejaba Ajustes y Salir colgando a media altura.
        Expanded(child: _zonaDeListas(context)),
        const SizedBox(height: 4),
        Divider(
          height: 1,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        const SizedBox(height: 4),
        _NavTile(
          icon: Icons.tune,
          label: 'Ajustes',
          selected: false,
          onTap: () => _abrirAjustes(context),
        ),
        _NavTile(
          icon: Icons.logout,
          label: 'Salir',
          selected: false,
          onTap: () => unawaited(onLogout()),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Artistas favoritos y playlists. Los artistas no son flex a propósito:
  /// se les pone un tope y las playlists se quedan con todo lo que sobre,
  /// que es lo que mantiene el pie del panel abajo.
  Widget _zonaDeListas(BuildContext context) {
    final theme = Theme.of(context);
    final playing = _playing;

    return LayoutBuilder(
      builder: (context, cons) {
        final tope = cons.maxHeight.isFinite
            ? math.min(240.0, cons.maxHeight * 0.45)
            : 240.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CabeceraSeccion(
              label: 'TUS ARTISTAS FAVORITOS',
              expanded: artistasExpanded,
              onTap: onToggleArtistas,
            ),
            Plegable(
              abierto: artistasExpanded,
              contenidoAbierto: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: tope),
                child: _ListaArtistasFavoritos(
                  artistas: artistasFavoritos,
                  seleccionado: artistaSeleccionado,
                  onSelect: onSelectArtista,
                ),
              ),
              contenidoCerrado: const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            _SectionHeader(
              label: 'TUS PLAYLISTS',
              expanded: expanded,
              onTap: onToggleExpanded,
              onCreatePlaylist: onCreatePlaylist,
              onCreateCarpeta: onCreateCarpeta,
            ),
            Expanded(
              child: Plegable(
                abierto: expanded,
                contenidoAbierto: error != null && playlists.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(error!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error)),
                      )
                    : _listaDePlaylists(context),
                contenidoCerrado: playing == null
                    ? const SizedBox.shrink()
                    : _PlaylistTile(
                        playlist: playing,
                        selected: view == _View.playlist &&
                            selected?.id == playing.id,
                        playing: true,
                        hayCarpetas: carpetas.isNotEmpty,
                        onTap: () => onSelectPlaylist(playing),
                        onDelete: () => onDeletePlaylist(playing),
                        onMover: () => onMoverPlaylist(playing),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _contenidoRail(BuildContext context) {
    final theme = Theme.of(context);
    final artistas = artistasFavoritos;
    final listas = _playlistsPlanas();
    final nArt = artistas.length;
    final nPl = listas.length;
    final sepArt = nArt > 0 ? 1 : 0;
    final sepPl = nPl > 0 ? 1 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Center(
          child: Tooltip(
            message: 'Expandir barra lateral',
            child: Pulsable(
              escalaSobre: 1.08,
              escalaPulsada: 0.92,
              child: InkWell(
                onTap: onTogglePlegado,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: anchoRail,
                  height: 44,
                  child: Center(
                    child: Icon(Icons.graphic_eq,
                        color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _IconoRail(
          icon: Icons.home,
          label: 'Inicio',
          selected: view == _View.home,
          onTap: () => onSelectView(_View.home),
        ),
        _IconoRail(
          icon: Icons.search,
          label: 'Buscar',
          selected: view == _View.search,
          onTap: () => onSelectView(_View.search),
        ),
        _IconoRail(
          icon: Icons.favorite,
          label: 'Canciones que te gustan',
          selected: view == _View.liked,
          onTap: () => onSelectView(_View.liked),
        ),
        _IconoRail(
          icon: Icons.queue_music,
          label: 'Cola',
          selected: view == _View.queue,
          onTap: () => onSelectView(_View.queue),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 2),
            addAutomaticKeepAlives: false,
            itemCount: sepArt + nArt + sepPl + nPl,
            itemBuilder: (context, i) {
              var idx = i;
              if (nArt > 0) {
                if (idx == 0) {
                  return const _SeparadorRail(
                    icono: Icons.person_outline,
                    etiqueta: 'Artistas favoritos',
                  );
                }
                idx--;
                if (idx < nArt) {
                  final a = artistas[idx];
                  return _CaratulaRail(
                    key: ValueKey('artista-${a.id}'),
                    url: a.art,
                    nombre: a.name,
                    redonda: true,
                    seleccionada:
                        view == _View.artist && artistaSeleccionado?.id == a.id,
                    sonando: false,
                    onTap: () => onSelectArtista(a),
                  );
                }
                idx -= nArt;
              }
              if (idx == 0 && nPl > 0) {
                return const _SeparadorRail(
                  icono: Icons.playlist_play,
                  etiqueta: 'Playlists',
                );
              }
              if (nPl > 0) idx--;
              final pl = listas[idx];
              return _CaratulaRail(
                key: ValueKey('playlist-${pl.id}'),
                url: pl.art,
                nombre: pl.name,
                redonda: false,
                seleccionada: view == _View.playlist && selected?.id == pl.id,
                sonando: pl.uri == playingContextUri,
                onTap: () => onSelectPlaylist(pl),
              );
            },
          ),
        ),
        _IconoRail(
          icon: Icons.tune,
          label: 'Ajustes',
          selected: false,
          onTap: () => _abrirAjustes(context),
        ),
        _IconoRail(
          icon: Icons.logout,
          label: 'Salir',
          selected: false,
          onTap: () => unawaited(onLogout()),
        ),
        const SizedBox(height: 8),
      ],
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
      addAutomaticKeepAlives: false,
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

/// Marca visual entre bloques del rail: un icono pequeño con tooltip para
/// que, comprimido, se sepa si lo de debajo son artistas o playlists.
class _SeparadorRail extends StatelessWidget {
  const _SeparadorRail({required this.icono, required this.etiqueta});

  final IconData icono;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Tooltip(
        message: etiqueta,
        child: Column(
          children: [
            Divider(
              height: 1,
              thickness: 1,
              indent: 18,
              endIndent: 18,
              color: esquema.outlineVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 6),
            Icon(icono, size: 14, color: esquema.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

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

class _ListaArtistasFavoritos extends StatefulWidget {
  const _ListaArtistasFavoritos({
    required this.artistas,
    required this.seleccionado,
    required this.onSelect,
  });

  final List<Artist> artistas;
  final Artist? seleccionado;
  final void Function(Artist) onSelect;

  @override
  State<_ListaArtistasFavoritos> createState() =>
      _ListaArtistasFavoritosState();
}

class _ListaArtistasFavoritosState extends State<_ListaArtistasFavoritos> {
  final Set<String> _yaVistos = {};
  var _primeraPasada = true;

  @override
  void initState() {
    super.initState();
    _yaVistos.addAll(widget.artistas.map((a) => a.id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _primeraPasada = false;
    });
  }

  @override
  void didUpdateWidget(covariant _ListaArtistasFavoritos old) {
    super.didUpdateWidget(old);
    final vivos = {for (final a in widget.artistas) a.id};
    _yaVistos.removeWhere((id) => !vivos.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.artistas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: T(
          'Tus artistas favoritos se guardan aquí.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final filas = widget.artistas;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _yaVistos.addAll(widget.artistas.map((a) => a.id));
    });

    final mueve =
        EstiloNeoFy.de(context).movimiento.seMueve && !modoRendimiento.value;
    return LayoutBuilder(
      builder: (context, cons) {
        const altoFila = 48.0;
        final tope = cons.maxHeight.isFinite ? cons.maxHeight : 240.0;
        final alto = math.min(filas.length * altoFila, tope);
        return AnimatedSize(
          duration: mueve ? kDuracionDesplegable : Duration.zero,
          curve: kCurvaDesplegable,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: alto,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: altoFila,
              addAutomaticKeepAlives: false,
              itemCount: filas.length,
              itemBuilder: (context, i) {
                final a = filas[i];
                return EntradaDeLista(
                  key: ValueKey(a.id),
                  animar: !_primeraPasada && !_yaVistos.contains(a.id),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    selected: widget.seleccionado?.id == a.id,
                    leading: ArtImage(url: a.art, size: 28, radius: 14),
                    title: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => widget.onSelect(a),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _CabeceraSeccion extends StatelessWidget {
  const _CabeceraSeccion({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

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
              child: T(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            GiroConMuelle(
              abierto: expanded,
              child: Icon(
                Icons.expand_less,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    return DesplegableEnSitio(
      icono: Icons.add,
      tooltip: 'Nueva playlist o carpeta',
      colorIcono: theme.colorScheme.onSurfaceVariant,
      paddingOpciones: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      opciones: [
        OpcionEnSitio(
          icono: Icons.playlist_add,
          texto: 'Nueva playlist',
          onTap: () => unawaited(onCreatePlaylist()),
        ),
        OpcionEnSitio(
          icono: Icons.create_new_folder_outlined,
          texto: 'Nueva carpeta',
          onTap: () => unawaited(onCreateCarpeta()),
        ),
      ],
      constructor: (context, disparador) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: T(label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              disparador,
              GiroConMuelle(
                abierto: expanded,
                child: Icon(
                  Icons.expand_less,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
    final tile = DesplegableEnSitio(
      opciones: [
        if (hayCarpetas)
          OpcionEnSitio(
            icono: Icons.drive_file_move_outlined,
            texto: 'Mover a carpeta...',
            onTap: onMover,
          ),
        OpcionEnSitio(
          icono: Icons.remove_circle_outline,
          texto: 'Quitar de tu biblioteca',
          onTap: onDelete,
          destructiva: true,
          confirmacion: '¿Quitar «${playlist.name}» de tu biblioteca?',
          textoConfirmar: 'Quitar',
        ),
      ],
      constructor: (context, disparador) => ListTile(
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
        subtitle: T('${playlist.trackCount} canciones',
            style: theme.textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (playing)
              Icon(Icons.volume_up, size: 16, color: theme.colorScheme.primary),
            disparador,
          ],
        ),
        onTap: onTap,
      ),
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
    return DesplegableEnSitio(
      opciones: [
        OpcionEnSitio(
          icono: Icons.edit_outlined,
          texto: 'Renombrar',
          onTap: onRenombrar,
        ),
        OpcionEnSitio(
          icono: Icons.delete_outline,
          texto: 'Eliminar carpeta',
          onTap: onBorrar,
          destructiva: true,
          confirmacion:
              '«${carpeta.nombre}» desaparece, pero sus playlists vuelven a la lista.',
          textoConfirmar: 'Eliminar',
        ),
      ],
      constructor: (context, disparador) => ListTile(
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
        subtitle: T(
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
            disparador,
          ],
        ),
        onTap: onTap,
      ),
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
    if (!EstiloNeoFy.de(context).navegacionEnPildora) {
      return ListTile(
        dense: true,
        selected: selected,
        leading: Icon(icon, size: 20),
        title: T(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      );
    }

    final esquema = Theme.of(context).colorScheme;
    final tinta =
        selected ? esquema.onSecondaryContainer : esquema.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Pulsable(
        escalaSobre: 1.015,
        escalaPulsada: 0.97,
        child: PildoraDeNavegacion(
          seleccionado: selected,
          color: esquema.secondaryContainer,
          child: Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: tinta),
                    const SizedBox(width: 12),
                    Expanded(
                      child: T(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: tinta,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Destino del rail plegado: el indicador en píldora de Material 3 con el
/// icono centrado y el nombre en el tooltip.
class _IconoRail extends StatelessWidget {
  const _IconoRail({
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
    final esquema = Theme.of(context).colorScheme;
    final enPildora = EstiloNeoFy.de(context).navegacionEnPildora;
    final tinta = selected
        ? (enPildora ? esquema.onSecondaryContainer : esquema.primary)
        : esquema.onSurfaceVariant;

    final indicador = SizedBox(
      width: 56,
      height: 32,
      child: enPildora
          ? PildoraDeNavegacion(
              seleccionado: selected,
              color: esquema.secondaryContainer,
              child: Center(child: Icon(icon, size: 20, color: tinta)),
            )
          : AnimatedContainer(
              duration: kDuracionDesplegable,
              curve: kCurvaDesplegable,
              decoration: BoxDecoration(
                color: selected
                    ? esquema.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: Icon(icon, size: 20, color: tinta)),
            ),
    );

    return Tooltip(
      message: label,
      child: Pulsable(
        escalaSobre: 1.06,
        escalaPulsada: 0.94,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Center(child: indicador),
          ),
        ),
      ),
    );
  }
}

/// Carátula de artista (redonda) o playlist (cuadrada) en el rail plegado,
/// con la convención de Spotify para distinguirlas de un vistazo.
class _CaratulaRail extends StatelessWidget {
  const _CaratulaRail({
    super.key,
    required this.url,
    required this.nombre,
    required this.redonda,
    required this.seleccionada,
    required this.sonando,
    required this.onTap,
  });

  final String? url;
  final String nombre;
  final bool redonda;
  final bool seleccionada;
  final bool sonando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final estilo = EstiloNeoFy.de(context);

    return Tooltip(
      message: redonda ? 'Artista · $nombre' : 'Playlist · $nombre',
      child: Pulsable(
        escalaSobre: 1.08,
        escalaPulsada: 0.92,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: AnimatedContainer(
                duration: kDuracionDesplegable,
                curve: kCurvaDesplegable,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: seleccionada
                      ? esquema.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                      redonda ? 28 : estilo.radio + 4),
                ),
                child: Stack(
                  children: [
                    ArtImage(
                      url: url,
                      size: 40,
                      radius: redonda ? 20 : estilo.radioDeCaratula(40),
                    ),
                    if (sonando)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: esquema.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.volume_up,
                                size: 12, color: esquema.primary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
