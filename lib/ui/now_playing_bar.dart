import 'dart:async';

import 'package:flutter/material.dart';

import '../core/home_store.dart';
import '../core/librespot.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/temas.dart';
import 'art_image.dart';
import 'botones_transporte.dart';
import 'icono_de_volumen.dart';
import 'like_button.dart';
import 'linea_de_artistas.dart';
import 'onda_de_progreso.dart';
import 'titulo_desplazable.dart';
import 'texto_traducido.dart';

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
    this.onCola,
    this.onLetra,
    this.colaAbierta = false,
    this.letraAbierta = false,
  });

  final PlayerController player;
  final LibrespotManager librespot;
  final LikedStore? likes;
  final HomeStore? home;
  final void Function(Artist artista)? onAbrirArtista;
  final VoidCallback? onCola;
  final VoidCallback? onLetra;
  final bool colaAbierta;
  final bool letraAbierta;

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar> {
  final ValueNotifier<double?> _dragMs = ValueNotifier(null);
  final ValueNotifier<double?> _dragVolume = ValueNotifier(null);
  late Listenable _escucha;

  bool _cuotaIgnorada = false;

  @override
  void initState() {
    super.initState();
    _escucha = Listenable.merge([widget.player, widget.librespot]);
  }

  @override
  void didUpdateWidget(covariant NowPlayingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player ||
        oldWidget.librespot != widget.librespot) {
      _escucha = Listenable.merge([widget.player, widget.librespot]);
    }
  }

  @override
  void dispose() {
    _dragMs.dispose();
    _dragVolume.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _escucha,
      builder: (context, _) {
        final theme = Theme.of(context);
        final estilo = EstiloNeoFy.de(context);
        final nocturno = estilo.usaInterfazNocturna;
        final state = widget.player.state;
        final track = state.track;
        final duracion = track?.durationMs ?? 0;
        final cuota = widget.player.api.avisoDeCuota;
        if (cuota == null) _cuotaIgnorada = false;
        final status = _statusMessage(cuota);
        final sePuedeIgnorar = cuota != null && status?.mensaje == cuota;

        return Material(
          color: estilo.hayCristal
              ? Colors.transparent
              : nocturno
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != null)
                _StatusStrip(
                  message: status.mensaje,
                  traducir: status.traducir,
                  onIgnorar: sePuedeIgnorar
                      ? () => setState(() => _cuotaIgnorada = true)
                      : null,
                ),
              Padding(
                padding: nocturno
                    ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8)
                    : const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: nocturno
                    ? Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _pistaActual(context, track, 48),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _controles(context),
                                _progreso(context, duracion),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (widget.onLetra != null)
                                  IconButton(
                                    tooltip: 'Letra',
                                    isSelected: widget.letraAbierta,
                                    onPressed:
                                        widget.letraAbierta ||
                                            (track != null && !track.isEpisode)
                                        ? widget.onLetra
                                        : null,
                                    icon: const Icon(Icons.lyrics_outlined),
                                    selectedIcon: Icon(
                                      Icons.lyrics,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                if (widget.onCola != null)
                                  IconButton(
                                    tooltip: 'Cola',
                                    isSelected: widget.colaAbierta,
                                    onPressed: widget.onCola,
                                    icon: const Icon(
                                      Icons.queue_music_outlined,
                                    ),
                                    selectedIcon: Icon(
                                      Icons.queue_music,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                Flexible(
                                  child: _volume(
                                    widget.player.volumeShown,
                                    compacto: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: 268,
                            child: _pistaActual(context, track, 56),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _controles(context),
                                _progreso(context, duracion),
                              ],
                            ),
                          ),
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

  Widget _pistaActual(BuildContext context, Track? track, double lado) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ArtImage(url: track?.artSmall, urlGrande: track?.artMedium, size: lado),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: track == null
                        ? T(
                            'Nada sonando',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : TituloDesplazable(
                            texto: track.name,
                            estilo: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  if (widget.likes != null &&
                      track != null &&
                      !track.isEpisode &&
                      track.uri.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    LikeButton(
                      likes: widget.likes!,
                      uri: track.uri,
                      pista: track,
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
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onAbrir: widget.onAbrirArtista == null
                    ? null
                    : (a) => widget.onAbrirArtista!(_artistaConFoto(a)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controles(BuildContext context) {
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: shuffleTooltip,
          icon: Icon(shuffleIcon, size: 20),
          color: shuffleColor,
          onPressed: () => player.ciclarModoAleatorio(
            likes: widget.likes,
            home: widget.home,
          ),
        ),
        BotonSaltoExpresivo(
          tooltip: 'Anterior',
          icono: Icons.skip_previous,
          direccion: -1,
          onPressed: player.previous,
        ),
        BotonPlayExpresivo(
          tooltip: state.isPlaying ? 'Pausar' : 'Reproducir',
          sonando: state.isPlaying,
          onPressed: player.togglePlay,
        ),
        BotonSaltoExpresivo(
          tooltip: 'Siguiente',
          icono: Icons.skip_next,
          direccion: 1,
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
    );
  }

  Widget _progreso(BuildContext context, int durationMs) {
    final player = widget.player;
    final state = player.state;
    final tema = Theme.of(context);
    final tiempo = tema.textTheme.bodySmall?.copyWith(
      color: tema.colorScheme.onSurfaceVariant,
    );
    return ValueListenableBuilder<int>(
      valueListenable: player.progressMs,
      builder: (context, progress, _) => ValueListenableBuilder<double?>(
        valueListenable: _dragMs,
        builder: (context, dragMs, _) {
          final shown = dragMs ?? progress.toDouble();
          final max = durationMs <= 0 ? 1.0 : durationMs.toDouble();
          return Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  formatMs(shown.round()),
                  style: tiempo,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                child: BarraDeProgreso(
                  clavePista: state.track?.uri,
                  valor: shown.clamp(0, max),
                  maximo: max,
                  enMarcha: state.isPlaying,
                  onCambio: durationMs <= 0
                      ? null
                      : (v) => _dragMs.value = v,
                  onFinDelCambio: (v) {
                    _dragMs.value = null;
                    player.seek(v.round());
                  },
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(formatMs(durationMs), style: tiempo),
              ),
            ],
          );
        },
      ),
    );
  }

  Artist _artistaConFoto(ArtistaDePista a) {
    final conocidos = widget.home?.artistas ?? const <Artist>[];
    for (final c in conocidos) {
      if (c.id == a.id) return c;
    }
    return a.comoArtista;
  }

  Widget _volume(int percent, {bool compacto = false}) {
    final player = widget.player;
    final muteado = player.muteado;
    return ValueListenableBuilder<double?>(
      valueListenable: _dragVolume,
      builder: (context, dragVol, _) {
        final shown = dragVol ?? percent.toDouble().clamp(0, 100);
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
                    _dragVolume.value = v;
                    player.previsualizarVolumen(v.round());
                  },
                  onChangeEnd: (v) {
                    _dragVolume.value = null;
                    unawaited(player.setVolume(v.round()));
                  },
                ),
              ),
              if (!compacto)
                SizedBox(
                  width: 26,
                  child: Text(
                    '${shown.round()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  _MensajeDeEstado? _statusMessage(String? cuota) {
    if (cuota != null && !_cuotaIgnorada) {
      return _MensajeDeEstado(cuota, traducir: true);
    }
    if (widget.player.premiumChecked && !widget.player.isPremium) {
      final libre = widget.player.libre;
      if (libre != null && !libre.tieneSesionYt) {
        return const _MensajeDeEstado(
          'Sin Premium el audio suena desde YouTube Music. Conéctalo en Ajustes',
        );
      }
      return const _MensajeDeEstado(
        'Cuenta sin Premium: el audio llega desde YouTube Music.',
      );
    }
    if (widget.player.libre == null) {
      if (widget.librespot.status == LibrespotStatus.failed) {
        final err = widget.librespot.lastError;
        if (err != null) return _MensajeDeEstado(err, traducir: false);
        return const _MensajeDeEstado('El reproductor no arrancó.');
      }
      if (widget.player.ourDeviceId == null) {
        return const _MensajeDeEstado('Buscando el reproductor local…');
      }
    }
    final err = widget.player.lastError;
    if (err != null && !_esAvisoDeCuota(err)) {
      return _MensajeDeEstado(err, traducir: false);
    }
    return null;
  }
}

class _MensajeDeEstado {
  const _MensajeDeEstado(this.mensaje, {this.traducir = true});

  final String mensaje;
  final bool traducir;
}

bool _esAvisoDeCuota(String mensaje) => mensaje.contains('agotado la cuota');

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.message,
    required this.traducir,
    this.onIgnorar,
  });

  final String message;
  final bool traducir;
  final VoidCallback? onIgnorar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onErrorContainer);
    final texto = traducir
        ? T(message,
            style: estilo, maxLines: 2, overflow: TextOverflow.ellipsis)
        : Text(message,
            style: estilo, maxLines: 2, overflow: TextOverflow.ellipsis);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: EdgeInsets.fromLTRB(16, 2, onIgnorar == null ? 16 : 4, 2),
      child: Row(
        children: [
          Expanded(child: texto),
          if (onIgnorar != null)
            IconButton(
              tooltip: 'Ignorar',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              icon: Icon(
                Icons.close,
                size: 16,
                color: theme.colorScheme.onErrorContainer,
              ),
              onPressed: onIgnorar,
            ),
        ],
      ),
    );
  }
}
