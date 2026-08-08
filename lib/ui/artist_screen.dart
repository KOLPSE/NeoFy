import 'dart:async';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'art_image.dart';
import 'track_tile.dart';

/// Lo que se va a reproducir de un artista, **antes** de darle a reproducir.
///
/// Pulsar un artista en la portada ponía su música directamente, sin enseñar
/// qué. Aquí se ve la lista, cuántas canciones son y cuánto duran en total.
///
/// ⚠️ **Lo que se pinta es exactamente lo que suena**, y por eso el botón usa
/// [PlayerController.playLista] con estas mismas canciones y no
/// `playContext(artista.uri)`. El contexto de un artista lo decide Spotify y no
/// tiene por qué coincidir con esta lista: prometer un recuento y una duración
/// y luego reproducir otra cosa sería mentir en la propia pantalla que existe
/// para no hacerlo.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.api,
    required this.player,
    required this.likes,
    required this.artist,
  });

  final SpotifyApi api;
  final PlayerController player;
  final LikedStore likes;
  final Artist artist;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
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
      final t = await widget.api.artistTopTracks(widget.artist.id);
      if (!mounted) return;
      setState(() {
        _tracks = t;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron leer las canciones de este artista.\n\n$e';
        _cargando = false;
      });
    }
  }

  List<String> get _uris => [for (final t in _tracks) t.uri];

  void _toast(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Radio la mitad del lado = círculo, igual que en la portada.
              ArtImage(url: widget.artist.art, size: 96, radius: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.artist.name,
                        style: theme.textTheme.headlineSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      _cargando ? 'Cargando…' : _resumen(_tracks),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      // Deshabilitado mientras no haya lista: reproducir algo
                      // que aún no se sabe cuál es no tiene sentido.
                      onPressed: _tracks.isEmpty
                          ? null
                          : () => widget.player.playLista(_uris),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Reproducir'),
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
          child: Text('Este artista no tiene canciones que enseñar.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }

    // Escuchar aquí la uri que suena es lo que mueve el título verde de una
    // canción a la siguiente sin repintar la pantalla entera.
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
              // Desde la lista entera y por su posición, para que "siguiente"
              // siga por donde toca en vez de dejar la canción repitiéndose.
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

/// `10 canciones · 32 min`, o con horas cuando pasa de sesenta minutos.
///
/// Se redondea al minuto porque los segundos no le dicen nada a nadie en un
/// total, y se escribe en singular cuando toca: "1 canción · 3 min".
String _resumen(List<Track> tracks) {
  final ms = tracks.fold<int>(0, (suma, t) => suma + t.durationMs);
  final minutos = (ms / 60000).round();
  final canciones =
      tracks.length == 1 ? '1 canción' : '${tracks.length} canciones';

  if (minutos < 60) return '$canciones · $minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  final enHoras = horas == 1 ? '1 h' : '$horas h';
  return resto == 0 ? '$canciones · $enHoras' : '$canciones · $enHoras $resto min';
}

/// Solo para los tests: el resumen que se pinta bajo el nombre del artista.
@visibleForTesting
String resumenDeArtista(List<Track> tracks) => _resumen(tracks);
