import 'dart:async';

import 'package:flutter/material.dart';

import '../core/home_store.dart';
import '../core/librespot.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/temas.dart';
import 'art_image.dart';
import 'icono_de_volumen.dart';
import 'like_button.dart';
import 'linea_de_artistas.dart';
import 'onda_de_progreso.dart';
import 'titulo_desplazable.dart';

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
    this.onAbrirArtista,
  });

  final PlayerController player;
  final LibrespotManager librespot;
  final LikedStore? likes;
  final HomeStore? home;
  final void Function(Artist artista)? onAbrirArtista;

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar> {
  double? _dragMs;

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
          color: EstiloNeoFy.de(context).hayCristal
              ? Colors.transparent
              : theme.colorScheme.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != null) _StatusStrip(message: status),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    ArtImage(
                      url: track?.artSmall,
                      urlGrande: track?.artMedium,
                      size: 56,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: TituloDesplazable(
                                  texto: track?.name ?? 'Nada sonando',
                                  estilo: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (widget.likes != null &&
                                  track != null &&
                                  track.uri.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                LikeButton(
                                  likes: widget.likes!,
                                  uri: track.uri,
                                  size: 20,
                                  caja: 24,
                                ),
                              ],
                            ],
                          ),
                          LineaDeArtistas(
                            artistas: track?.listaDeArtistas ?? const [],
                            texto: track?.artists ?? '',
                            estilo: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                            onAbrir: widget.onAbrirArtista == null
                                ? null
                                : (a) => widget.onAbrirArtista!(_artistaConFoto(a)),
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
                  child: BarraDeProgreso(
                    valor: shown.clamp(0, max),
                    maximo: max,
                    enMarcha: state.isPlaying,
                    onCambio: durationMs <= 0
                        ? null
                        : (v) => setState(() => _dragMs = v),
                    onFinDelCambio: (v) {
                      setState(() => _dragMs = null);
                      player.seek(v.round());
                    },
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

  Artist _artistaConFoto(ArtistaDePista a) {
    final conocidos = widget.home?.artistas ?? const <Artist>[];
    for (final c in conocidos) {
      if (c.id == a.id) return c;
    }
    return a.comoArtista;
  }

  Widget _volume(int percent) {
    final player = widget.player;
    final muteado = player.muteado;
    final shown = _dragVolume ?? percent.toDouble().clamp(0, 100);
    return SizedBox(
      width: 150,
      child: Row(
        children: [
          IconButton(
            tooltip: muteado ? 'Activar sonido' : 'Silenciar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: IconoDeVolumen(
              volumen: shown,
              muteado: muteado,
              tamano: 20,
            ),
            onPressed: () => unawaited(player.alternarMute()),
          ),
          Expanded(
            child: Slider(
              value: shown,
              max: 100,
              onChanged: (v) {
                setState(() => _dragVolume = v);
                player.previsualizarVolumen(v.round());
              },
              onChangeEnd: (v) {
                setState(() => _dragVolume = null);
                unawaited(player.setVolume(v.round()));
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

  String? _statusMessage() {
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
