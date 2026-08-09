import 'dart:async';

import 'package:flutter/material.dart';

import '../core/yt_models.dart';
import '../core/yt_music_api.dart';
import '../core/yt_player.dart';
import 'art_image.dart';
import 'yt_acciones.dart';

/// Buscador de NeoTube. Devuelve **por categorías** (canciones, listas,
/// álbumes, artistas) y no solo canciones: antes se le pedía a la API el
/// filtro de "solo canciones", así que desde aquí tampoco había forma de
/// llegar a una playlist.
class YtSearchScreen extends StatefulWidget {
  const YtSearchScreen({
    super.key,
    required this.api,
    required this.player,
    required this.acciones,
  });

  final YtMusicApi api;
  final YtPlayer player;
  final YtAcciones acciones;

  @override
  State<YtSearchScreen> createState() => _YtSearchScreenState();
}

class _YtSearchScreenState extends State<YtSearchScreen> {
  final _ctrl = TextEditingController();
  List<YtSection> _secciones = const [];
  bool _buscando = false;
  String? _error;
  bool _buscadoAlgunaVez = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _buscando = true;
      _error = null;
      _buscadoAlgunaVez = true;
    });
    try {
      final r = await widget.api.buscar(query);
      if (!mounted) return;
      setState(() => _secciones = r);
    } catch (e) {
      // La API interna no tiene documentación oficial, así que conviene ver el
      // fallo completo en consola — el mensaje en pantalla se recorta para no
      // desbordar el layout.
      debugPrint('[NeoTube buscar] fallo completo: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar canciones, listas, álbumes o artistas',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _buscando
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onSubmitted: (_) => unawaited(_buscar()),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _error!,
              // La API interna no da errores cortos y legibles — a veces es
              // una página entera. Recortado aquí; el completo va a la consola.
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        Expanded(child: _resultados(theme)),
      ],
    );
  }

  Widget _resultados(ThemeData theme) {
    if (_secciones.isEmpty) {
      return Center(
        child: Text(
          _buscadoAlgunaVez && !_buscando
              ? 'Sin resultados.'
              : 'Escribe algo y pulsa Intro.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          for (final seccion in _secciones) ...[
            if (seccion.titulo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(seccion.titulo, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
            ],
            for (final item in seccion.items) _fila(theme, item),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _fila(ThemeData theme, YtItem item) {
    final sonando = item.videoId != null && widget.player.actual?.videoId == item.videoId;
    final cargando = item.videoId != null && widget.player.resolviendo == item.videoId;
    return ListTile(
      dense: true,
      selected: sonando,
      leading: ArtImage(
        url: item.miniatura,
        size: 48,
        radius: item.tipo == YtTipo.artista ? 24 : 4,
      ),
      title: Text(item.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.subtitulo.isEmpty ? _nombreDe(item.tipo) : item.subtitulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: cargando
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(sonando ? Icons.graphic_eq : iconoDe(item.tipo),
              color: sonando ? theme.colorScheme.primary : null),
      onTap: cargando ? null : () => unawaited(widget.acciones.pulsar(context, item)),
    );
  }

  String _nombreDe(YtTipo t) => switch (t) {
        YtTipo.cancion => 'Canción',
        YtTipo.lista => 'Lista',
        YtTipo.album => 'Álbum',
        YtTipo.artista => 'Artista',
        YtTipo.desconocido => '',
      };
}
