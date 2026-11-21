import 'dart:async';

import 'package:flutter/material.dart';

import '../core/home_store.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'texto_traducido.dart';
import 'track_tile.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.api,
    required this.player,
    required this.likes,
    this.onClose,
    this.home,
  });

  final SpotifyApi api;
  final PlayerController player;
  final LikedStore likes;
  final VoidCallback? onClose;
  final HomeStore? home;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<Track> _queue = const [];
  bool _loading = true;
  String? _error;
  bool _verRecientes = false;
  int _peticion = 0;

  @override
  void initState() {
    super.initState();
    _lastTrackUri = widget.player.state.track?.uri;
    unawaited(_load());
    widget.player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  String? _lastTrackUri;

  void _onPlayerChanged() {
    final uri = widget.player.state.track?.uri;
    if (uri != _lastTrackUri) {
      _lastTrackUri = uri;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final peticion = ++_peticion;
    try {
      final q = await widget.api.queue();
      if (!mounted || peticion != _peticion) return;
      setState(() {
        _queue = q;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted && peticion == _peticion) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Widget _recientes(HomeStore home) => AnimatedBuilder(
    animation: home,
    builder: (context, _) {
      if (home.recientes.isEmpty) {
        return const Center(child: T('Aún no hay escuchas recientes.'));
      }
      return ListView.builder(
        itemCount: home.recientes.length,
        itemBuilder: (context, index) {
          final track = home.recientes[index];
          return TrackTile(
            track: track,
            actions: TrackActions(
              onPlay: () => widget.player.playTrack(track.uri),
            ),
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.player.state.track;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              T('Cola', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Cerrar cola',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        if (widget.home != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              selected: {_verRecientes},
              onSelectionChanged: (seleccion) {
                setState(() => _verRecientes = seleccion.single);
                if (_verRecientes) unawaited(widget.home!.cargar());
              },
              segments: const [
                ButtonSegment(value: false, label: T('A continuación')),
                ButtonSegment(value: true, label: T('Recientes')),
              ],
            ),
          ),
        if (!_verRecientes && current != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: T(
              'SONANDO AHORA',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TrackTile(
            track: current,
            likes: current.isEpisode ? null : widget.likes,
            isCurrent: true,
            actions: const TrackActions(),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: T(
              'A CONTINUACIÓN',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        Expanded(
          child: _verRecientes && widget.home != null
              ? _recientes(widget.home!)
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                )
              : _queue.isEmpty
              ? Center(
                  child: T(
                    'La cola está vacía.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _queue.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: _queue[i],
                    likes: _queue[i].isEpisode ? null : widget.likes,
                    leadingNumber: i + 1,
                    actions: TrackActions(
                      onPlay: () => widget.player.playTrack(_queue[i].uri),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
