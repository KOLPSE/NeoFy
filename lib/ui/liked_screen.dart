import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/auth.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'track_tile.dart';

class LikedScreen extends StatefulWidget {
  const LikedScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.playlists,
    required this.likes,
    required this.onReauth,
  });

  final SpotifyApi api;
  final SpotifyAuth auth;
  final PlayerController player;
  final List<Playlist> playlists;
  final LikedStore likes;
  final Future<void> Function() onReauth;

  @override
  State<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends State<LikedScreen> {
  static const double _altoFila = 64;

  static const int _radioPortadas = 25;

  final _scroll = ScrollController();

  final ValueNotifier<int> _centro = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alHacerScroll);
    if (widget.auth.hasScope(kScopeLibraryRead)) {
      unawaited(widget.likes.cargarBiblioteca());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _centro.dispose();
    super.dispose();
  }

  void _alHacerScroll() {
    if (!_scroll.hasClients) return;
    final centro =
        ((_scroll.offset + _scroll.position.viewportDimension / 2) / _altoFila)
            .round();
    if ((centro - _centro.value).abs() >= 5) _centro.value = centro;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _addToPlaylist(Track track) async {
    final pl = await pickPlaylist(context, widget.playlists);
    if (pl == null) return;
    try {
      await widget.api.addToPlaylist(pl.id, [track.uri]);
      _toast('Añadida a ${pl.name}');
    } catch (e) {
      _toast('No se pudo añadir: $e');
    }
  }

  Future<void> _play({int? offset}) async {
    final userId = widget.player.currentUserId;
    if (userId == null) {
      _toast('Todavía no sé el id de tu cuenta; espera un momento.');
      return;
    }
    await widget.player
        .playContext(SpotifyApi.likedContextUri(userId), offset: offset);
  }

  String _textoProgreso(LikedStore likes) {
    if (likes.biblioteca.isEmpty) {
      return likes.cargandoBiblioteca ? 'Cargando…' : 'Tu biblioteca guardada';
    }
    if (!likes.cargandoBiblioteca) return '${likes.biblioteca.length} canciones';
    final total = likes.totalBiblioteca;
    return total == null
        ? 'Cargando… ${likes.biblioteca.length}'
        : 'Cargando… ${likes.biblioteca.length} de $total';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.auth.hasScope(kScopeLibraryRead)) return _reauthNotice(theme);

    return AnimatedBuilder(
      animation: widget.likes,
      builder: (context, _) {
        final likes = widget.likes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                    ),
                    child: const Icon(Icons.favorite, color: Colors.white, size: 40),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Canciones que te gustan',
                            style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          _textoProgreso(likes),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: () => _play(),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Reproducir'),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Volver a cargar la biblioteca',
                              icon: const Icon(Icons.refresh),
                              onPressed: likes.cargandoBiblioteca
                                  ? null
                                  : () => unawaited(
                                      likes.cargarBiblioteca(forzar: true)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (likes.cargandoBiblioteca)
              LinearProgressIndicator(
                minHeight: 2,
                value: (likes.totalBiblioteca ?? 0) > 0
                    ? (likes.biblioteca.length / likes.totalBiblioteca!)
                        .clamp(0.0, 1.0)
                    : null,
              )
            else
              const Divider(height: 1),
            Expanded(
              child: likes.errorBiblioteca != null && likes.biblioteca.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(likes.errorBiblioteca!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    )
                  : _lista(likes),
            ),
          ],
        );
      },
    );
  }

  Widget _lista(LikedStore likes) {
    return ValueListenableBuilder<String?>(
      valueListenable: widget.player.currentUri,
      builder: (context, currentUri, _) => ListView.builder(
        controller: _scroll,
        itemExtent: _altoFila,
        itemCount: likes.biblioteca.length,
        itemBuilder: (context, i) {
          final t = likes.biblioteca[i];
          final tile = TrackActions(
            onPlay: () => _play(offset: i),
            onQueue: () async {
              await widget.player.addToQueue(t.uri);
              _toast('Añadida a la cola');
            },
            onAddToPlaylist: () => _addToPlaylist(t),
          );
          return ValueListenableBuilder<int>(
            valueListenable: _centro,
            builder: (context, centro, _) => TrackTile(
              track: t,
              likes: likes,
              leadingNumber: i + 1,
              isCurrent: currentUri != null && currentUri == t.uri,
              showArt: (i - centro).abs() <= _radioPortadas,
              actions: tile,
            ),
          );
        },
      ),
    );
  }

  Widget _reauthNotice(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Hace falta un permiso más', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tus canciones guardadas no son una playlist: van por otro sitio de '
                'la API y necesitan el permiso «user-library-read», que tu sesión '
                'actual no incluye.\n\n'
                'Un inicio de sesión antiguo no gana permisos al renovarse, así que '
                'hay que volver a pasar por la pantalla de Spotify una vez. No '
                'perderás nada.',
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
