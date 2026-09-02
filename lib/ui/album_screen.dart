import 'dart:async';

import 'package:flutter/material.dart';

import '../core/artistas_favoritos_store.dart';
import '../core/liked_store.dart';
import '../core/metadata_sidecar.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'art_image.dart';
import 'artist_favorite_button.dart';
import 'linea_de_artistas.dart';
import 'texto_traducido.dart';
import 'track_tile.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.api,
    required this.player,
    required this.likes,
    required this.favoritos,
    required this.album,
    this.sidecar,
    this.artistaOrigen,
    this.onAbrirArtista,
  });

  final SpotifyApi api;
  final PlayerController player;
  final LikedStore likes;
  final ArtistasFavoritosStore favoritos;
  final Album album;
  final MetadataSidecar? sidecar;
  final Artist? artistaOrigen;
  final void Function(Artist artista)? onAbrirArtista;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<Track> _tracks = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_cargar());
  }

  Future<void> _cargar() async {
    try {
      List<Track> t;
      final sidecar = widget.sidecar;
      if (sidecar != null &&
          sidecar.ready &&
          widget.api.esperaDe('/albums') != null) {
        t = await sidecar.albumTracks(widget.album.id);
      } else {
        try {
          t = await widget.api.albumTracks(widget.album.id);
        } catch (e) {
          if (sidecar != null && sidecar.ready) {
            t = await sidecar.albumTracks(widget.album.id);
          } else {
            rethrow;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _tracks = t;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.isForbidden
            ? 'Spotify no permite ver las canciones de este álbum (límite de Modo Desarrollo).'
            : 'No se pueden cargar las canciones.\n$e';
        _cargando = false;
      });
    }
  }

  List<String> get _uris => [for (final t in _tracks) t.uri];

  Artist? get _artistaDelDisco {
    final origen = widget.artistaOrigen;
    if (origen != null && origen.id.isNotEmpty) return origen;
    final principal = widget.album.artistaPrincipal;
    if (principal != null && principal.sePuedeAbrir) {
      return principal.comoArtista;
    }
    if (_tracks.isNotEmpty) {
      for (final a in _tracks.first.listaDeArtistas) {
        if (a.sePuedeAbrir) return a.comoArtista;
      }
    }
    return null;
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

  void _abrirArtista(Artist a) {
    widget.onAbrirArtista?.call(a);
  }

  String get _subtitulo {
    final partes = <String>[
      if (widget.album.anio != null) widget.album.anio!,
      if (_cargando)
        'Cargando…'
      else if (_tracks.isNotEmpty)
        _tracks.length == 1 ? '1 canción' : '${_tracks.length} canciones',
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artista = _artistaDelDisco;
    final listaArtistas = widget.album.listaDeArtistas.isNotEmpty
        ? widget.album.listaDeArtistas
        : (artista != null
            ? [
                ArtistaDePista(
                  id: artista.id,
                  uri: artista.uri,
                  name: artista.name,
                ),
              ]
            : const <ArtistaDePista>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArtImage(url: widget.album.art, size: 96),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.artistaOrigen != null) ...[
                      TextButton.icon(
                        onPressed: () => _abrirArtista(widget.artistaOrigen!),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: T('Volver a ${widget.artistaOrigen!.name}'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(widget.album.name,
                        style: theme.textTheme.headlineSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    if (listaArtistas.isNotEmpty)
                      LineaDeArtistas(
                        artistas: listaArtistas,
                        texto: widget.album.artists,
                        estilo: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onAbrir: widget.onAbrirArtista == null
                            ? null
                            : (a) => _abrirArtista(a.comoArtista),
                      )
                    else if (widget.album.artists.isNotEmpty)
                      Text(
                        widget.album.artists,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (_subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      T(
                        _subtitulo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _tracks.isEmpty && widget.album.uri.isEmpty
                              ? null
                              : () => _tracks.isEmpty
                                  ? widget.player.playContext(widget.album.uri)
                                  : widget.player.playLista(_uris),
                          icon: const Icon(Icons.play_arrow),
                          label: T('Reproducir'),
                        ),
                        if (artista != null)
                          ArtistFavoriteButton(
                            favoritos: widget.favoritos,
                            artista: artista,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _lista(theme)),
      ],
    );
  }

  Widget _lista(ThemeData theme) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
    if (_tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: T('Este disco no tiene canciones que enseñar.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }

    return ValueListenableBuilder<String?>(
      valueListenable: widget.player.currentUri,
      builder: (context, currentUri, _) => ListView.builder(
        itemCount: _tracks.length,
        itemBuilder: (context, i) {
          final t = _tracks[i];
          return TrackTile(
            track: t,
            likes: widget.likes,
            leadingNumber: i + 1,
            isCurrent: currentUri != null && currentUri == t.uri,
            actions: TrackActions(
              onPlay: () => widget.player.playLista(_uris, desde: i),
              onQueue: () async {
                await widget.player.addToQueue(t.uri);
                _toast('Añadida a la cola');
              },
            ),
          );
        },
      ),
    );
  }
}
