import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import '../core/temas.dart';
import 'art_image.dart';
import 'artist_favorite_button.dart';
import 'home_screen.dart';
import 'movimiento.dart';
import 'tira_horizontal.dart';
import 'texto_traducido.dart';
import 'track_tile.dart';

const int kPopularesDelPerfil = 5;
const double kPaddingPerfil = 20;

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.api,
    required this.player,
    required this.likes,
    required this.favoritos,
    required this.artist,
    this.sidecar,
    this.onAbrirAlbum,
    this.onAbrirPlaylist,
    this.onAbrirArtista,
  });

  final SpotifyApi api;
  final PlayerController player;
  final LikedStore likes;
  final ArtistasFavoritosStore favoritos;
  final Artist artist;
  final MetadataSidecar? sidecar;
  final void Function(Album album)? onAbrirAlbum;
  final void Function(Playlist playlist)? onAbrirPlaylist;
  final void Function(Artist artista)? onAbrirArtista;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Artist _artista = widget.artist;
  List<Track> _tracks = const [];
  List<Album> _albumes = const [];
  List<Album> _singles = const [];
  List<Album> _apareceEn = const [];
  List<Playlist> _playlists = const [];
  List<Artist> _relacionados = const [];
  bool _cargando = true;
  String? _error;
  var _pendienteDeSidecar = false;

  @override
  void initState() {
    super.initState();
    widget.sidecar?.addListener(_siSidecarListo);
    unawaited(_cargar());
  }

  @override
  void dispose() {
    widget.sidecar?.removeListener(_siSidecarListo);
    super.dispose();
  }

  void _siSidecarListo() {
    if (!_pendienteDeSidecar) return;
    if (widget.sidecar?.ready != true) return;
    _pendienteDeSidecar = false;
    unawaited(_cargar());
  }

  Future<bool> _esperarSidecar() async {
    final s = widget.sidecar;
    if (s == null) return false;
    if (s.ready) return true;
    _pendienteDeSidecar = true;
    final listo = Completer<bool>();
    void ver() {
      if (s.ready && !listo.isCompleted) listo.complete(true);
    }
    s.addListener(ver);
    try {
      return await listo.future
          .timeout(const Duration(seconds: 12), onTimeout: () => s.ready);
    } finally {
      s.removeListener(ver);
    }
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    final sidecarListo = await _esperarSidecar();
    if (!mounted) return;

    if (sidecarListo) {
      try {
        await _cargarDelSidecar();
        _pendienteDeSidecar = false;
        return;
      } catch (e) {
        _pendienteDeSidecar = false;
        if (!mounted) return;
        if (widget.api.avisoDeCuota != null) {
          setState(() {
            _error =
                'No se pudieron leer las canciones de este artista.\n\n$e';
            _cargando = false;
          });
          return;
        }
      }
    }

    if (widget.api.avisoDeCuota != null) {
      setState(() {
        _error = widget.api.avisoDeCuota;
        _cargando = false;
      });
      return;
    }

    await _cargarDeLaApi();
  }

  Future<void> _cargarDelSidecar() async {
    final perfil = await widget.sidecar!.artista(widget.artist.id);
    if (!mounted) return;
    setState(() {
      _artista = perfil.artista.name.isEmpty ? widget.artist : perfil.artista;
      _tracks = perfil.top;
      _albumes = perfil.albumes;
      _singles = perfil.singles;
      _apareceEn = perfil.apareceEn;
      _playlists = const [];
      _relacionados = [
        for (final a in perfil.relacionados) if (a.id != widget.artist.id) a
      ];
      _cargando = false;
    });
  }

  Future<void> _cargarDeLaApi() async {
    try {
      final detalleF = widget.api.artist(widget.artist.id);
      final topF = widget.api.artistTopTracks(widget.artist.id);
      final albumesF = _suave(
        widget.api.artistAlbums(
          widget.artist.id,
          includeGroups: 'album',
          max: 20,
        ),
        const <Album>[],
      );
      final singlesF = _suave(
        widget.api.artistAlbums(
          widget.artist.id,
          includeGroups: 'single',
          max: 20,
        ),
        const <Album>[],
      );
      final apareceF = _suave(
        widget.api.artistAlbums(
          widget.artist.id,
          includeGroups: 'appears_on',
          max: 15,
        ),
        const <Album>[],
      );
      final relacionadosF = _suave(
        widget.api.relatedArtists(widget.artist.id),
        const <Artist>[],
      );
      final playlistsF = _suave(
        _playlistsDelArtista(widget.artist),
        const <Playlist>[],
      );

      Artist artist;
      try {
        artist = await detalleF;
      } catch (_) {
        artist = widget.artist;
      }
      if (mounted) {
        setState(() => _artista = artist.name.isEmpty ? widget.artist : artist);
      }

      final tracks = await topF;
      final albumes = await albumesF;
      final singles = await singlesF;
      final aparece = await apareceF;
      final parecidos = await relacionadosF;
      final listas = await playlistsF;

      if (!mounted) return;

      setState(() {
        _tracks = tracks;
        _albumes = albumes;
        _singles = singles;
        _apareceEn = aparece;
        _playlists = listas;
        _relacionados = [
          for (final a in parecidos) if (a.id != widget.artist.id) a
        ];
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.isForbidden
            ? 'Spotify no deja leer las canciones de este artista.\n\n'
                'Ni sus más populares ni sus discos: es el tope del Modo '
                'Desarrollo, no un problema de tu cuenta.'
            : 'No se pudieron leer las canciones de este artista.\n\n$e';
        _cargando = false;
      });
    }
  }

  Future<List<Playlist>> _playlistsDelArtista(Artist artista) async {
    final res = await widget.api.search(
      artista.name,
      types: const ['playlist'],
      limit: 10,
    );
    return playlistsDelArtista(res.playlists.items, artista.name);
  }

  List<Track> get _populares => _tracks.length <= kPopularesDelPerfil
      ? _tracks
      : _tracks.sublist(0, kPopularesDelPerfil);

  List<String> get _urisPopulares => [for (final t in _populares) t.uri];

  void _reproducir() {
    final uri =
        _artista.uri.isNotEmpty ? _artista.uri : widget.artist.uri;
    if (uri.isNotEmpty) {
      unawaited(widget.player.playContext(uri));
      return;
    }
    if (_urisPopulares.isNotEmpty) {
      unawaited(widget.player.playLista(_urisPopulares));
    }
  }

  void _aleatorio() {
    final uris = List<String>.from(_urisPopulares)..shuffle();
    if (uris.isEmpty) {
      _reproducir();
      return;
    }
    unawaited(widget.player.playLista(uris));
  }

  void _toast(String mensaje) {
    if (!mounted) return;
    unawaited(() async {
      final t = await traducirTexto(context, mensaje);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), duration: const Duration(seconds: 2)),
      );
    }());
  }

  void _abrirDisco(Album a) {
    if (widget.onAbrirAlbum != null) {
      widget.onAbrirAlbum!(a);
    } else {
      unawaited(widget.player.playContext(a.uri));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final dosColumnas = c.maxWidth >= 620;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: _cabecera(context, dosColumnas: dosColumnas)),
            if (_error != null && !dosColumnas)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _errorDeCarga(context),
              )
            else if (_cargando && !dosColumnas)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              )
            else if (!_cargando && _error == null) ...[
              if (!dosColumnas && _populares.isNotEmpty)
                ..._sliverPopulares(),
              if (_albumes.isNotEmpty) ...[
                _titulo('Álbumes'),
                SliverToBoxAdapter(
                  child: TiraDeAlbumes(
                    albumes: _albumes,
                    onAbrir: _abrirDisco,
                    subtituloDe: (a) => a.anio ?? a.lineaSecundaria,
                  ),
                ),
              ],
              if (_singles.isNotEmpty) ...[
                _titulo('Singles y EPs'),
                SliverToBoxAdapter(
                  child: TiraDeAlbumes(
                    albumes: _singles,
                    onAbrir: _abrirDisco,
                    subtituloDe: (a) => a.lineaSecundaria,
                  ),
                ),
              ],
              if (_apareceEn.isNotEmpty) ...[
                _titulo('Destacado en'),
                SliverToBoxAdapter(
                  child: _TiraApaisada(
                    albumes: _apareceEn,
                    onAbrir: _abrirDisco,
                  ),
                ),
              ],
              if (_playlists.isNotEmpty) ...[
                _titulo('Listas de reproducción de ${_artista.name}'),
                SliverToBoxAdapter(
                  child: TiraDePlaylists(
                    playlists: _playlists,
                    onAbrir: (pl) => widget.onAbrirPlaylist?.call(pl),
                  ),
                ),
              ],
              if (_relacionados.isNotEmpty) ...[
                _titulo('Puede que también te guste'),
                SliverToBoxAdapter(
                  child: TiraDeArtistas(
                    artistas: _relacionados,
                    onAbrir: (a) => widget.onAbrirArtista?.call(a),
                    subtituloDe: (a) => a.followers > 0
                        ? '${formatearCuenta(a.followers)} seguidores'
                        : null,
                  ),
                ),
              ],
              if (_populares.isEmpty &&
                  _albumes.isEmpty &&
                  _singles.isEmpty &&
                  _apareceEn.isEmpty &&
                  _playlists.isEmpty &&
                  _relacionados.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: T(
                        'Este artista no tiene canciones que enseñar.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _sliverPopulares() {
    return [
      _titulo('Canciones más escuchadas'),
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 8),
        sliver: SliverList.builder(
          itemCount: _populares.length,
          itemBuilder: (context, i) => _tilePopular(i),
        ),
      ),
    ];
  }

  Widget _tilePopular(int i) {
    final t = _populares[i];
    return ValueListenableBuilder<String?>(
      valueListenable: widget.player.currentUri,
      builder: (context, currentUri, _) => TrackTile(
        track: t,
        likes: widget.likes,
        leadingNumber: i + 1,
        contentPadding: const EdgeInsets.symmetric(horizontal: kPaddingPerfil),
        isCurrent: currentUri != null && currentUri == t.uri,
        actions: TrackActions(
          onPlay: () => widget.player.playLista(_urisPopulares, desde: i),
          onQueue: () async {
            await widget.player.addToQueue(t.uri);
            _toast('Añadida a la cola');
          },
        ),
      ),
    );
  }

  Widget _cabecera(BuildContext context, {required bool dosColumnas}) {
    final theme = Theme.of(context);
    final estilo = EstiloNeoFy.de(context);
    final art = _artista.artGrande ?? _artista.art ?? widget.artist.art;
    final generos = _artista.genres.take(3).join(' · ');
    final bio = _artista.biografia?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final ancho = c.maxWidth;
              if (!dosColumnas) {
                final anchoFoto = math.min(ancho, 640.0);
                final alto = (anchoFoto * 9 / 16).clamp(180.0, 280.0);
                return ArtImage(
                  url: art,
                  urlGrande: art,
                  size: alto,
                  ancho: anchoFoto,
                  radius: estilo.radio,
                );
              }

              final altoLista = 28.0 + 8 + 64.0 * math.max(_populares.length, 4);
              final alto = altoLista.clamp(220.0, 340.0);
              final anchoFoto = math.min(alto, ancho * 0.42);
              return SizedBox(
                height: alto,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArtImage(
                      url: art,
                      urlGrande: art,
                      size: alto,
                      ancho: anchoFoto,
                      radius: estilo.radio,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _panelDerecho(context, theme)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _artista.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_artista.followers > 0) ...[
            const SizedBox(height: 6),
            T(
              '${formatearCuenta(_artista.followers)} seguidores',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (generos.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              generos,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            BiografiaTraducida(texto: bio),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _aleatorio,
                icon: const Icon(Icons.shuffle, size: 18),
                label: T('Aleatorio'),
              ),
              OutlinedButton.icon(
                onPressed: _reproducir,
                icon: const Icon(Icons.play_arrow),
                label: T('Reproducir'),
              ),
              ArtistFavoriteButton(
                favoritos: widget.favoritos,
                artista: _artista,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelDerecho(BuildContext context, ThemeData theme) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          child: Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    if (_populares.isEmpty) {
      return Center(
        child: T(
          'Sin canciones que enseñar aquí.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPaddingPerfil, 0, kPaddingPerfil, 4),
          child: T(
            'Canciones más escuchadas',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _populares.length,
            itemBuilder: (context, i) => _tilePopular(i),
          ),
        ),
      ],
    );
  }

  Widget _errorDeCarga(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _titulo(String texto) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kPaddingPerfil, 20, kPaddingPerfil, 8),
        child: T(
          texto,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TiraApaisada extends StatelessWidget {
  const _TiraApaisada({required this.albumes, required this.onAbrir});

  static const double _ancho = 196;
  static const double _altoFoto = 110;

  final List<Album> albumes;
  final void Function(Album) onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final radio = EstiloNeoFy.de(context).radio;
    final altoTexto =
        MediaQuery.textScalerOf(context).scale(estilo.fontSize ?? 14) *
            (estilo.height ?? 1.4) *
            2;
    return TiraHorizontal(
      alto: 4 + _altoFoto + 6 + altoTexto.ceilToDouble() + 4,
      centroDeFlechas: 4 + _altoFoto / 2,
      itemCount: albumes.length,
      itemBuilder: (context, i) {
        final a = albumes[i];
        return Pulsable(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              width: _ancho,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onAbrir(a),
                  borderRadius: BorderRadius.circular(radio),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArtImage(
                        url: a.art,
                        size: _altoFoto,
                        ancho: _ancho,
                        radius: radio,
                      ),
                      const SizedBox(height: 6),
                      Text(a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              estilo.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        a.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: estilo.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<T> _suave<T>(Future<T> futuro, T vacio) async {
  try {
    return await futuro;
  } catch (_) {
    return vacio;
  }
}

String _resumen(List<Track> tracks) {
  final ms = tracks.fold<int>(0, (suma, t) => suma + t.durationMs);
  final minutos = (ms / 60000).round();
  final canciones =
      tracks.length == 1 ? '1 canción' : '${tracks.length} canciones';

  if (minutos < 60) return '$canciones · $minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  final enHoras = horas == 1 ? '1 h' : '$horas h';
  return resto == 0
      ? '$canciones · $enHoras'
      : '$canciones · $enHoras $resto min';
}

@visibleForTesting
String resumenDeArtista(List<Track> tracks) => _resumen(tracks);

@visibleForTesting
List<Playlist> playlistsDelArtista(List<Playlist> listas, String nombre) {
  final clave = nombre.trim().toLowerCase();
  if (clave.isEmpty) return const [];
  final vistos = <String>{};
  final out = <Playlist>[];
  for (final pl in listas) {
    if (pl.id.isEmpty || !vistos.add(pl.id)) continue;
    if (pl.owner.trim().toLowerCase() != clave) continue;
    out.add(pl);
  }
  return out;
}
