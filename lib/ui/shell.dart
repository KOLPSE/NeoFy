import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_mode.dart';
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
import 'art_image.dart';
import 'artist_screen.dart';
import 'home_screen.dart';
import 'liked_screen.dart';
import 'mode_toggle_text.dart';
import 'now_playing_bar.dart';
import 'settings_dialog.dart';
import 'playlist_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';

enum _View { home, search, queue, liked, playlist, artist }

/// ¿Hace falta pedir la siguiente página de playlists sin esperar a que haya
/// scroll?
///
/// La paginación la dispara `_onScroll`, que solo entra cuando la lista
/// desborda el panel. Con una carpeta plegada la lista puede quedarse en una
/// fila: `maxScrollExtent` es cero, no llega ningún evento y `_loadMore` no
/// volvería a llamarse nunca. Si quedan páginas y el contenido no llena el
/// viewport, la siguiente se pide igualmente justo después de pintar.
///
/// Está separada del widget para poder probarla sin red: es la decisión pura,
/// sin compañeros de `ScrollController` ni de la API.
bool hayQuePedirMas({
  required bool quedanPaginas,
  required bool cargando,
  required bool hayError,
  required bool desborda,
  required bool seccionAbierta,
}) {
  // Nunca: sin páginas no hay nada que pedir; mientras una petición vuela, el
  // aviso siguiente ya está programado (el setState del final re-dispara esta
  // comprobación); y un error no se reintenta en bucle — ya se enseña en el
  // panel, y el scroll o una visita nueva lo volverán a intentar.
  if (!quedanPaginas || cargando || hayError) return false;
  // ⚠️ Con la sección plegada tampoco. No es un detalle: plegada no hay lista,
  // así que no hay scroll y `desborda` es false para siempre — sin esta línea,
  // plegar "TUS PLAYLISTS" se descargaría la biblioteca entera de una tacada,
  // que es justo lo que la paginación existe para no hacer. Al desplegarla, el
  // build siguiente vuelve a preguntar y se retoma donde estaba.
  if (!seccionAbierta) return false;
  // Con scroll, la página siguiente la dispara el desplazamiento: pedirla aquí
  // además rompería el scroll infinito (cargaría de golpe todo lo que queda).
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
    required this.onToggleMode,
    this.onLiberarRam,
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

  /// Cerrar NeoFy para que el instalador pueda sobrescribir el ejecutable.
  final Future<void> Function() onSalirParaActualizar;

  /// Reabre la salida de audio sin cerrar la app. Ver `_reiniciarAudio` en
  /// `main.dart`.
  final Future<void> Function() onReiniciarAudio;
  final LibrespotManager librespot;
  final MetadataSidecar sidecar;
  final Future<void> Function() onLogout;
  final Future<void> Function() onReauth;

  /// Pulsado en el nombre de la app en la barra lateral: dispara el cambio a
  /// NeoTube. Ver `mode_toggle_text.dart` y `mode_host.dart`.
  final VoidCallback onToggleMode;

  /// Se llama a mitad de la animación del botón, con NeoFy todavía en
  /// pantalla: hueco para soltar la caché de imágenes antes de irse a
  /// NeoTube. Ver `ModeToggleText.onSufijoBorrado`.
  final VoidCallback? onLiberarRam;

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

  /// Carpetas del panel ya plegadas por el usuario. Está en el estado en vez de
  /// dentro del sidebar porque la sección entera se puede plegar y desplegar, y
  /// el detalle de cada carpeta tiene que sobrevivir igual a la navegación.
  final Set<String> _carpetasPlegadas = {};

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

  /// Tras pintar, ve si hay que seguir trayendo playlists sin scroll de por
  /// medio (p. ej. con todo lo descargado dentro de una carpeta plegada, la
  /// lista no desborda y `_onScroll` ya no tiene forma de dispararse).
  ///
  /// Se ejecuta después del frame para que el `ScrollController` ya tenga
  /// clientes y dimensiones medibles; desde build, si no, `hasClients` aún es
  /// false y no se sabría si hay o no scroll. Un solo aviso por frame: `_loadMore`
  /// se protege con `_loading`/`_hasMore`, y cada página que llega re-dispara la
  /// comprobación con su setState, así que no hay que encadenar nada a mano.
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
      // La id muerta no debe seguir apuntada en ninguna carpeta: si algún día la
      // vuelves a seguir, no tiene por qué reaparecer ordenada dentro.
      await widget.carpetas.quitarPlaylist(pl.id);
    } catch (e) {
      _avisar('No se pudo quitar: $e');
    }
  }

  /// Pide un nombre para una playlist o una carpeta.
  ///
  /// Las dos comparten el diálogo: es "un nombre y un botón", y duplicarlo solo
  /// serviría para que los dos acabaran por desincronizarse.
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
      // Cuerpo con llaves a propósito: `whenComplete` espera al futuro que le
      // devuelva el callback, y aquí no debe devolver ninguno.
      controlador.dispose();
    });
  }

  /// Crea una carpeta de playlists. Es un cambio local: la Web API de Spotify
  /// no tiene nada parecido (ver `carpetas_store.dart`).
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

  /// Borrar la carpeta no borra las playlists: solo desaparece la estructura y
  /// sus listas vuelven a la sección sueltas. Se pregunta antes porque pierdes
  /// la organización, que no se puede deshacer.
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

  /// Pregunta en qué carpeta dejar una playlist; la última opción la saca de
  /// todas y la deja suelta.
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

  /// El teclado ya no se escucha aquí: lo hace [AtajosDeReproduccion], por
  /// encima de los dos modos.
  ///
  /// ⚠️ Tenerlo en este shell era un fallo con NeoTube delante. `ModeHost`
  /// mantiene los dos shells montados a la vez, así que este `Focus` seguía
  /// recibiendo el espacio con NeoTube en pantalla y pausaba/reanudaba
  /// Spotify. Ver el comentario de `ui/atajos.dart`.
  @override
  Widget build(BuildContext context) {
    // Tras este frame se comprueba si hace falta seguir trayendo playlists sin
    // scroll que lo dispare (ver `_revisarSiCargarMas`). Cada setState recién
    // pintado es la oportunidad: una página que llega, una carpeta que se
    // pliega y encoge la lista, una sección que vuelve a abrirse...
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
                // El panel se repinta con el estado del reproductor (necesita
                // saber qué playlist suena para dejarla a la vista cuando la
                // sección está plegada) y con el del store de carpetas, que es
                // quien avisa cuando cambian la estructura o el orden.
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
                    onToggleMode: widget.onToggleMode,
                    onLiberarRam: widget.onLiberarRam,
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
    required this.onToggleMode,
    this.onLiberarRam,
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
  final VoidCallback onToggleMode;
  final VoidCallback? onLiberarRam;

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
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
            child: ModeToggleText(
              modo: AppMode.neofy,
              onTap: onToggleMode,
              onSufijoBorrado: onLiberarRam,
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
            // Plegada, pero la que suena se queda siempre a la vista: es el
            // único motivo por el que plegar no te hace perder el hilo.
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
                        // Reiniciar la salida es reiniciar librespot: no tiene
                        // equivalente en NeoTube, que reproduce aquí mismo.
                        propiosDelModo: [
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

  /// La lista se aplana a entradas para poder meter las carpetas en el mismo
  /// `ListView.builder` que las playlists sueltas: una vista única, con scroll
  /// compartido y la paginación intacta.
  ///
  /// ⚠️ El orden importa. Una carpeta puede referirse a una playlist que
  /// todavía no se ha descargado (está en una página posterior); cuando llegue,
  /// tiene que salir **dentro de su carpeta**, no duplicada en la lista. Por
  /// eso las playlists que están en alguna carpeta se filtran de la segunda
  /// pasada con `enCarpeta`, independientemente de si la carpeta está plegada.
  ListView _listaDePlaylists(BuildContext context) {
    final porId = {for (final pl in playlists) pl.id: pl};
    final enCarpeta = <String>{
      for (final c in carpetas) ...c.playlistIds,
    };
    final entradas = <_EntradaSidebar>[];
    for (final c in carpetas) {
      // Cuántas de las playlists de la carpeta están ya descargadas: es lo que
      // se verá al desplegarla. Con la paginación por páginas puede haber huecos
      // (una carpeta apunta a ids de páginas que aún no han llegado), y el
      // subtítulo tiene que cuadrar con lo que se enseña, no mentir.
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
      // +1 para el indicador de "cargando más" al final.
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
              // Solo el margen extra: lo que delimita la pertenencia a la
              // carpeta es la indentación, no el relleno del icono.
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

/// Una fila del panel de playlists: o bien una carpeta con sus playlists
/// plegadas debajo, o bien una playlist (suelta, o indentada dentro de una
/// carpeta no plegada).
sealed class _EntradaSidebar {}

class _EntradaCarpeta extends _EntradaSidebar {
  _EntradaCarpeta(this.carpeta, {required this.cargadas});
  final Carpeta carpeta;

  /// Cuántas playlists de la carpeta están ya descargadas. Menos que el total
  /// cuando algunas han quedado en páginas que aún no han llegado.
  final int cargadas;
}

class _EntradaPlaylist extends _EntradaSidebar {
  _EntradaPlaylist(this.playlist, {this.indentada = false});
  final Playlist playlist;

  /// Va dentro de una carpeta (y no plegada), por lo que se indentará.
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
            // El "+" va fuera del InkWell de la cabecera: pulsarlo no debe
            // plegar la sección de paso. Ahora ofrece las dos creaciones.
            // ⚠️ Aquí NO va `color:`. Esto era un IconButton, donde `color` es
            // el color del icono; en un PopupMenuButton es **el fondo del menú
            // desplegable**. Al convertirlo se arrastró la propiedad tal cual y
            // el menú acababa pintado de `onSurfaceVariant` —un color pensado
            // para texto— con las letras en `onSurface` encima: oscuro sobre
            // oscuro, ilegible. Sin `color`, el menú usa la superficie del tema
            // y el texto su contraste, que es lo correcto en claro y en oscuro.
            // El tinte que se quería va en el icono, que es lo que se veía.
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
            // ⚠️ `onSelected` mira el valor de verdad: con dos entradas, un
            // `(_) => onDelete()` borraría la playlist al elegir "mover".
            onSelected: (v) {
              if (v == 'mover') {
                onMover();
              } else {
                onDelete();
              }
            },
            itemBuilder: (context) => [
              // "Mover a carpeta" solo tiene sentido si hay algo que elegir;
              // sin carpetas, no hay ningún sitio al que moverla.
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

  /// Cuántas de las playlists que apunta la carpeta están ya cargadas. El
  /// subtítulo "x de y" existe porque Spotify pagina las playlists de 50 en 50:
  /// una carpeta puede referirse a ids de páginas que todavía no se han pedido,
  /// y enseñar el número de `carpeta.playlistIds` entero sería mentir sobre lo
  /// que se combina al desplegarla. Cuando todo llegue, se queda en "x
  /// playlists" y el "de y" desaparece solo.
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
