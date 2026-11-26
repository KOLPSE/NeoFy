import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/home_store.dart';
import '../core/letras_service.dart';
import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/settings.dart';
import '../core/spotify_api.dart';
import '../core/temas.dart';
import '../core/temporizador_apagado.dart';
import 'art_image.dart';
import 'artist_favorite_button.dart';
import 'like_button.dart';
import 'linea_de_artistas.dart';
import 'queue_screen.dart';
import 'texto_traducido.dart';
import 'titulo_desplazable.dart';

/// Sidebar derecho de Reproducción Actual (y Cola integrada) de NeoFy.
///
/// Soporta 4 estados:
/// - **Plegado**: franja vertical minimalista con `<` que se ensancha un poco al
///   pasar el ratón sin mostrar contenido, y se despliega al hacer clic.
/// - **Compacto** (~312 px): panel derecho desplazable con contexto (`HEAD`),
///   arte de la canción (foto o animado/Canvas), título + compartir + corazón,
///   vista previa de letras desplegable inline, información del artista
///   (verificado, oyentes mensuales, seguir y descripción), créditos (`or/A`),
///   fechas de gira y siguiente canción en la cola.
/// - **Cola**: muestra [QueueScreen] dentro del propio sidebar con retorno rápido.
/// - **Expandido** (`↗↙`): vista ampliada a dos columnas en el área central.
class RightSidebar extends StatefulWidget {
  const RightSidebar({
    super.key,
    required this.api,
    required this.player,
    required this.likes,
    required this.favoritos,
    required this.sidecar,
    required this.letras,
    required this.temporizador,
    required this.playlists,
    required this.plegado,
    required this.expandido,
    required this.mostrarCola,
    required this.contextoTitulo,
    required this.onTogglePlegado,
    required this.onToggleExpandido,
    required this.onAbrirCola,
    required this.onCerrarCola,
    required this.onAbrirLetraCompleta,
    required this.onAbrirArtista,
    required this.onAbrirAlbum,
    this.onAbrirContexto,
    this.home,
    this.anchoCompacto = 312,
  });

  final SpotifyApi api;
  final PlayerController player;
  final LikedStore likes;
  final ArtistasFavoritosStore favoritos;
  final MetadataSidecar sidecar;
  final LetrasService letras;
  final TemporizadorApagado temporizador;
  final List<Playlist> playlists;
  final HomeStore? home;

  final bool plegado;
  final bool expandido;
  final bool mostrarCola;
  final String contextoTitulo;
  final double anchoCompacto;

  final VoidCallback onTogglePlegado;
  final VoidCallback onToggleExpandido;
  final VoidCallback onAbrirCola;
  final VoidCallback onCerrarCola;
  final VoidCallback onAbrirLetraCompleta;
  final void Function(Artist artista) onAbrirArtista;
  final void Function(Album album) onAbrirAlbum;
  final VoidCallback? onAbrirContexto;

  @override
  State<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends State<RightSidebar> {
  String? _trackUriCargada;
  int _revision = 0;

  ResultadoLetra? _letra;
  bool _cargandoLetra = false;
  bool _letraDesplegada = false;

  InfoArtistaExtendida? _infoArtista;
  Artist? _artistaFallback;
  CreditosDePista? _creditos;
  CanvasDePista? _canvas;
  Track? _siguienteEnCola;

  bool _bioExpandida = false;
  bool _giraExpandida = false;
  bool _hoverPlegado = false;

  @override
  void initState() {
    super.initState();
    widget.player.currentUri.addListener(_alCambiarPista);
    widget.player.addListener(_alCambiarEstadoReproductor);
    _cargarTodoParaPistaActual();
  }

  @override
  void didUpdateWidget(covariant RightSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.currentUri.removeListener(_alCambiarPista);
      oldWidget.player.removeListener(_alCambiarEstadoReproductor);
      widget.player.currentUri.addListener(_alCambiarPista);
      widget.player.addListener(_alCambiarEstadoReproductor);
      _cargarTodoParaPistaActual();
    }
  }

  @override
  void dispose() {
    widget.player.currentUri.removeListener(_alCambiarPista);
    widget.player.removeListener(_alCambiarEstadoReproductor);
    super.dispose();
  }

  void _alCambiarEstadoReproductor() {
    final uri = widget.player.state.track?.uri;
    if (uri != _trackUriCargada) {
      _cargarTodoParaPistaActual();
    }
  }

  void _alCambiarPista() {
    _cargarTodoParaPistaActual();
  }

