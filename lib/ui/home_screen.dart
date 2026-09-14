import 'dart:async';

import 'package:flutter/material.dart';

import '../core/home_store.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/temas.dart';
import 'art_image.dart';
import 'movimiento.dart';
import 'tira_horizontal.dart';
import 'texto_traducido.dart';
import 'track_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.home,
    required this.player,
    required this.likes,
    required this.onReauth,
    required this.onAbrirArtista,
  });

  final HomeStore home;
  final PlayerController player;
  final LikedStore likes;
  final Future<void> Function() onReauth;

  final void Function(Artist) onAbrirArtista;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.home.cargar());
  }

  Future<void> _reauthYRecargar() async {
    await widget.onReauth();
    // Tras el login el State de esta pantalla se reutiliza: initState no
    // vuelve a correr y, si la primera carga salió por falta de permisos,
    // aquí seguiría el hueco vacío para siempre.
    await widget.home.cargar(forzar: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.home.puedeLeer) return _avisoPermisos(theme);

    return AnimatedBuilder(
      animation: widget.home,
      builder: (context, _) {
        final home = widget.home;
        // Permisos llegaron después (reauth desde otra pantalla, scopes
        // tardíos): dispara la carga que initState no pudo hacer. Si ya
        // falló, no insistir en cada rebuild — el botón de actualizar sí.
        if (!home.cargado && !home.cargando && home.error == null) {
          unawaited(home.cargar());
        }
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
                  T('Inicio', style: theme.textTheme.headlineSmall),
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
              _Titulo('Vuelve a escuchar'),
              TiraDeCanciones(
                tracks: home.recientes,
                onPlay: (i) => widget.player.playLista(
                  [for (final t in home.recientes) t.uri],
                  desde: i,
                ),
              ),
            ],
            if (home.paraTi.isNotEmpty) ...[
              _Titulo('Hecho para ti'),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: T(
                  '   Canciones de tus artistas top que no has escuchado hace poco',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TiraDeCanciones(
                tracks: home.paraTi,
                onPlay: (i) => widget.player.playLista(
                  [for (final t in home.paraTi) t.uri],
                  desde: i,
                ),
              ),
            ],
            if (home.artistas.isNotEmpty) ...[
              _Titulo('Tus artistas'),
              TiraDeArtistas(
                artistas: home.artistas,
                onAbrir: widget.onAbrirArtista,
              ),
            ],
            if (home.novedades.isNotEmpty) ...[
              _Titulo('Novedades'),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: T(
                  '   Lo último publicado en Spotify',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              TiraDeAlbumes(
                albumes: home.novedades,
                onAbrir: (a) => widget.player.playContext(a.uri),
              ),
            ],
            if (home.masEscuchadas.isNotEmpty) ...[
              _Titulo('Lo que más escuchas'),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: T(
                  '   De las últimas semanas',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
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
                          onPlay: () => widget.player.playLista(
                            [for (final t in home.masEscuchadas) t.uri],
                            desde: i,
                          ),
                          onQueue: () async {
                            await widget.player
                                .addToQueue(home.masEscuchadas[i].uri);
                            if (!context.mounted) return;
                            final t = await traducirTexto(
                                context, 'Añadida a la cola');
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(t),
                                duration: const Duration(seconds: 2),
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
                child: T(
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
              T('Falta un permiso para la portada',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              T(
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
                onPressed: () => unawaited(_reauthYRecargar()),
                icon: const Icon(Icons.refresh),
                label: T('Volver a iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: T(texto, style: Theme.of(context).textTheme.titleMedium),
      );
}

const double _huecoTarjeta = 6;
const double _margenTarjeta = 4;

double _altoDeTarjeta(
  BuildContext context,
  TextStyle estilo, {
  required double lado,
  required int lineas,
}) {
  final tamano = MediaQuery.textScalerOf(context).scale(estilo.fontSize ?? 14);
  final altoDeLinea = tamano * (estilo.height ?? 1.4);
  return _margenTarjeta * 2 +
      lado +
      _huecoTarjeta +
      (altoDeLinea * lineas).ceilToDouble();
}

class TiraDeCanciones extends StatelessWidget {
  const TiraDeCanciones({super.key, required this.tracks, required this.onPlay});

  static const double _ladoTarjeta = 128;

  final List<Track> tracks;

  final void Function(int indice) onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    return TiraHorizontal(
      alto: _altoDeTarjeta(context, estilo, lado: _ladoTarjeta, lineas: 2),
      centroDeFlechas: _margenTarjeta + _ladoTarjeta / 2,
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final t = tracks[i];
        return Pulsable(
          child: InkWell(
          onTap: () => onPlay(i),
          borderRadius: BorderRadius.circular(EstiloNeoFy.de(context).radio),
          child: Padding(
            padding: const EdgeInsets.all(_margenTarjeta),
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
                  ),
                  const SizedBox(height: _huecoTarjeta),
                  Text(t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: estilo.copyWith(fontWeight: FontWeight.w600)),
                  Text(t.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: estilo.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }
}

class TiraDeArtistas extends StatelessWidget {
  const TiraDeArtistas({
    super.key,
    required this.artistas,
    required this.onAbrir,
    this.subtituloDe,
  });

  static const double _lado = 108;

  final List<Artist> artistas;

  final void Function(Artist) onAbrir;
  final String? Function(Artist)? subtituloDe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final extra = subtituloDe != null;
    return TiraHorizontal(
      alto: _altoDeTarjeta(context, estilo, lado: _lado, lineas: extra ? 2 : 1),
      centroDeFlechas: _margenTarjeta + _lado / 2,
      itemCount: artistas.length,
      itemBuilder: (context, i) {
        final a = artistas[i];
        return Pulsable(
          child: InkWell(
          onTap: () => onAbrir(a),
          borderRadius: BorderRadius.circular(_lado),
          child: Padding(
            padding: const EdgeInsets.all(_margenTarjeta),
            child: SizedBox(
              width: _lado,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArtImage(url: a.art, size: _lado, radius: _lado / 2),
                  const SizedBox(height: _huecoTarjeta),
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: estilo),
                  if (subtituloDe != null)
                    Text(
                      subtituloDe!(a) ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: estilo.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }
}

class TiraDeAlbumes extends StatelessWidget {
  const TiraDeAlbumes({
    super.key,
    required this.albumes,
    required this.onAbrir,
    this.subtituloDe,
  });

  static const double _ladoTarjeta = 128;

  final List<Album> albumes;
  final void Function(Album) onAbrir;
  final String Function(Album)? subtituloDe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    return TiraHorizontal(
      alto: _altoDeTarjeta(context, estilo, lado: _ladoTarjeta, lineas: 2),
      centroDeFlechas: _margenTarjeta + _ladoTarjeta / 2,
      itemCount: albumes.length,
      itemBuilder: (context, i) {
        final a = albumes[i];
        return Pulsable(
          child: InkWell(
          onTap: () => onAbrir(a),
          borderRadius: BorderRadius.circular(EstiloNeoFy.de(context).radio),
          child: Padding(
            padding: const EdgeInsets.all(_margenTarjeta),
            child: SizedBox(
              width: _ladoTarjeta,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArtImage(url: a.art, size: _ladoTarjeta),
                  const SizedBox(height: _huecoTarjeta),
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: estilo.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtituloDe?.call(a) ?? a.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: estilo.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }
}

class TiraDePlaylists extends StatelessWidget {
  const TiraDePlaylists({
    super.key,
    required this.playlists,
    required this.onAbrir,
  });

  static const double _ladoTarjeta = 128;

  final List<Playlist> playlists;
  final void Function(Playlist) onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    return TiraHorizontal(
      alto: _altoDeTarjeta(context, estilo, lado: _ladoTarjeta, lineas: 2),
      centroDeFlechas: _margenTarjeta + _ladoTarjeta / 2,
      itemCount: playlists.length,
      itemBuilder: (context, i) {
        final pl = playlists[i];
        return Pulsable(
          child: InkWell(
            onTap: () => onAbrir(pl),
            borderRadius: BorderRadius.circular(EstiloNeoFy.de(context).radio),
            child: Padding(
              padding: const EdgeInsets.all(_margenTarjeta),
              child: SizedBox(
                width: _ladoTarjeta,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArtImage(url: pl.art, size: _ladoTarjeta),
                    const SizedBox(height: _huecoTarjeta),
                    Text(pl.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: estilo.copyWith(fontWeight: FontWeight.w600)),
                    T(
                      pl.owner.isEmpty ? 'Lista de reproducción' : pl.owner,
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
        );
      },
    );
  }
}

