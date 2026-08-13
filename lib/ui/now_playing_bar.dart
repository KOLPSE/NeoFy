import 'package:flutter/material.dart';

import '../core/home_store.dart';
import '../core/librespot.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import 'art_image.dart';
import 'like_button.dart';

String formatMs(int ms) {
  final total = (ms / 1000).round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class NowPlayingBar extends StatefulWidget {
  const NowPlayingBar({
    super.key,
    required this.player,
    required this.librespot,
    this.likes,
    this.home,
  });

  final PlayerController player;
  final LibrespotManager librespot;
  final LikedStore? likes;
  final HomeStore? home;

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar> {
  /// Posición mientras se arrastra el slider. Sin esto, el sondeo devolvería
  /// la posición vieja y el pulgar daría saltos bajo el dedo.
  double? _dragMs;

  /// Lo mismo para el volumen.
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.player, widget.librespot]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final state = widget.player.state;
        final track = state.track;
        final status = _statusMessage();

        return Material(
          color: theme.colorScheme.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != null) _StatusStrip(message: status),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    // Se le dan las dos y que elija por píxeles reales: en una
                    // pantalla al 100 % estos 56 px caben en la de 64 (4 KB),
                    // y en una HiDPI al 200 % pasa sola a la de 300.
                    ArtImage(
                      url: track?.artSmall,
                      urlGrande: track?.artMedium,
                      size: 56,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track?.name ?? 'Nada sonando',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  track?.artists ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (widget.likes != null && track != null && track.uri.isNotEmpty)
                            LikeButton(
                              likes: widget.likes!,
                              uri: track.uri,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _controlsAndProgress(context, track?.durationMs ?? 0)),
                    const SizedBox(width: 8),
                    _volume(widget.player.volumeShown),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controlsAndProgress(BuildContext context, int durationMs) {
    final player = widget.player;
    final state = player.state;
    final theme = Theme.of(context);

    final modoAleatorio = player.modoAleatorio;
    String shuffleTooltip;
    IconData shuffleIcon;
    Color? shuffleColor;

    switch (modoAleatorio) {
      case ModoAleatorio.apagado:
        shuffleTooltip = 'Aleatorio: Apagado';
        shuffleIcon = Icons.shuffle;
        shuffleColor = null;
        break;
      case ModoAleatorio.estandar:
        shuffleTooltip = 'Aleatorio';
        shuffleIcon = Icons.shuffle;
        shuffleColor = theme.colorScheme.primary;
        break;
      case ModoAleatorio.inteligente:
        shuffleTooltip = 'Aleatorio inteligente';
        shuffleIcon = Icons.auto_awesome;
        shuffleColor = theme.colorScheme.primary;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: shuffleTooltip,
              icon: Icon(shuffleIcon, size: 20),
              color: shuffleColor,
              onPressed: () =>
                  player.ciclarModoAleatorio(likes: widget.likes, home: widget.home),
            ),
            IconButton(
              tooltip: 'Anterior',
              icon: const Icon(Icons.skip_previous),
              onPressed: player.previous,
            ),
            IconButton.filled(
              tooltip: state.isPlaying ? 'Pausar' : 'Reproducir',
              icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: player.togglePlay,
            ),
            IconButton(
              tooltip: 'Siguiente',
              icon: const Icon(Icons.skip_next),
              onPressed: player.next,
            ),
            IconButton(
              tooltip: 'Repetir',
              icon: Icon(
                state.repeat == 'track' ? Icons.repeat_one : Icons.repeat,
                size: 20,
              ),
              color: state.repeat == 'off' ? null : theme.colorScheme.primary,
              onPressed: player.cycleRepeat,
            ),
          ],
        ),
        // Solo esta parte se repinta con el tick de 250 ms; el resto de la
        // barra se queda quieto hasta que cambie el estado de verdad.
        ValueListenableBuilder<int>(
          valueListenable: player.progressMs,
          builder: (context, progress, _) {
            final shown = _dragMs ?? progress.toDouble();
            final max = durationMs <= 0 ? 1.0 : durationMs.toDouble();
            return Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(formatMs(shown.round()),
                      style: theme.textTheme.bodySmall, textAlign: TextAlign.right),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: shown.clamp(0, max),
                      max: max,
                      onChanged: durationMs <= 0
                          ? null
                          : (v) => setState(() => _dragMs = v),
                      onChangeEnd: (v) {
                        setState(() => _dragMs = null);
                        player.seek(v.round());
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(formatMs(durationMs), style: theme.textTheme.bodySmall),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _volume(int percent) {
    final shown = _dragVolume ?? percent.toDouble().clamp(0, 100);
    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Icon(_iconoVolumen(shown), size: 18),
          Expanded(
            child: Slider(
              value: shown,
              max: 100,
              // ⚠️ El cambio se manda al soltar, no en cada píxel. Antes esto
              // era `onChanged: setVolume(...)`, o sea una petición a la Web
              // API por cada paso del arrastre: se saturaba, Spotify empezaba
              // a devolver 429 y el volumen acababa quedándose en un valor
              // intermedio al azar. De ahí que "se bugeara".
              onChanged: (v) => setState(() => _dragVolume = v),
              onChangeEnd: (v) {
                setState(() => _dragVolume = null);
                widget.player.setVolume(v.round());
              },
            ),
          ),
          SizedBox(
            width: 26,
            child: Text('${shown.round()}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  IconData _iconoVolumen(double v) {
    if (v <= 0) return Icons.volume_off;
    if (v < 50) return Icons.volume_down;
    return Icons.volume_up;
  }

  /// Un único sitio donde se decide qué problema merece ocupar la franja de
  /// aviso, en orden de gravedad.
  String? _statusMessage() {
    // Lo primero de todo: con la cuota agotada no funciona nada más, y saber
    // cuándo vuelve importa más que cualquier otro aviso.
    final cuota = widget.player.api.avisoDeCuota;
    if (cuota != null) return cuota;
    if (widget.player.premiumChecked && !widget.player.isPremium) {
      final libre = widget.player.libre;
      if (libre != null && !libre.tieneSesionYt) {
        return 'Sin Premium el audio lo pone YouTube Music: conéctalo en '
            'Ajustes para que suene la música.';
      }
      return 'Cuenta sin Premium: el audio lo pone YouTube.';
    }
    if (widget.player.libre == null) {
      if (widget.librespot.status == LibrespotStatus.failed) {
        return widget.librespot.lastError ?? 'El reproductor no arrancó.';
      }
      if (widget.player.ourDeviceId == null) {
        return 'Buscando el reproductor local…';
      }
    }
    final err = widget.player.lastError;
    if (err != null) return err;
    return null;
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        message,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onErrorContainer),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