  void _cargarTodoParaPistaActual() {
    final track = widget.player.state.track;
    final uri = track?.uri;
    if (uri == _trackUriCargada && track != null) return;
    _trackUriCargada = uri;
    final rev = ++_revision;

    if (track == null) {
      if (!mounted) return;
      setState(() {
        _letra = null;
        _cargandoLetra = false;
        _infoArtista = null;
        _artistaFallback = null;
        _creditos = null;
        _canvas = null;
        _siguienteEnCola = null;
        _bioExpandida = false;
        _giraExpandida = false;
      });
      return;
    }

    setState(() {
      _letra = null;
      _cargandoLetra = !track.isEpisode;
      _infoArtista = null;
      _artistaFallback = null;
      _creditos = null;
      _canvas = null;
      _siguienteEnCola = null;
      _bioExpandida = false;
      _giraExpandida = false;
    });

    if (!track.isEpisode) {
      unawaited(_cargarLetra(track, rev));
      unawaited(_cargarCreditosYCanvas(track, rev));
    }
    unawaited(_cargarArtista(track, rev));
    unawaited(_cargarSiguienteCola(track, rev));
  }

  Future<void> _cargarLetra(Track track, int rev) async {
    try {
      final res = await widget.letras.obtener(track);
      if (!mounted || rev != _revision) return;
      setState(() {
        _letra = res;
        _cargandoLetra = false;
      });
    } catch (_) {
      if (!mounted || rev != _revision) return;
      setState(() {
        _letra = null;
        _cargandoLetra = false;
      });
    }
  }

  Future<void> _cargarCreditosYCanvas(Track track, int rev) async {
    final id = track.id.isNotEmpty ? track.id : idDeSpotify(track.uri);
    if (id.isEmpty) return;
    if (!widget.sidecar.puedeUsarse) {
      if (!mounted || rev != _revision) return;
      if (track.listaDeArtistas.isNotEmpty) {
        setState(() {
          _creditos = CreditosDePista(
            personas: [
              for (final a in track.listaDeArtistas)
                CreditoPista(
                  nombre: a.name,
                  artistaId: a.id,
                  artistaUri: a.uri,
                  roles: const ['Artista Principal'],
                ),
            ],
          );
        });
      }
      return;
    }

    final resultados = await Future.wait([
      widget.sidecar.creditosDePista(id).catchError((_) => null),
      widget.sidecar.canvasDePista(id).catchError((_) => null),
    ]);
    if (!mounted || rev != _revision) return;
    final creditos = resultados[0] as CreditosDePista?;
    final canvas = resultados[1] as CanvasDePista?;
    setState(() {
      _creditos = (creditos != null && !creditos.estaVacio)
          ? creditos
          : (track.listaDeArtistas.isNotEmpty
                ? CreditosDePista(
                    personas: [
                      for (final a in track.listaDeArtistas)
                        CreditoPista(
                          nombre: a.name,
                          artistaId: a.id,
                          artistaUri: a.uri,
                          roles: const ['Artista Principal'],
                        ),
                    ],
                  )
                : null);
      _canvas = canvas;
    });
  }

  Future<void> _cargarArtista(Track track, int rev) async {
    final principal = track.listaDeArtistas.firstOrNull;
    if (principal == null || principal.id.isEmpty) return;

    InfoArtistaExtendida? insights;
    if (widget.sidecar.puedeUsarse) {
      insights = await widget.sidecar
          .infoArtistaExtendida(principal.id)
          .catchError((_) => null);
    }

    Artist? fallback;
    if (insights == null ||
        insights.imagenBanner == null ||
        insights.biografia == null) {
      try {
        fallback = await widget.api.artist(principal.id);
      } catch (_) {}
    }

    if (!mounted || rev != _revision) return;
    setState(() {
      _infoArtista = insights;
      _artistaFallback = fallback;
    });
  }

  Future<void> _cargarSiguienteCola(Track track, int rev) async {
    try {
      final cola = await widget.api.queue();
      if (!mounted || rev != _revision) return;
      Track? siguiente;
      for (final item in cola) {
        if (item.uri != track.uri) {
          siguiente = item;
          break;
        }
      }
      siguiente ??= cola.length > 1 ? cola[1] : cola.firstOrNull;
      setState(() => _siguienteEnCola = siguiente);
    } catch (_) {
      if (!mounted || rev != _revision) return;
      setState(() => _siguienteEnCola = null);
    }
  }

