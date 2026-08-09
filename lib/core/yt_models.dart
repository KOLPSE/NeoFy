/// Modelos de NeoTube. Mínimos a propósito, igual que los de Spotify
/// (`models.dart`): solo los campos que la interfaz pinta o que hacen falta
/// para reproducir.
library;

/// Qué es una tarjeta de un carrusel o una fila de la biblioteca.
///
/// La API interna mete en el mismo sitio cosas que se comportan de forma muy
/// distinta, y **distinguirlas es lo que hacía falta para poder reproducir
/// listas**: una canción se reproduce por `videoId`, una lista por
/// `playlistId` (hay que pedir sus pistas primero), un álbum por su
/// `browseId` (`MPREb_…`, que ni siquiera es un `playlistId`) y un artista no
/// se reproduce en absoluto. Antes todo se aplanaba a "pista sin videoId" y
/// por eso las listas solo se podían mirar.
enum YtTipo { cancion, lista, album, artista, desconocido }

/// Una pista concreta y reproducible: la unidad de la cola de [YtPlayer].
class YtTrack {
  const YtTrack({
    required this.videoId,
    required this.titulo,
    required this.artista,
    this.miniatura,
    this.duracion,
  });

  final String videoId;
  final String titulo;
  final String artista;
  final String? miniatura;

  /// Solo cuando la API la da (las filas de una lista traen `fixedColumns`
  /// con el `mm:ss`; las tarjetas de la portada, no).
  final Duration? duracion;

  @override
  bool operator ==(Object other) => other is YtTrack && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

/// Un elemento de una fila de portada/explorar/biblioteca: puede ser una
/// canción suelta, una lista, un álbum o un artista.
class YtItem {
  const YtItem({
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
    this.videoId,
    this.playlistId,
    this.browseId,
    this.miniatura,
    this.duracion,
  });

  final YtTipo tipo;
  final String titulo;
  final String subtitulo;

  /// Presente en las canciones sueltas.
  final String? videoId;

  /// Sin el prefijo `VL`: el que hay que pasar a `browse`/`next`. Las mezclas
  /// y radios de la portada empiezan por `RD`, las listas de verdad por `PL`
  /// o `VLPL`, y "Tu Me gusta" es `LM`.
  final String? playlistId;

  /// `MPREb_…` en los álbumes, `UC…` en los artistas.
  final String? browseId;

  final String? miniatura;
  final Duration? duracion;

  bool get esCancion => tipo == YtTipo.cancion && videoId != null;

  /// ¿Lleva a algún sitio? La biblioteca cuela como primera tarjeta el botón
  /// de "Nueva lista", que tiene título y carátula pero ningún destino:
  /// pintarlo sería una tarjeta muerta en mitad de tus playlists.
  bool get tieneDestino => videoId != null || playlistId != null || browseId != null;

  /// ¿Se puede pulsar y que suene (o que se abra algo que suena)? Un artista
  /// no: no tiene ni pistas propias ni lista que resolver.
  bool get esNavegable =>
      esCancion || playlistId != null || (tipo == YtTipo.album && browseId != null);

  YtTrack? get comoPista => esCancion
      ? YtTrack(
          videoId: videoId!,
          titulo: titulo,
          artista: subtitulo,
          miniatura: miniatura,
          duracion: duracion,
        )
      : null;
}

/// Una fila de la portada/explorar/biblioteca: su título ("Escuchado
/// recientemente", "Tus playlists"…) y lo que trae dentro.
class YtSection {
  const YtSection({required this.titulo, required this.items});

  final String titulo;
  final List<YtItem> items;
}

/// El resultado de abrir una lista o un álbum: la cabecera y sus pistas.
class YtColeccion {
  const YtColeccion({
    required this.titulo,
    required this.subtitulo,
    required this.pistas,
    this.miniatura,
  });

  final String titulo;
  final String subtitulo;
  final List<YtTrack> pistas;
  final String? miniatura;
}
