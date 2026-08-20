import 'dart:async';

import 'package:flutter/material.dart';

import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'track_tile.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.api,
    required this.player,
    required this.likes,
  });

  final SpotifyApi api;
  final PlayerController player;
  final LikedStore likes;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<Track> _queue = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    try {
      final q = await widget.api.queue();
      if (!mounted) return;
      setState(() {
        _queue = q;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

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
              Text('Cola', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
        ),
        if (current != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('SONANDO AHORA',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          TrackTile(
            track: current,
            likes: widget.likes,
            isCurrent: true,
            actions: const TrackActions(),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('A CONTINUACIÓN',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    )
                  : _queue.isEmpty
                      ? Center(
                          child: Text('La cola está vacía.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        )
                      : ListView.builder(
                          itemCount: _queue.length,
                          itemBuilder: (context, i) => TrackTile(
                            track: _queue[i],
                            likes: widget.likes,
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