  void _notificar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)),
    );
  }

  String _enlaceSpotify(Track track) {
    final id = track.id.isNotEmpty ? track.id : idDeSpotify(track.uri);
    final tipo = track.isEpisode ? 'episode' : 'track';
    return 'https://open.spotify.com/$tipo/$id';
  }

  Future<void> _copiarEnlace(Track track, {bool notificar = true}) async {
    await Clipboard.setData(ClipboardData(text: _enlaceSpotify(track)));
    if (notificar) _notificar('Enlace copiado al portapapeles');
  }

  Future<void> _copiarTituloYArtista(Track track) async {
    final texto = track.artists.isEmpty
        ? track.name
        : '${track.name} — ${track.artists}';
    await Clipboard.setData(ClipboardData(text: texto));
    _notificar('Título y artista copiados');
  }

  Future<void> _abrirEnSpotify(Track track) async {
    final uri = Uri.parse(_enlaceSpotify(track));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _notificar('No se pudo abrir en Spotify.');
  }

  Future<void> _anadirAPlaylist(Track track) async {
    if (track.uri.isEmpty) return;
    final editables = widget.playlists;
    if (editables.isEmpty) {
      _notificar('No tienes playlists cargadas para añadir la canción.');
      return;
    }
    final elegida = await showDialogTraducido<Playlist>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const T('Añadir a lista'),
        children: [
          for (final pl in editables)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(pl),
              child: Text(
                pl.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    if (elegida == null || !mounted) return;
    try {
      await widget.api.addToPlaylist(elegida.id, [track.uri]);
      _notificar('Añadida a «${elegida.name}»');
    } catch (e) {
      _notificar('No se pudo añadir a la lista: $e');
    }
  }

  Future<void> _anadirACola(Track track) async {
    if (track.uri.isEmpty) return;
    try {
      await widget.api.addToQueue(track.uri);
      _notificar('Añadida a la cola');
      unawaited(_cargarSiguienteCola(track, _revision));
    } catch (e) {
      _notificar('No se pudo añadir a la cola: $e');
    }
  }

  Future<void> _irARadioDeLaCancion(Track track) async {
    final principal = track.listaDeArtistas.firstOrNull;
    if (principal == null || principal.id.isEmpty) {
      _notificar('No hay suficiente información del artista para crear radio.');
      return;
    }
    try {
      final pistas = <Track>[track];
      final vistas = <String>{track.uri};
      final top = await widget.api.artistTopTracks(principal.id);
      for (final t in top) {
        if (t.uri.isNotEmpty && vistas.add(t.uri)) pistas.add(t);
      }
      final relacionados = await widget.api
          .relatedArtists(principal.id)
          .catchError((_) => const <Artist>[]);
      for (final rel in relacionados.take(3)) {
        final relTop = await widget.api
            .artistTopTracks(rel.id)
            .catchError((_) => const <Track>[]);
        for (final t in relTop.take(3)) {
          if (t.uri.isNotEmpty && vistas.add(t.uri)) pistas.add(t);
        }
      }
      final uris = pistas.map((t) => t.uri).toList();
      if (uris.length <= 1) {
        _notificar('No se encontraron más canciones relacionadas.');
        return;
      }
      await widget.player.playLista(uris);
      _notificar('Reproduciendo radio de «${track.name}»');
    } catch (e) {
      _notificar('No se pudo iniciar la radio: $e');
    }
  }

  Future<void> _irAlAlbum(Track track) async {
    if (track.uri.isEmpty) return;
    try {
      final ctx = await widget.api.contextoDePista(track.uri);
      if (!mounted) return;
      if (ctx == null) {
        _notificar('No se pudo resolver el álbum de esta canción.');
        return;
      }
      final albumId = idDeSpotify(ctx.album);
      widget.onAbrirAlbum(
        Album(
          id: albumId,
          uri: ctx.album,
          name: track.album.isNotEmpty ? track.album : 'Álbum',
          artists: track.artists,
          listaDeArtistas: track.listaDeArtistas,
          art: track.artMedium ?? track.artSmall,
        ),
      );
    } catch (e) {
      _notificar('No se pudo abrir el álbum: $e');
    }
  }

  void _mostrarTodosLosCreditos(Track track, CreditosDePista creditos) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const T('Créditos'),
              Text(
                track.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in creditos.personas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _filaCredito(p, enDialogo: true),
                    ),
                  if (creditos.fuentes.isNotEmpty) ...[
                    const Divider(),
                    Text(
                      'Fuentes: ${creditos.fuentes.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const T('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plegado) {
      return _construirPlegado(context);
    }
    if (widget.expandido) {
      return _construirExpandido(context);
    }
    return _construirCompacto(context);
  }

  Widget _construirPlegado(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final estilo = EstiloNeoFy.de(context);
    final nocturno = estilo.usaInterfazNocturna;
    final sinAnimar =
        MediaQuery.disableAnimationsOf(context) || modoRendimiento.value;
    final ancho = _hoverPlegado ? 38.0 : 24.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverPlegado = true),
      onExit: (_) => setState(() => _hoverPlegado = false),
      child: Tooltip(
        message: 'Mostrar panel de reproducción actual',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTogglePlegado,
          child: AnimatedContainer(
            duration: sinAnimar
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: ancho,
            decoration: BoxDecoration(
              color: _hoverPlegado
                  ? colores.surfaceContainerHigh
                  : (nocturno ? colores.surfaceContainer : colores.surface),
              borderRadius: nocturno
                  ? BorderRadius.circular(estilo.radio)
                  : null,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.chevron_left,
              size: 18,
              color: _hoverPlegado
                  ? colores.onSurface
                  : colores.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirCompacto(BuildContext context) {
    final estilo = EstiloNeoFy.de(context);
    final nocturno = estilo.usaInterfazNocturna;
    final colores = Theme.of(context).colorScheme;

    return SizedBox(
      width: widget.anchoCompacto,
      child: Material(
        color: nocturno
            ? colores.surfaceContainer
            : colores.surfaceContainerLow,
        shape: nocturno
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(estilo.radio),
              )
            : null,
        clipBehavior: nocturno ? Clip.antiAlias : Clip.none,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.player,
            widget.favoritos,
            widget.likes,
            widget.temporizador,
          ]),
          builder: (context, _) {
            if (widget.mostrarCola) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Volver a Reproducción Actual',
                          icon: const Icon(Icons.arrow_back, size: 18),
                          onPressed: widget.onCerrarCola,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: T(
                            'Reproducción Actual',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _botonComprimir(context),
                      ],
                    ),
                  ),
                  Expanded(
                    child: QueueScreen(
                      api: widget.api,
                      player: widget.player,
                      likes: widget.likes,
                      home: widget.home,
                      onClose: widget.onCerrarCola,
                    ),
                  ),
                ],
              );
            }

            final track = widget.player.state.track;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cabecera(context, track, esExpandido: false),
                Expanded(
                  child: track == null
                      ? _sinReproduccion(context)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          children: _tarjetasCuerpo(context, track),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _construirExpandido(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Material(
      color: colores.surfaceContainer,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.player,
          widget.favoritos,
          widget.likes,
          widget.temporizador,
        ]),
        builder: (context, _) {
          final track = widget.player.state.track;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cabecera(context, track, esExpandido: true),
              Expanded(
                child: track == null
                    ? _sinReproduccion(context)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final dosColumnas = constraints.maxWidth >= 720;
                          if (!dosColumnas) {
                            return ListView(
                              padding: const EdgeInsets.all(16),
                              children: _tarjetasCuerpo(context, track),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: (constraints.maxWidth * 0.42).clamp(
                                    260.0,
                                    400.0,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _tarjetaArte(
                                          context,
                                          track,
                                          lado: 340,
                                        ),
                                        const SizedBox(height: 14),
                                        _filaTituloYAcciones(
                                          context,
                                          track,
                                          grande: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: ListView(
                                    children: _tarjetasSecundarias(
                                      context,
                                      track,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _tarjetasCuerpo(BuildContext context, Track track) {
    return [
      _tarjetaArte(context, track, lado: widget.anchoCompacto - 24),
      const SizedBox(height: 12),
      _filaTituloYAcciones(context, track),
      ..._tarjetasSecundarias(context, track),
    ];
  }

  List<Widget> _tarjetasSecundarias(BuildContext context, Track track) {
    final tieneLetras =
        !track.isEpisode &&
        (_cargandoLetra ||
            (_letra != null &&
                (_letra!.instrumental ||
                    _letra!.lineas.isNotEmpty ||
                    _letra!.textoPlano.trim().isNotEmpty)));

    final artistaPrincipal = track.listaDeArtistas.firstOrNull;
    final tieneArtista = artistaPrincipal != null && artistaPrincipal.id.isNotEmpty;
    final creditos = _creditos;
    final conciertos = _infoArtista?.conciertos ?? const <ConciertoArtista>[];
    final siguiente = _siguienteEnCola;

    return [
      if (tieneLetras) ...[
        const SizedBox(height: 14),
        _tarjetaLetra(context, track),
      ],
      if (tieneArtista) ...[
        const SizedBox(height: 14),
        _tarjetaArtista(context, artistaPrincipal),
      ],
      if (creditos != null && !creditos.estaVacio) ...[
        const SizedBox(height: 14),
        _tarjetaCreditos(context, track, creditos),
      ],
      if (conciertos.isNotEmpty) ...[
        const SizedBox(height: 14),
        _tarjetaGira(context, conciertos),
      ],
      if (siguiente != null) ...[
        const SizedBox(height: 14),
        _tarjetaCola(context, siguiente),
      ],
    ];
  }

  Widget _sinReproduccion(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 40,
              color: tema.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            T(
              'Reproduce una canción para ver sus detalles.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecera(
    BuildContext context,
    Track? track, {
    required bool esExpandido,
  }) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final titulo = widget.contextoTitulo.isEmpty
        ? 'Reproduciendo'
        : widget.contextoTitulo;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
          if (!esExpandido) _botonComprimir(context),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onAbrirContexto,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.temporizador.activo) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colores.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 12,
                              color: colores.onPrimaryContainer,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              widget.temporizador.etiquetaRestante,
                              style: tema.textTheme.labelSmall?.copyWith(
                                color: colores.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (track != null) _botonMenuAjustes(context, track),
          IconButton(
            tooltip: esExpandido ? 'Contraer vista' : 'Expandir vista',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              esExpandido
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              size: 18,
              color: colores.onSurfaceVariant,
            ),
            onPressed: widget.onToggleExpandido,
          ),
        ],
      ),
    );
  }

  Widget _botonComprimir(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      tooltip: 'Ocultar panel',
      visualDensity: VisualDensity.compact,
      onPressed: widget.onTogglePlegado,
      icon: CustomPaint(
        size: const Size(18, 16),
        painter: _IconoComprimirDerechaPainter(color: color),
      ),
    );
  }

  Widget _botonMenuAjustes(BuildContext context, Track track) {
    final colores = Theme.of(context).colorScheme;
    final enMeGusta = widget.likes.isSaved(track.uri) ?? false;
    final artistaPrincipal = track.listaDeArtistas.firstOrNull;
    final hayAlbum = track.uri.startsWith('spotify:track:');

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colores.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colores.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        if (!track.isEpisode)
          MenuItemButton(
            leadingIcon: const Icon(Icons.add, size: 18),
            onPressed: () => unawaited(_anadirAPlaylist(track)),
            child: const T('Añadir a lista'),
          ),
        if (!track.isEpisode && track.uri.isNotEmpty)
          MenuItemButton(
            leadingIcon: Icon(
              enMeGusta ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: enMeGusta ? colores.primary : null,
            ),
            onPressed: () => unawaited(widget.likes.toggle(track.uri, pista: track)),
            child: T(
              enMeGusta
                  ? 'Eliminar de Canciones que te gustan'
                  : 'Guardar en Canciones que te gustan',
            ),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.playlist_add, size: 18),
          onPressed: () => unawaited(_anadirACola(track)),
          child: const T('Añadir a la cola'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.timer_outlined, size: 18),
          menuChildren: [
            for (final min in const [5, 10, 15, 30, 45, 60])
              MenuItemButton(
                onPressed: () {
                  widget.temporizador.activarMinutos(min);
                  _notificar('Temporizador fijado en $min min');
                },
                child: Text('$min minutos'),
              ),
            MenuItemButton(
              leadingIcon: widget.temporizador.alFinalDeLaCancion
                  ? const Icon(Icons.check, size: 16)
                  : null,
              onPressed: () {
                widget.temporizador.activarFinDeCancion();
                _notificar('Se pausará al terminar esta canción');
              },
              child: const T('Al final de la canción'),
            ),
            if (widget.temporizador.activo) ...[
              const Divider(height: 8),
              MenuItemButton(
                leadingIcon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  widget.temporizador.cancelar();
                  _notificar('Temporizador desactivado');
                },
                child: const T('Desactivar temporizador'),
              ),
            ],
          ],
          child: Row(
            children: [
              const T('Temporizador de apagado'),
              if (widget.temporizador.activo) ...[
                const SizedBox(width: 8),
                Text(
                  widget.temporizador.etiquetaRestante,
                  style: TextStyle(color: colores.primary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 8),
        if (!track.isEpisode)
          MenuItemButton(
            leadingIcon: const Icon(Icons.radio, size: 18),
            onPressed: () => unawaited(_irARadioDeLaCancion(track)),
            child: const T('Ir a radio de la canción'),
          ),
        if (artistaPrincipal != null && artistaPrincipal.id.isNotEmpty)
          MenuItemButton(
            leadingIcon: const Icon(Icons.person_outline, size: 18),
            onPressed: () => widget.onAbrirArtista(artistaPrincipal.comoArtista),
            child: const T('Ir al artista'),
          ),
        if (hayAlbum)
          MenuItemButton(
            leadingIcon: const Icon(Icons.album_outlined, size: 18),
            onPressed: () => unawaited(_irAlAlbum(track)),
            child: const T('Ir al álbum'),
          ),
        if (_creditos != null && !_creditos!.estaVacio)
          MenuItemButton(
            leadingIcon: const Icon(Icons.groups_outlined, size: 18),
            onPressed: () => _mostrarTodosLosCreditos(track, _creditos!),
            child: const T('Ver créditos'),
          ),
        const Divider(height: 8),
        SubmenuButton(
          leadingIcon: const Icon(Icons.ios_share_rounded, size: 18),
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.link, size: 18),
              onPressed: () => unawaited(_copiarEnlace(track)),
              child: const T('Copiar enlace de Spotify'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.copy, size: 18),
              onPressed: () => unawaited(_copiarTituloYArtista(track)),
              child: const T('Copiar título y artista'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => unawaited(_abrirEnSpotify(track)),
              child: const T('Abrir en Spotify'),
            ),
          ],
          child: const T('Compartir'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Más opciones de reproducción',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.more_horiz, size: 20, color: colores.onSurfaceVariant),
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }

  Widget _tarjetaArte(
    BuildContext context,
    Track track, {
    required double lado,
  }) {
    final animar =
        widget.player.state.isPlaying &&
        !modoRendimiento.value &&
        !MediaQuery.disableAnimationsOf(context);
    final urlCanvas = (_canvas != null && _canvas!.esImagenAnimable)
        ? _canvas!.url
        : null;

    return _ArteAnimadoPista(
      url: urlCanvas ?? track.artMedium ?? track.artSmall,
      urlGrande: urlCanvas ?? track.artMedium ?? track.artSmall,
      lado: lado,
      animar: animar,
      tieneCanvas: _canvas?.tieneCanvas ?? false,
    );
  }

  Widget _filaTituloYAcciones(
    BuildContext context,
    Track track, {
    bool grande = false,
  }) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final estiloTitulo =
        (grande ? tema.textTheme.headlineSmall : tema.textTheme.titleMedium)
            ?.copyWith(fontWeight: FontWeight.w700);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TituloDesplazable(
                texto: track.name,
                estilo: estiloTitulo,
              ),
              const SizedBox(height: 2),
              LineaDeArtistas(
                artistas: track.listaDeArtistas,
                texto: track.artists,
                estilo: tema.textTheme.bodySmall?.copyWith(
                  color: colores.onSurfaceVariant,
                ),
                onAbrir: (a) => widget.onAbrirArtista(a.comoArtista),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _BotonCopiarEnlace(
          trackUri: track.uri,
          onCopiar: () => _copiarEnlace(track, notificar: false),
        ),
        if (!track.isEpisode && track.uri.isNotEmpty) ...[
          const SizedBox(width: 2),
          LikeButton(
            likes: widget.likes,
            uri: track.uri,
            pista: track,
            size: 20,
            caja: 32,
          ),
        ],
      ],
    );
  }

  Widget _tarjetaLetra(BuildContext context, Track track) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final fondoBase = Color.lerp(
      const Color(0xFF7A0D0D),
      colores.primaryContainer,
      0.35,
    )!;
    final fondoOscuro = Color.lerp(fondoBase, Colors.black, 0.45)!;

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fondoBase, fondoOscuro],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: T(
                    'Vista previa de la letra',
                    style: tema.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _letraDesplegada
                      ? 'Contraer vista previa'
                      : 'Desplegar un poco la letra',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: Icon(
                    _letraDesplegada ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  onPressed: () =>
                      setState(() => _letraDesplegada = !_letraDesplegada),
                ),
                IconButton(
                  tooltip: 'Abrir letra completa',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  onPressed: widget.onAbrirLetraCompleta,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _letraDesplegada ? 290 : 126,
                ),
                child: _contenidoLetra(context, track),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenidoLetra(BuildContext context, Track track) {
    if (_cargandoLetra) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
        ),
      );
    }
    final letra = _letra;
    if (letra == null) return const SizedBox.shrink();
    if (letra.instrumental) {
      return const Text(
        'Pista instrumental',
        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      );
    }
    if (letra.lineas.isEmpty) {
      return SingleChildScrollView(
        child: Text(
          letra.textoPlano,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      );
    }

    final desfase = widget.player.config.desfasesLetraMs[track.uri] ?? 0;
    return ValueListenableBuilder<int>(
      valueListenable: widget.player.progressMs,
      builder: (context, progressMs, _) {
        final ms = progressMs + desfase;
        var idx = 0;
        for (var i = 0; i < letra.lineas.length; i++) {
          if (letra.lineas[i].inicioMs <= ms) {
            idx = i;
          } else {
            break;
          }
        }
        final inicio = _letraDesplegada ? math.max(0, idx - 1) : idx;
        final fin = _letraDesplegada
            ? math.min(letra.lineas.length, inicio + 9)
            : math.min(letra.lineas.length, inicio + 4);
        final visibles = letra.lineas.sublist(inicio, fin);

        return ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.72, 1.0],
            colors: [Colors.white, Colors.white, Colors.transparent],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < visibles.length; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      visibles[k].texto.isEmpty ? '♪' : visibles[k].texto,
                      style: TextStyle(
                        color: (inicio + k) == idx
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.62),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.32,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tarjetaArtista(BuildContext context, ArtistaDePista principal) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final info = _infoArtista;
    final fallback = _artistaFallback;

    final nombre = (info != null && info.nombre.isNotEmpty)
        ? info.nombre
        : (fallback?.name.isNotEmpty == true ? fallback!.name : principal.name);
    final imagen = info?.imagenBanner ?? fallback?.artGrande ?? fallback?.art;
    final rawBio = info?.biografia ?? fallback?.biografia ?? '';
    final bioFormateada = rawBio.isNotEmpty ? formatearBiografia(rawBio) : null;
    final textoBio = bioFormateada?.parrafos.join('\n\n') ?? '';

    final artistaParaSeguir = Artist(
      id: principal.id,
      uri: principal.uri,
      name: nombre,
      art: fallback?.art ?? imagen,
      artGrande: imagen,
      followers: fallback?.followers ?? 0,
      biografia: rawBio.isNotEmpty ? rawBio : null,
    );

    final subtituloOyentes = info?.oyentesMensuales != null
        ? '${formatearOyentesMensuales(info!.oyentesMensuales!)} oyentes mensuales'
        : (fallback != null && fallback.followers > 0
              ? '${formatearCuenta(fallback.followers)} seguidores'
              : null);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colores.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          InkWell(
            onTap: () => widget.onAbrirArtista(artistaParaSeguir),
            child: SizedBox(
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ArtImage(
                    url: imagen,
                    urlGrande: imagen,
                    size: 170,
                    ancho: widget.anchoCompacto,
                    radius: 0,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xAA000000),
                          Colors.transparent,
                          Color(0x66000000),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 12,
                    left: 14,
                    right: 14,
                    child: T(
                      'Información sobre el artista',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => widget.onAbrirArtista(artistaParaSeguir),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (info?.verificado == true) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message: 'Artista verificado',
                          child: Icon(
                            Icons.verified,
                            size: 16,
                            color: Color(0xFF3D91F4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: subtituloOyentes != null
                          ? Text(
                              subtituloOyentes,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tema.textTheme.bodySmall?.copyWith(
                                color: colores.onSurfaceVariant,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    ArtistFavoriteButton(
                      favoritos: widget.favoritos,
                      artista: artistaParaSeguir,
                      compacto: true,
                    ),
                  ],
                ),
                if (textoBio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _bioExpandida = !_bioExpandida),
                    child: Text(
                      textoBio,
                      maxLines: _bioExpandida ? null : 3,
                      overflow: _bioExpandida
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: colores.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _tarjetaCreditos(
    BuildContext context,
    Track track,
    CreditosDePista creditos,
  ) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final visibles = creditos.personas.take(3).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colores.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: T(
                    'Créditos',
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () => _mostrarTodosLosCreditos(track, creditos),
                  child: T(
                    'Mostrar todos',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < visibles.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _filaCredito(visibles[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaCredito(CreditoPista persona, {bool enDialogo = false}) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InkWell(
            onTap: persona.tienePerfil
                ? () {
                    if (enDialogo) Navigator.of(context).pop();
                    widget.onAbrirArtista(persona.comoArtista);
                  }
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  persona.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (persona.rolesTexto.isNotEmpty)
                  Text(
                    persona.rolesTexto,
                    maxLines: enDialogo ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: colores.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (persona.tienePerfil) ...[
          const SizedBox(width: 8),
          ArtistFavoriteButton(
            favoritos: widget.favoritos,
            artista: persona.comoArtista,
            compacto: true,
          ),
        ],
      ],
    );
  }

  Widget _tarjetaGira(
    BuildContext context,
    List<ConciertoArtista> conciertos,
  ) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;
    final visibles = _giraExpandida
        ? conciertos
        : conciertos.take(2).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colores.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: T(
                    'De gira',
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (conciertos.length > 2 || _giraExpandida)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () =>
                        setState(() => _giraExpandida = !_giraExpandida),
                    child: T(
                      _giraExpandida ? 'Mostrar menos' : 'Mostrar todos',
                      style: tema.textTheme.labelMedium?.copyWith(
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < visibles.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _filaConcierto(context, visibles[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaConcierto(BuildContext context, ConciertoArtista c) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: c.url.isEmpty
          ? null
          : () => unawaited(
              launchUrl(Uri.parse(c.url), mode: LaunchMode.externalApplication),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colores.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  c.mesCorto,
                  style: tema.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1.1,
                    color: colores.onSurfaceVariant,
                  ),
                ),
                Text(
                  c.diaNumero,
                  style: tema.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.ciudad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (c.artista.isNotEmpty)
                  Text(
                    c.artista,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                Text(
                  c.lineaDetalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: colores.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCola(BuildContext context, Track siguiente) {
    final tema = Theme.of(context);
    final colores = tema.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colores.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: T(
                    'A continuación en la cola',
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: widget.onAbrirCola,
                  child: T(
                    'Abrir cola',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => unawaited(widget.player.playTrack(siguiente.uri)),
              child: Row(
                children: [
                  ArtImage(
                    url: siguiente.artSmall ?? siguiente.artMedium,
                    size: 44,
                    radius: 6,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          siguiente.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          siguiente.artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: colores.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArteAnimadoPista extends StatefulWidget {
  const _ArteAnimadoPista({
    required this.url,
    required this.urlGrande,
    required this.lado,
    required this.animar,
    required this.tieneCanvas,
  });

  final String? url;
  final String? urlGrande;
  final double lado;
  final bool animar;
  final bool tieneCanvas;

  @override
  State<_ArteAnimadoPista> createState() => _ArteAnimadoPistaState();
}

class _ArteAnimadoPistaState extends State<_ArteAnimadoPista>
    with SingleTickerProviderStateMixin {
  AnimationController? _control;

  @override
  void initState() {
    super.initState();
    if (widget.animar) _asegurarControl().repeat(reverse: true);
  }

  AnimationController _asegurarControl() => _control ??= AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didUpdateWidget(covariant _ArteAnimadoPista oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animar != oldWidget.animar) {
      if (widget.animar) {
        _asegurarControl().repeat(reverse: true);
      } else {
        _control?.stop();
      }
    }
  }

  @override
  void dispose() {
    _control?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ArtImage(
      url: widget.url,
      urlGrande: widget.urlGrande,
      size: widget.lado,
      radius: 12,
    );
    if (!widget.animar) return base;
    final control = _asegurarControl();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AnimatedBuilder(
        animation: control,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(control.value);
          final escala = 1.0 + (widget.tieneCanvas ? 0.055 : 0.035) * t;
          final dx = (t - 0.5) * 4.0;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(scale: escala, child: child),
          );
        },
        child: base,
      ),
    );
  }
}

class _IconoComprimirDerechaPainter extends CustomPainter {
  const _IconoComprimirDerechaPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(rect, paint);

    final divX = size.width * 0.65;
    canvas.drawLine(
      Offset(divX, 1.5),
      Offset(divX, size.height - 1.5),
      paint,
    );

    final cy = size.height / 2;
    final ax = size.width * 0.30;
    final path = Path()
      ..moveTo(ax, cy - 2.6)
      ..lineTo(ax + 3.0, cy)
      ..lineTo(ax, cy + 2.6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _IconoComprimirDerechaPainter old) =>
      old.color != color;
}

class _BotonCopiarEnlace extends StatefulWidget {
  const _BotonCopiarEnlace({
    required this.trackUri,
    required this.onCopiar,
  });

  final String trackUri;
  final Future<void> Function() onCopiar;

  @override
  State<_BotonCopiarEnlace> createState() => _BotonCopiarEnlaceState();
}

class _BotonCopiarEnlaceState extends State<_BotonCopiarEnlace> {
  bool _copiado = false;
  Timer? _temporizador;

  @override
  void didUpdateWidget(covariant _BotonCopiarEnlace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackUri != widget.trackUri) {
      _temporizador?.cancel();
      _temporizador = null;
      _copiado = false;
    }
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  void _alPulsar() {
    unawaited(widget.onCopiar());
    _temporizador?.cancel();
    setState(() => _copiado = true);
    _temporizador = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _copiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final sinAnimar =
        MediaQuery.disableAnimationsOf(context) || modoRendimiento.value;

    return Tooltip(
      message: _copiado ? 'Enlace copiado' : 'Copiar enlace de la canción',
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          style: IconButton.styleFrom(
            backgroundColor: _copiado
                ? colores.primary.withValues(alpha: 0.14)
                : null,
          ),
          onPressed: _alPulsar,
          icon: AnimatedSwitcher(
            duration: sinAnimar
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _copiado
                ? Icon(
                    Icons.check_rounded,
                    key: const ValueKey('copiado'),
                    size: 18,
                    color: colores.primary,
                  )
                : Icon(
                    Icons.copy_rounded,
                    key: const ValueKey('copiar'),
                    size: 18,
                    color: colores.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}
