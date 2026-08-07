import 'dart:async';

import 'package:flutter/material.dart';

import '../core/home_store.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import 'art_image.dart';
import 'track_tile.dart';

/// Portada: lo último que has escuchado y lo que más pones.
///
/// **No hay mixes diarios ni radar de novedades, y no es un descuido**: las
/// listas que Spotify genera para cada usuario no las expone la Web API. Los
/// endpoints de `/browse` dan 403 en Modo Desarrollo y `/recommendations` está
/// retirado; está comprobado en `tool/probe_home.dart`. Lo que se enseña aquí
/// sale de la cuenta del propio usuario, que es lo que sí se puede leer.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.home,
    required this.player,
    required this.likes,
    required this.onReauth,
  });

  final HomeStore home;
  final PlayerController player;
  final LikedStore likes;
  final Future<void> Function() onReauth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Si ya está cargada de una visita anterior, no hace nada.
    unawaited(widget.home.cargar());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.home.puedeLeer) return _avisoPermisos(theme);

    return AnimatedBuilder(
      animation: widget.home,
      builder: (context, _) {
        final home = widget.home;
        if (home.cargando && home.vacio) {
          return const Center(child: CircularProgressIndicator());
        }
        if (home.error != null && home.vacio) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(home.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Text('Inicio', style: theme.textTheme.headlineSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Actualizar',
                    icon: const Icon(Icons.refresh),
                    onPressed: home.cargando
                        ? null
                        : () => unawaited(home.cargar(forzar: true)),
                  ),
                ],
              ),
            ),
            if (home.recientes.isNotEmpty) ...[
              _Titulo('Vuelve a escuchar', theme),
              _TirasDeCanciones(
                tracks: home.recientes,
                onPlay: (t) => widget.player.playTrack(t.uri),
              ),
            ],
            if (home.artistas.isNotEmpty) ...[
              _Titulo('Tus artistas', theme),
              _TiraDeArtistas(
                artistas: home.artistas,
                // El contexto de un artista pone sus canciones más populares.
                onPlay: (a) => widget.player.playContext(a.uri),
              ),
            ],
            if (home.masEscuchadas.isNotEmpty) ...[
              _Titulo('Lo que más escuchas', theme),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '   De las últimas semanas',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              // La uri que suena se escucha aquí para que el título verde salte
              // de canción en canción sin repintar la portada entera.
              ValueListenableBuilder<String?>(
                valueListenable: widget.player.currentUri,
                builder: (context, currentUri, _) => Column(
                  children: [
                    for (var i = 0; i < home.masEscuchadas.length; i++)
                      TrackTile(
                        track: home.masEscuchadas[i],
                        likes: widget.likes,
                        leadingNumber: i + 1,
                        isCurrent: currentUri == home.masEscuchadas[i].uri,
                        actions: TrackActions(
                          onPlay: () =>
                              widget.player.playTrack(home.masEscuchadas[i].uri),
                          onQueue: () async {
                            await widget.player
                                .addToQueue(home.masEscuchadas[i].uri);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Añadida a la cola'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (!home.cargando && home.vacio)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Todavía no hay historial que enseñar. Pon algo de música y '
                  'vuelve por aquí.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _avisoPermisos(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.home_outlined, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Falta un permiso para la portada',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Para enseñarte lo que más escuchas y tu historial hacen falta '
                'dos permisos que tu sesión no incluye, porque se pidieron '
                'después de que la iniciaras.\n\n'
                'Un inicio de sesión antiguo no gana permisos al renovarse: hay '
                'que volver a pasar por Spotify una vez. No perderás nada.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: widget.onReauth,
                icon: const Icon(Icons.refresh),
                label: const Text('Volver a iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, this.theme);

  final String texto;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(texto, style: theme.textTheme.titleMedium),
      );
}

/// Tira horizontal de carátulas. Se pide la variante de 300 px de Spotify (no
/// la de 640) porque la tarjeta mide 128: es la regla de siempre, y la que
/// mantiene la memoria plana.
class _TirasDeCanciones extends StatelessWidget {
  const _TirasDeCanciones({required this.tracks, required this.onPlay});

  static const double _ladoTarjeta = 128;

  final List<Track> tracks;
  final void Function(Track) onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      // Carátula + dos líneas de texto.
      height: _ladoTarjeta + 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final t = tracks[i];
          return InkWell(
            onTap: () => onPlay(t),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: _ladoTarjeta,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArtImage(
                      url: t.artSmall,
                      urlGrande: t.artMedium,
                      size: _ladoTarjeta,
                      radius: 6,
                    ),
                    const SizedBox(height: 6),
                    Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(t.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TiraDeArtistas extends StatelessWidget {
  const _TiraDeArtistas({required this.artistas, required this.onPlay});

  static const double _lado = 108;

  final List<Artist> artistas;
  final void Function(Artist) onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _lado + 28,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: artistas.length,
        itemBuilder: (context, i) {
          final a = artistas[i];
          return InkWell(
            onTap: () => onPlay(a),
            borderRadius: BorderRadius.circular(_lado),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: _lado,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Radio la mitad del lado = círculo.
                    ArtImage(url: a.art, size: _lado, radius: _lado / 2),
                    const SizedBox(height: 6),
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
