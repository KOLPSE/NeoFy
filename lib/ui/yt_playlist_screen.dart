import 'dart:async';

import 'package:flutter/material.dart';

import '../core/yt_models.dart';
import '../core/yt_music_api.dart';
import '../core/yt_player.dart';
import 'art_image.dart';
import 'yt_acciones.dart';

/// El contenido de una lista, un álbum o una mezcla: cabecera con carátula,
/// botón de reproducir todo y las pistas en orden.
///
/// Es la pantalla que faltaba entera. Sin ella la portada y la biblioteca
/// pintaban listas que no llevaban a ningún sitio, y de ahí que "solo se
/// pudieran reproducir canciones sueltas".
class YtPlaylistScreen extends StatefulWidget {
  const YtPlaylistScreen({
    super.key,
    required this.item,
    required this.api,
    required this.player,
    required this.onVolver,
  });

  final YtItem item;
  final YtMusicApi api;
  final YtPlayer player;
  final VoidCallback onVolver;

  @override
  State<YtPlaylistScreen> createState() => _YtPlaylistScreenState();
}

class _YtPlaylistScreenState extends State<YtPlaylistScreen> {
  YtColeccion? _coleccion;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_cargar());
  }

  @override
  void didUpdateWidget(YtPlaylistScreen old) {
    super.didUpdateWidget(old);
    if (old.item.playlistId != widget.item.playlistId ||
        old.item.browseId != widget.item.browseId) {
      unawaited(_cargar());
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final c = await widget.api.coleccion(
        playlistId: widget.item.playlistId,
        browseId: widget.item.browseId,
      );
      if (mounted) setState(() => _coleccion = c);
    } catch (e) {
      debugPrint('[NeoTube lista ${widget.item.playlistId}] $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reproducirDesde(int i) async {
    final pistas = _coleccion?.pistas;
    if (pistas == null || pistas.isEmpty) return;
    try {
      await widget.player.reproducirLista(
        pistas,
        desde: i,
        contexto: widget.item.playlistId ?? widget.item.browseId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo reproducir: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _coleccion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver',
                onPressed: widget.onVolver,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  c?.titulo.isNotEmpty == true ? c!.titulo : widget.item.titulo,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _mensaje(theme, _error!, esError: true)
                  : c == null || c.pistas.isEmpty
                      ? _mensaje(theme, 'Esta lista no tiene canciones.')
                      : _lista(theme, c),
        ),
      ],
    );
  }

  Widget _mensaje(ThemeData theme, String texto, {bool esError = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                texto,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: esError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (esError) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_cargar()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _lista(ThemeData theme, YtColeccion c) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final sonando = widget.player.actual?.videoId;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          // Uno más: la cabecera va dentro del propio scroll para que no se
          // coma la mitad de la ventana en una lista larga.
          itemCount: c.pistas.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _cabecera(theme, c);
            final t = c.pistas[i - 1];
            final activa = t.videoId == sonando;
            return ListTile(
              dense: true,
              selected: activa,
              leading: SizedBox(
                width: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.player.resolviendo == t.videoId)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else if (activa)
                      Icon(Icons.graphic_eq, size: 18, color: theme.colorScheme.primary)
                    else
                      Text('$i',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              title: Text(t.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.artista, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: t.duracion == null
                  ? null
                  : Text(formatoDuracion(t.duracion!),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              onTap: () => unawaited(_reproducirDesde(i - 1)),
            );
          },
        );
      },
    );
  }

  Widget _cabecera(ThemeData theme, YtColeccion c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArtImage(url: c.miniatura ?? widget.item.miniatura, size: 128, radius: 10),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.titulo.isEmpty ? widget.item.titulo : c.titulo,
                    style: theme.textTheme.headlineSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  c.subtitulo.isEmpty ? '${c.pistas.length} canciones' : c.subtitulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => unawaited(_reproducirDesde(0)),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Reproducir'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        final mezcla = [...c.pistas]..shuffle();
                        unawaited(widget.player.reproducirLista(
                          mezcla,
                          contexto: widget.item.playlistId ?? widget.item.browseId,
                        ));
                      },
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Aleatorio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
