import 'dart:async';

import 'package:flutter/material.dart';

import '../core/yt_models.dart';
import '../core/yt_music_api.dart';
import '../core/yt_player.dart';

/// Qué pasa al pulsar un elemento de NeoTube, en un solo sitio.
///
/// La portada, "Explorar", la biblioteca, la búsqueda y el contenido de una
/// lista pintan **los mismos** elementos ([YtItem]), y antes cada pantalla
/// decidía por su cuenta qué hacer con un tap — que era, en todas, "si no es
/// una canción suelta, avisar de que no se puede reproducir". Centralizarlo es
/// lo que permite que una playlist se comporte igual se pulse donde se pulse.
class YtAcciones {
  const YtAcciones({
    required this.api,
    required this.player,
    required this.abrir,
  });

  final YtMusicApi api;
  final YtPlayer player;

  /// Navegar al detalle de una lista o un álbum. Lo resuelve el shell, que es
  /// quien tiene la pila de navegación.
  final void Function(YtItem) abrir;

  /// El tap normal: una canción suena; una lista o un álbum se abren.
  Future<void> pulsar(BuildContext context, YtItem item) async {
    if (item.esCancion) {
      await reproducirCancion(context, item.comoPista!);
      return;
    }
    if (item.tipo == YtTipo.artista) {
      _avisar(context, 'Las páginas de artista todavía no están.');
      return;
    }
    if (item.playlistId != null || item.browseId != null) {
      abrir(item);
      return;
    }
    _avisar(context, 'Este elemento no trae nada que abrir.');
  }

  /// Una canción suelta: suena al momento y su radio se engancha detrás en
  /// cuanto llegue, para que al acabar siga sonando música.
  Future<void> reproducirCancion(BuildContext context, YtTrack t) async {
    try {
      await player.reproducirPista(t);
    } catch (e) {
      if (context.mounted) _avisar(context, 'No se pudo reproducir: $e');
      return;
    }
    unawaited(api.radioDe(t.videoId).then((radio) {
      // Solo si sigue sonando la misma: si el usuario ya cambió de canción,
      // engancharle la radio de la anterior sería sabotear su cola.
      if (player.actual?.videoId == t.videoId) player.anexar(radio);
    }).catchError((_) {}));
  }

  /// Reproducir una lista o un álbum de principio a fin.
  Future<void> reproducirColeccion(BuildContext context, YtItem item) async {
    try {
      final c = await api.coleccion(playlistId: item.playlistId, browseId: item.browseId);
      if (c.pistas.isEmpty) {
        if (context.mounted) _avisar(context, 'Esta lista no tiene canciones que reproducir.');
        return;
      }
      await player.reproducirLista(c.pistas, contexto: item.playlistId ?? item.browseId);
    } catch (e) {
      if (context.mounted) _avisar(context, 'No se pudo reproducir la lista: $e');
    }
  }

  void _avisar(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
    );
  }
}

/// El icono que distingue de un vistazo qué es cada tarjeta: sin él, una lista
/// y una canción se ven idénticas y no hay forma de saber cuál va a sonar y
/// cuál va a abrirse.
IconData iconoDe(YtTipo tipo) => switch (tipo) {
      YtTipo.cancion => Icons.play_arrow,
      YtTipo.lista => Icons.queue_music,
      YtTipo.album => Icons.album,
      YtTipo.artista => Icons.person,
      YtTipo.desconocido => Icons.more_horiz,
    };

String formatoDuracion(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
