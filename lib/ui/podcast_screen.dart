import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import '../core/temas.dart';
import 'art_image.dart';
import 'cabecera_coleccion.dart';
import 'now_playing_bar.dart' show formatMs;
import 'texto_traducido.dart';

class PodcastScreen extends StatefulWidget {
  const PodcastScreen({
    super.key,
    required this.podcast,
    required this.api,
    required this.player,
  });

  final Podcast podcast;
  final SpotifyApi api;
  final PlayerController player;

  @override
  State<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  final _episodes = <PodcastEpisode>[];
  var _offset = 0;
  var _loading = false;
  var _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.podcastEpisodes(
        widget.podcast.id,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _episodes.addAll(page.items);
        _offset += page.rawCount;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrirEnSpotify(Track track) async {
    try {
      if (await launchUrl(
        Uri.parse(track.uri),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // El protocolo puede no estar registrado, así que probamos el enlace web.
    }
    final id = track.uri.split(':').last;
    final abierta = await launchUrl(
      Uri.https('open.spotify.com', '/episode/$id'),
      mode: LaunchMode.externalApplication,
    );
    if (!abierta && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: T('No se pudo abrir el episodio en Spotify.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podcast = widget.podcast;
    final nocturno = EstiloNeoFy.de(context).usaInterfazNocturna;
    return CustomScrollView(
      slivers: [
        if (nocturno)
          SliverToBoxAdapter(
            child: CabeceraColeccion(
              portada: podcast.art,
              titulo: Text(podcast.name),
              detalle: podcast.publisher.isEmpty
                  ? const T('Pódcast')
                  : T('Pódcast · ${podcast.publisher}'),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!nocturno)
                  Row(
                    children: [
                      ArtImage(url: podcast.art, size: 110),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            T('Pódcast', style: theme.textTheme.labelLarge),
                            Text(
                              podcast.name,
                              style: theme.textTheme.headlineMedium,
                            ),
                            Text(
                              podcast.publisher,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (podcast.description.isNotEmpty) ...[
                  if (!nocturno) const SizedBox(height: 16),
                  Text(
                    podcast.description,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 28),
                T('Episodios', style: theme.textTheme.titleLarge),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: _episodes.length,
            itemBuilder: (context, i) {
              final episode = _episodes[i];
              final track = episode.track;
              final date = DateTime.tryParse(episode.releaseDate);
              final release = date == null || episode.releaseDate.length < 10
                  ? episode.releaseDate
                  : MaterialLocalizations.of(context).formatShortDate(date);
              return ExpansionTile(
                key: PageStorageKey(track.uri),
                leading: ArtImage(url: track.artSmall ?? podcast.art, size: 48),
                title: Text(track.name),
                subtitle: Text(
                  [
                    release,
                    formatMs(track.durationMs),
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (episode.playable && widget.player.libre == null)
                        FilledButton.tonalIcon(
                          onPressed: () => widget.player.playTrack(track.uri),
                          icon: const Icon(Icons.play_arrow),
                          label: const T('Reproducir aquí'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _abrirEnSpotify(track),
                        icon: const Icon(Icons.open_in_new),
                        label: const T('Abrir episodio en Spotify'),
                      ),
                    ],
                  ),
                  if (episode.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(episode.description),
                  ],
                ],
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : _error != null
                  ? Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _load,
                          child: const T('Reintentar'),
                        ),
                      ],
                    )
                  : _hasMore
                  ? OutlinedButton(
                      onPressed: _load,
                      child: const T('Más episodios'),
                    )
                  : _episodes.isEmpty
                  ? const T('No hay episodios disponibles.')
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
