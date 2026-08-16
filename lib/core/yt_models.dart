library;

enum YtTipo { cancion, lista, album, artista, desconocido }

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

  final Duration? duracion;

  @override
  bool operator ==(Object other) => other is YtTrack && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

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

  final String? videoId;

  final String? playlistId;

  final String? browseId;

  final String? miniatura;
  final Duration? duracion;

  bool get esCancion => tipo == YtTipo.cancion && videoId != null;

  bool get tieneDestino => videoId != null || playlistId != null || browseId != null;

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

class YtSection {
  const YtSection({required this.titulo, required this.items});

  final String titulo;
  final List<YtItem> items;
}

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
