import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:http/http.dart' as http;

import '../core/app_config.dart' show kLimiteDesfaseLetraMs;
import '../core/models.dart';
import '../core/player_state.dart';
import 'art_image.dart';
import 'letra_sincronizada.dart';
import 'now_playing_bar.dart' show formatMs;
import 'texto_traducido.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.track,
    required this.player,
    required this.onClose,
  });

  final Track track;
  final PlayerController player;
  final VoidCallback onClose;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView>
    with SingleTickerProviderStateMixin {
  late Future<_Lyrics?> _request;
  final _client = http.Client();
  final _activeLine = GlobalKey();
  final _tiempo = ValueNotifier<int>(0);
  final _indice = ValueNotifier<int>(-1);
  late final Ticker _latido = createTicker((_) => _sincronizarTiempo());
  var _lineas = const <LineaDeLetra>[];
  late int _desfaseGuardado;
  late int _desfaseMs;
  bool _ajustando = false;
  bool _guardando = false;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _desfaseGuardado =
        widget.player.config.desfasesLetraMs[widget.track.uri] ?? 0;
    _desfaseMs = _desfaseGuardado;
    widget.player.progressMs.addListener(_sincronizarTiempo);
    widget.player.addListener(_actualizarLatido);
    _request = _load();
  }

  @override
  void dispose() {
    widget.player.progressMs.removeListener(_sincronizarTiempo);
    widget.player.removeListener(_actualizarLatido);
    _latido.dispose();
    _tiempo.dispose();
    _indice.dispose();
    _client.close();
    super.dispose();
  }

  void _sincronizarTiempo() {
    if (widget.player.state.track?.uri != widget.track.uri) return;
    _mostrarTiempo(widget.player.posicionActualMs + _desfaseMs);
  }

  void _actualizarLatido() {
    final animar = _lineas.isNotEmpty && widget.player.state.isPlaying;
    if (animar == _latido.isActive) return;
    _sincronizarTiempo();
    if (animar) {
      _latido.start();
    } else {
      _latido.stop();
    }
  }

  void _mostrarTiempo(int ms) {
    _tiempo.value = ms;
    final actual = _lineas.lastIndexWhere((linea) => linea.inicioMs <= ms);
    if (actual != _indice.value) {
      _indice.value = actual;
      _centerLine();
    }
  }

  int _posicionParaLinea(LineaDeLetra linea) =>
      (linea.inicioMs - _desfaseMs).clamp(0, widget.track.durationMs);

  void _previsualizarDesfase(int ms) {
    setState(() {
      _desfaseMs = ms.clamp(-kLimiteDesfaseLetraMs, kLimiteDesfaseLetraMs);
    });
    _sincronizarTiempo();
  }

  Future<void> _guardarDesfase() async {
    if (_desfaseMs == _desfaseGuardado) {
      setState(() => _ajustando = false);
      return;
    }
    setState(() => _guardando = true);
    final uri = widget.track.uri;
    final config = widget.player.config;
    final antes = config.desfasesLetraMs[uri];
    if (_desfaseMs == 0) {
      config.desfasesLetraMs.remove(uri);
    } else {
      config.desfasesLetraMs[uri] = _desfaseMs;
    }
    try {
      await config.save();
      if (!mounted) return;
      setState(() {
        _desfaseGuardado = _desfaseMs;
        _ajustando = false;
      });
    } catch (_) {
      if (antes == null) {
        config.desfasesLetraMs.remove(uri);
      } else {
        config.desfasesLetraMs[uri] = antes;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('No se pudo guardar la sincronización.')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<dynamic> _pedir(String path, Map<String, String> query) async {
    final resp = await _client
        .get(
          Uri.https('lrclib.net', path, query),
          headers: const {'User-Agent': 'NeoFy (desktop music player)'},
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw StateError('LRCLIB HTTP ${resp.statusCode}');
    }

    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<_Lyrics?> _load() async {
    final track = widget.track;
    final artista = track.listaDeArtistas.firstOrNull?.name ?? track.artists;
    final duracion = (track.durationMs / 1000).round();
    final campos = {'track_name': track.name, 'artist_name': artista};
    var data =
        await _pedir('/api/get-cached', {
              ...campos,
              'album_name': track.album,
              'duration': '$duracion',
            })
            as Map<String, dynamic>?;
    if (data == null) {
      final candidatos = await _pedir('/api/search', campos) as List<dynamic>?;
      final tituloBuscado = _normalizar(track.name);
      final artistaBuscado = _normalizar(artista);
      final albumBuscado = _normalizar(track.album);
      final coincidentes = (candidatos ?? const [])
          .whereType<Map<String, dynamic>>()
          .where(
            (item) =>
                _normalizar(item['trackName']) == tituloBuscado &&
                _normalizar(item['artistName']) == artistaBuscado &&
                item['duration'] is num &&
                ((item['duration'] as num) - duracion).abs() <= 3,
          )
          .toList();
      data =
          coincidentes
              .where(
                (item) =>
                    _normalizar(item['albumName']) == albumBuscado &&
                    item['hasWordSync'] == true,
              )
              .firstOrNull ??
          coincidentes
              .where(
                (item) =>
                    _normalizar(item['albumName']) == albumBuscado &&
                    (item['syncedLyrics'] as String?)?.isNotEmpty == true,
              )
              .firstOrNull ??
          coincidentes.firstOrNull;
    }
    if (data == null) return null;
    if (data['instrumental'] == true) {
      return const _Lyrics([], '', instrumental: true);
    }
    final lines = LineaDeLetra.leer(data, track.durationMs);
    final plain = data['plainLyrics'] as String? ?? '';
    if (lines.isEmpty && plain.trim().isEmpty) return null;
    if (mounted) {
      _lineas = lines;
      _sincronizarTiempo();
      _actualizarLatido();
    }
    return _Lyrics(lines, plain);
  }

  String _normalizar(Object? texto) => (texto as String? ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  void _centerLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _activeLine.currentContext;
      if (!mounted || !_follow || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: .35,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.surface, colors.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
            child: Row(
              children: [
                ArtImage(url: widget.track.artSmall, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const T('Letra'),
                      Text(
                        widget.track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                if (!_follow)
                  TextButton(
                    onPressed: () {
                      setState(() => _follow = true);
                      _centerLine();
                    },
                    child: const T('Seguir letra'),
                  ),
                FutureBuilder<_Lyrics?>(
                  future: _request,
                  builder: (context, snapshot) {
                    if (snapshot.data?.lines.isNotEmpty != true) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      tooltip: 'Ajustar sincronización',
                      isSelected: _ajustando,
                      icon: const Icon(Icons.sync_alt_rounded),
                      onPressed: _guardando
                          ? null
                          : () {
                              if (_ajustando) {
                                _previsualizarDesfase(_desfaseGuardado);
                              }
                              setState(() => _ajustando = !_ajustando);
                            },
                    );
                  },
                ),
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Cerrar letra',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_ajustando) _panelDeSincronizacion(),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<_Lyrics?>(
              future: _request,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const T('No se pudo conectar con LRCLIB.'),
                        TextButton(
                          onPressed: () => setState(() => _request = _load()),
                          child: const T('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }
                final lyrics = snapshot.data;
                if (lyrics == null) {
                  return const Center(
                    child: T('No hay letra disponible en LRCLIB.'),
                  );
                }
                if (lyrics.instrumental) {
                  return const Center(child: T('Pista instrumental'));
                }
                return lyrics.lines.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          lyrics.plain,
                          style: theme.textTheme.titleLarge,
                        ),
                      )
                    : _synced(lyrics);
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Text('LRCLIB'),
          ),
        ],
      ),
    );
  }

  Widget _panelDeSincronizacion() {
    final signo = _desfaseMs > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const T('Sincronización de esta canción'),
          Row(
            children: [
              IconButton(
                tooltip: 'Retrasar la letra 100 ms',
                icon: const Icon(Icons.remove),
                onPressed: _guardando || _desfaseMs <= -kLimiteDesfaseLetraMs
                    ? null
                    : () => _previsualizarDesfase(_desfaseMs - 100),
              ),
              Expanded(
                child: Slider(
                  value: _desfaseMs.toDouble(),
                  min: -kLimiteDesfaseLetraMs.toDouble(),
                  max: kLimiteDesfaseLetraMs.toDouble(),
                  divisions: 2 * kLimiteDesfaseLetraMs ~/ 100,
                  label: '$signo$_desfaseMs ms',
                  semanticFormatterCallback: (ms) => ms > 0
                      ? 'Adelantar ${ms.round()} milisegundos'
                      : ms < 0
                      ? 'Retrasar ${ms.abs().round()} milisegundos'
                      : 'Sin desplazamiento',
                  onChanged: _guardando
                      ? null
                      : (ms) => _previsualizarDesfase(ms.round()),
                ),
              ),
              IconButton(
                tooltip: 'Adelantar la letra 100 ms',
                icon: const Icon(Icons.add),
                onPressed: _guardando || _desfaseMs >= kLimiteDesfaseLetraMs
                    ? null
                    : () => _previsualizarDesfase(_desfaseMs + 100),
              ),
              SizedBox(
                width: 80,
                child: Text('$signo$_desfaseMs ms', textAlign: TextAlign.end),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _guardando || _desfaseMs == 0
                      ? null
                      : () => _previsualizarDesfase(0),
                  child: const T('Restablecer'),
                ),
                FilledButton(
                  onPressed: _guardando ? null : _guardarDesfase,
                  child: const T('Guardar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _synced(_Lyrics lyrics) {
    final theme = Theme.of(context);
    final lineStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return ValueListenableBuilder<int>(
      valueListenable: _indice,
      builder: (context, index, _) {
        return NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (_follow && notification.direction != ScrollDirection.idle) {
              setState(() => _follow = false);
            }
            return false;
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 38, 18, 180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in lyrics.lines.indexed)
                  Padding(
                    key: index == i ? _activeLine : ValueKey(i),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton(
                      onPressed: () =>
                          widget.player.seek(_posicionParaLinea(line)),
                      style: TextButton.styleFrom(
                        backgroundColor: index == i
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: .52,
                              )
                            : null,
                        foregroundColor: index == i
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(formatMs(_posicionParaLinea(line))),
                          ),
                          Expanded(
                            child: i == index && line.texto.isNotEmpty
                                ? _pintarKaraoke(line, lineStyle)
                                : Text(
                                    line.texto.isEmpty ? '♪' : line.texto,
                                    style: lineStyle,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pintarKaraoke(LineaDeLetra linea, TextStyle? estilo) {
    final colores = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: _tiempo,
      builder: (context, ms, _) {
        final texto = linea.en(ms);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: texto.anterior,
                style: TextStyle(color: colores.primary),
              ),
              TextSpan(
                text: texto.actual,
                style: TextStyle(
                  color: colores.onSurface,
                  shadows: [Shadow(color: colores.primary, blurRadius: 9)],
                ),
              ),
              TextSpan(text: texto.siguiente),
            ],
          ),
          style: estilo?.copyWith(color: colores.onSurfaceVariant),
          semanticsLabel: linea.texto,
        );
      },
    );
  }
}

class _Lyrics {
  const _Lyrics(this.lines, this.plain, {this.instrumental = false});

  final List<LineaDeLetra> lines;
  final String plain;
  final bool instrumental;
}
