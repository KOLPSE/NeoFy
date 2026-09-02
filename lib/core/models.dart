library;

import 'idiomas_spotify.dart';

String idDeSpotify(String idOUri) {
  final i = idOUri.lastIndexOf(':');
  if (i >= 0 && i < idOUri.length - 1) return idOUri.substring(i + 1);
  return idOUri;
}

String? pickImage(List<dynamic>? images, int minSize) {
  if (images == null || images.isEmpty) return null;
  Map<String, dynamic>? best;
  for (final raw in images) {
    final img = raw as Map<String, dynamic>;
    final w = (img['width'] as num?)?.toInt() ?? 0;
    if (w >= minSize && (best == null || w < ((best['width'] as num?)?.toInt() ?? 1 << 30))) {
      best = img;
    }
  }
  best ??= images.first as Map<String, dynamic>;
  return best['url'] as String?;
}

String? pickLargestImage(List<dynamic>? images) {
  if (images == null || images.isEmpty) return null;
  Map<String, dynamic>? best;
  for (final raw in images) {
    final img = raw as Map<String, dynamic>;
    final w = (img['width'] as num?)?.toInt() ?? 0;
    if (best == null || w > ((best['width'] as num?)?.toInt() ?? 0)) {
      best = img;
    }
  }
  return best?['url'] as String?;
}

/// Biografía tal como llega de librespot/Rovi: un bloque, a veces con
/// atribución al final (~ Autor, Rovi).
class BiografiaFormateada {
  const BiografiaFormateada({required this.parrafos, this.atribucion});

  final List<String> parrafos;
  final String? atribucion;
}

/// Spotify manda varias biografías sin locale; elige la que encaja con el idioma.
String elegirBiografia(Iterable<String> bios, {String? locale}) {
  final candidatas = [
    for (final b in bios)
      if (b.trim().isNotEmpty) b.trim(),
  ];
  if (candidatas.isEmpty) return '';
  if (candidatas.length == 1) return candidatas.first;

  final idioma = locale != null && locale.contains('_')
      ? codigoIdiomaDeLocale(locale)
      : codigoIdiomaDelSistema(locale: locale);
  var mejor = candidatas.first;
  var mejorPuntaje = -999999;
  for (final bio in candidatas) {
    final puntaje = puntajeBiografia(bio, idioma);
    if (puntaje > mejorPuntaje) {
      mejorPuntaje = puntaje;
      mejor = bio;
    }
  }
  return mejor;
}

int puntajeBiografia(String texto, String idioma) {
  final t = ' ${texto.toLowerCase()} ';
  var puntaje = 0;

  if (RegExp(r'[ñ¿¡]').hasMatch(t)) puntaje += 8;

  void sumar(List<String> marcadores, int valor) {
    for (final m in marcadores) {
      if (t.contains(m)) puntaje += valor;
    }
  }

  switch (idioma) {
    case 'es':
      sumar(const [
        ' de la ',
        ' de los ',
        ' de las ',
        ' en el ',
        ' en la ',
        ' es un ',
        ' es una ',
        ' cantante ',
        ' músico ',
        ' nació ',
        ' español',
        ' española',
        ' también ',
        ' carrera ',
        ' álbum ',
        ' canción ',
        ' grupo ',
      ], 2);
      sumar(const [
        ' the ',
        ' and ',
        ' with ',
        ' known as ',
        ' his ',
        ' her ',
        ' after ',
        ' before ',
        ' singer/',
        ' proved ',
      ], -3);
    case 'en':
      sumar(const [
        ' the ',
        ' and ',
        ' with ',
        ' known as ',
        ' his ',
        ' her ',
        ' after ',
        ' before ',
        ' singer',
        ' band ',
      ], 2);
      sumar(const [
        ' de la ',
        ' es un ',
        ' cantante ',
        ' nació ',
        ' también ',
        ' álbum ',
      ], -3);
    case 'pt':
      sumar(const [
        ' de ',
        ' da ',
        ' do ',
        ' cantor ',
        ' cantora ',
        ' músico ',
        ' também ',
        ' álbum ',
        ' nasceu ',
      ], 2);
      sumar(const [' the ', ' and ', ' with ', ' known as '], -3);
    case 'fr':
      sumar(const [
        ' de ',
        ' des ',
        ' le ',
        ' la ',
        ' chanteur ',
        ' chanteuse ',
        ' est un ',
        ' est une ',
        ' aussi ',
        ' album ',
      ], 2);
      sumar(const [' the ', ' and ', ' with ', ' known as '], -3);
    case 'de':
      sumar(const [
        ' der ',
        ' die ',
        ' das ',
        ' und ',
        ' ist ein ',
        ' ist eine ',
        ' sänger',
        ' auch ',
        ' album ',
      ], 2);
      sumar(const [' the ', ' and ', ' with ', ' known as '], -3);
    case 'it':
      sumar(const [
        ' di ',
        ' del ',
        ' della ',
        ' cantante ',
        ' musicista ',
        ' è un ',
        ' è una ',
        ' anche ',
        ' album ',
      ], 2);
      sumar(const [' the ', ' and ', ' with ', ' known as '], -3);
    default:
      sumar(const [' the ', ' and ', ' with '], 1);
  }

  return puntaje;
}

BiografiaFormateada formatearBiografia(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return const BiografiaFormateada(parrafos: []);

  t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
  t = t.replaceAll(RegExp(r'&nbsp;|&#160;'), ' ');
  t = t.replaceAll(RegExp(r'&amp;'), '&');
  t = t.replaceAll(RegExp(r'&quot;'), '"');
  t = t.replaceAll(RegExp(r'&#39;|&apos;'), "'");
  t = t.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  t = t.replaceAll(RegExp(r'\n[ \t]+'), '\n');

  String? atribucion;
  final fin = RegExp(r'\s*[~—–-]\s*([^~—]+)$').firstMatch(t);
  if (fin != null) {
    atribucion = fin.group(1)?.trim();
    t = t.substring(0, fin.start).trim();
  }

  var parrafos = t
      .split(RegExp(r'\n\s*\n+'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList();

  if (parrafos.length <= 1) {
    if (t.contains(' -- ')) {
      parrafos = t
          .split(' -- ')
          .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((p) => p.isNotEmpty)
          .toList();
    } else if (t.length > 180) {
      final oraciones = t
          .split(RegExp(r'(?<=[.!?])\s+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      parrafos = <String>[];
      final buf = StringBuffer();
      for (var i = 0; i < oraciones.length; i++) {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(oraciones[i]);
        if (i.isOdd || i == oraciones.length - 1) {
          parrafos.add(buf.toString().trim());
          buf.clear();
        }
      }
    } else if (t.isNotEmpty) {
      parrafos = [t.replaceAll(RegExp(r'\s+'), ' ').trim()];
    }
  }

  return BiografiaFormateada(parrafos: parrafos, atribucion: atribucion);
}

String? anioDeFecha(String? fecha) {
  if (fecha == null || fecha.length < 4) return null;
  final anio = fecha.substring(0, 4);
  return RegExp(r'^\d{4}$').hasMatch(anio) ? anio : null;
}

String formatearCuenta(int n) {
  if (n >= 1000000) return '${_unaDecimal(n / 1000000)} M';
  if (n >= 10000) return '${_unaDecimal(n / 1000)} mil';
  return '$n';
}

String _unaDecimal(double n) {
  final redondeado = (n * 10).round() / 10;
  if (redondeado == redondeado.roundToDouble()) {
    return redondeado.round().toString();
  }
  return redondeado.toStringAsFixed(1).replaceAll('.', ',');
}

class ApiPage<T> {
  final List<T> items;
  final bool hasMore;
  final int rawCount;

  final int? total;

  const ApiPage({
    required this.items,
    required this.hasMore,
    required this.rawCount,
    this.total,
  });

  const ApiPage.empty()
      : items = const [],
        hasMore = false,
        rawCount = 0,
        total = 0;
}

class SearchResults {
  final ApiPage<Track> tracks;
  final ApiPage<Playlist> playlists;
  final ApiPage<Artist> artists;

  const SearchResults({
    this.tracks = const ApiPage.empty(),
    this.playlists = const ApiPage.empty(),
    this.artists = const ApiPage.empty(),
  });

  const SearchResults.empty()
      : tracks = const ApiPage.empty(),
        playlists = const ApiPage.empty(),
        artists = const ApiPage.empty();
}

class ArtistaDePista {
  const ArtistaDePista({
    required this.id,
    required this.uri,
    required this.name,
  });

  final String id;
  final String uri;
  final String name;

  bool get sePuedeAbrir => id.isNotEmpty;

  Artist get comoArtista => Artist(
        id: id,
        uri: uri.isNotEmpty ? uri : 'spotify:artist:$id',
        name: name,
        art: null,
      );

  Map<String, dynamic> aJson() => {
        'id': id,
        'uri': uri,
        'name': name,
      };

  static ArtistaDePista? desdeJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final id = (j['id'] as String?) ?? '';
    final nombre = (j['name'] as String?) ?? '';
    if (id.isEmpty && nombre.isEmpty) return null;
    final uri = (j['uri'] as String?) ?? '';
    return ArtistaDePista(
      id: id,
      uri: uri.isNotEmpty
          ? uri
          : (id.isEmpty ? '' : 'spotify:artist:$id'),
      name: nombre,
    );
  }
}

class Track {
  final String id;
  final String uri;
  final String name;
  final String artists;
  final List<ArtistaDePista> listaDeArtistas;
  final String album;
  final String? artSmall;
  final String? artMedium;
  final int durationMs;
  final bool isLocal;
  final int popularity;

  const Track({
    required this.id,
    required this.uri,
    required this.name,
    required this.artists,
    required this.album,
    required this.artSmall,
    required this.artMedium,
    required this.durationMs,
    required this.isLocal,
    this.popularity = 0,
    this.listaDeArtistas = const [],
  });

  Track copyWith({
    String? id,
    String? uri,
    String? name,
    String? artists,
    List<ArtistaDePista>? listaDeArtistas,
    String? album,
    String? artSmall,
    String? artMedium,
    int? durationMs,
    bool? isLocal,
    int? popularity,
  }) =>
      Track(
        id: id ?? this.id,
        uri: uri ?? this.uri,
        name: name ?? this.name,
        artists: artists ?? this.artists,
        listaDeArtistas: listaDeArtistas ?? this.listaDeArtistas,
        album: album ?? this.album,
        artSmall: artSmall ?? this.artSmall,
        artMedium: artMedium ?? this.artMedium,
        durationMs: durationMs ?? this.durationMs,
        isLocal: isLocal ?? this.isLocal,
        popularity: popularity ?? this.popularity,
      );

  Map<String, dynamic> aLocal() => {
        'id': id,
        'uri': uri,
        'name': name,
        'artists': artists,
        'listaDeArtistas': [for (final a in listaDeArtistas) a.aJson()],
        'album': album,
        'artSmall': artSmall,
        'artMedium': artMedium,
        'durationMs': durationMs,
        'isLocal': isLocal,
        'popularity': popularity,
      };

  static Track? desdeLocal(Map<String, dynamic>? j) {
    if (j == null) return null;
    final uri = j['uri'];
    if (uri is! String || uri.isEmpty) return null;
    return Track(
      id: (j['id'] as String?) ?? '',
      uri: uri,
      name: (j['name'] as String?) ?? 'Desconocido',
      artists: (j['artists'] as String?) ?? '',
      listaDeArtistas: [
        for (final raw
            in (j['listaDeArtistas'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>) ?ArtistaDePista.desdeJson(raw),
      ],
      album: (j['album'] as String?) ?? '',
      artSmall: j['artSmall'] as String?,
      artMedium: j['artMedium'] as String?,
      durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      isLocal: (j['isLocal'] as bool?) ?? false,
      popularity: (j['popularity'] as num?)?.toInt() ?? 0,
    );
  }

  static Track? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final artistList = j['artists'] as List<dynamic>?;
    final album = j['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>?;
    final lista = <ArtistaDePista>[
      if (artistList != null)
        for (final raw in artistList)
          if (raw is Map<String, dynamic>)
            ?ArtistaDePista.desdeJson(raw),
    ];
    return Track(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Desconocido',
      artists: lista.isNotEmpty
          ? lista.map((a) => a.name).where((n) => n.isNotEmpty).join(', ')
          : '',
      listaDeArtistas: lista,
      album: (album?['name'] as String?) ?? '',
      artSmall: pickImage(images, 64),
      artMedium: pickImage(images, 300),
      durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
      isLocal: (j['is_local'] as bool?) ?? false,
      popularity: (j['popularity'] as num?)?.toInt() ?? 0,
    );
  }
}

class Playlist {
  final String id;
  final String uri;
  final String name;
  final String owner;

  final String ownerId;
  final String? art;
  final int trackCount;

  const Playlist({
    required this.id,
    required this.uri,
    required this.name,
    required this.owner,
    required this.ownerId,
    required this.art,
    required this.trackCount,
  });

  static Playlist fromJson(Map<String, dynamic> j) {
    final counts = (j['items'] ?? j['tracks']) as Map<String, dynamic>?;
    final owner = j['owner'] as Map<String, dynamic>?;
    return Playlist(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Sin nombre',
      owner: (owner?['display_name'] as String?) ?? '',
      ownerId: (owner?['id'] as String?) ?? '',
      art: pickImage(j['images'] as List<dynamic>?, 64),
      trackCount: (counts?['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class Artist {
  final String id;
  final String uri;
  final String name;
  final String? art;
  final String? artGrande;
  final int followers;
  final int popularity;
  final List<String> genres;
  final String? biografia;

  const Artist({
    required this.id,
    required this.uri,
    required this.name,
    required this.art,
    this.artGrande,
    this.followers = 0,
    this.popularity = 0,
    this.genres = const [],
    this.biografia,
  });

  Artist copyWith({
    String? id,
    String? uri,
    String? name,
    String? art,
    String? artGrande,
    int? followers,
    int? popularity,
    List<String>? genres,
    String? biografia,
  }) =>
      Artist(
        id: id ?? this.id,
        uri: uri ?? this.uri,
        name: name ?? this.name,
        art: art ?? this.art,
        artGrande: artGrande ?? this.artGrande,
        followers: followers ?? this.followers,
        popularity: popularity ?? this.popularity,
        genres: genres ?? this.genres,
        biografia: biografia ?? this.biografia,
      );

  Map<String, dynamic> aLocal() => {
        'id': id,
        'uri': uri,
        'name': name,
        'art': art,
        'artGrande': artGrande,
        'followers': followers,
        'popularity': popularity,
        'genres': genres,
        if (biografia != null && biografia!.isNotEmpty) 'biografia': biografia,
      };

  static Artist? desdeLocal(Map<String, dynamic>? j) {
    if (j == null) return null;
    final id = (j['id'] as String?) ?? '';
    final nombre = (j['name'] as String?) ?? '';
    if (id.isEmpty && nombre.isEmpty) return null;
    return Artist(
      id: id,
      uri: (j['uri'] as String?) ??
          (id.isEmpty ? '' : 'spotify:artist:$id'),
      name: nombre.isEmpty ? 'Desconocido' : nombre,
      art: j['art'] as String?,
      artGrande: j['artGrande'] as String?,
      followers: (j['followers'] as num?)?.toInt() ?? 0,
      popularity: (j['popularity'] as num?)?.toInt() ?? 0,
      genres: [
        for (final g in (j['genres'] as List<dynamic>?) ?? const [])
          if (g is String && g.isNotEmpty) g,
      ],
      biografia: j['biografia'] as String?,
    );
  }

  static Artist? fromJson(Map<String, dynamic>? j, {String? locale}) {
    if (j == null) return null;
    final images = j['images'] as List<dynamic>?;
    final seguidores = j['followers'] as Map<String, dynamic>?;
    final bio = elegirBiografia([
      for (final b in (j['biographies'] as List<dynamic>?) ?? const [])
        if (b is String) b,
      if (j['biography'] is String) j['biography'] as String,
      if (j['biografia'] is String) j['biografia'] as String,
    ], locale: locale);
    return Artist(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Desconocido',
      art: pickImage(images, 300),
      artGrande: pickLargestImage(images),
      followers: (seguidores?['total'] as num?)?.toInt() ?? 0,
      popularity: (j['popularity'] as num?)?.toInt() ?? 0,
      genres: [
        for (final g in (j['genres'] as List<dynamic>?) ?? const [])
          if (g is String && g.isNotEmpty) g,
      ],
      biografia: (bio.isNotEmpty) ? bio : null,
    );
  }
}

class Album {
  final String id;
  final String uri;
  final String name;
  final String artists;
  final List<ArtistaDePista> listaDeArtistas;
  final String? art;
  final String? releaseDate;
  final String albumGroup;
  final int totalTracks;

  const Album({
    required this.id,
    required this.uri,
    required this.name,
    required this.artists,
    this.listaDeArtistas = const [],
    required this.art,
    this.releaseDate,
    this.albumGroup = '',
    this.totalTracks = 0,
  });

  ArtistaDePista? get artistaPrincipal =>
      listaDeArtistas.isNotEmpty ? listaDeArtistas.first : null;

  String? get anio => anioDeFecha(releaseDate);

  bool get esSingle => albumGroup == 'single' || albumGroup == 'ep';

  String get lineaSecundaria {
    final a = anio;
    if (esSingle) return a == null ? 'Single' : 'Single · $a';
    return a ?? artists;
  }

  static Album? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final artistList = j['artists'] as List<dynamic>?;
    final lista = [
      for (final raw in artistList ?? const [])
        ArtistaDePista.desdeJson(raw as Map<String, dynamic>?),
    ].whereType<ArtistaDePista>().toList();
    return Album(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Desconocido',
      artists: lista.isNotEmpty
          ? lista.map((a) => a.name).join(', ')
          : (artistList == null
              ? ''
              : artistList
                  .map((a) => (a as Map)['name'] as String? ?? '')
                  .join(', ')),
      listaDeArtistas: lista,
      art: pickImage(j['images'] as List<dynamic>?, 300),
      releaseDate: j['release_date'] as String?,
      albumGroup: (j['album_group'] as String?) ??
          (j['album_type'] as String?) ??
          '',
      totalTracks: (j['total_tracks'] as num?)?.toInt() ?? 0,
    );
  }
}

class Device {
  final String id;
  final String name;
  final bool isActive;
  final int? volumePercent;

  const Device({
    required this.id,
    required this.name,
    required this.isActive,
    required this.volumePercent,
  });

  static Device fromJson(Map<String, dynamic> j) => Device(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        isActive: (j['is_active'] as bool?) ?? false,
        volumePercent: (j['volume_percent'] as num?)?.toInt(),
      );
}

enum ModoAleatorio {
  apagado,

  estandar,

  inteligente,
}

class Playback {
  final Track? track;
  final bool isPlaying;
  final int progressMs;
  final String? deviceId;
  final String? deviceName;
  final int? volumePercent;
  final bool shuffle;
  final String repeat;
  final String? contextUri;

  final bool canSkipNext;
  final bool canSkipPrevious;

  const Playback({
    required this.track,
    required this.isPlaying,
    required this.progressMs,
    required this.deviceId,
    required this.deviceName,
    required this.volumePercent,
    required this.shuffle,
    required this.repeat,
    required this.contextUri,
    this.canSkipNext = true,
    this.canSkipPrevious = true,
  });

  static const empty = Playback(
    track: null,
    isPlaying: false,
    progressMs: 0,
    deviceId: null,
    deviceName: null,
    volumePercent: null,
    shuffle: false,
    repeat: 'off',
    contextUri: null,
  );

  Playback copyWith({
    bool? isPlaying,
    int? progressMs,
    int? volumePercent,
    bool? shuffle,
    String? repeat,
  }) =>
      Playback(
        track: track,
        isPlaying: isPlaying ?? this.isPlaying,
        progressMs: progressMs ?? this.progressMs,
        deviceId: deviceId,
        deviceName: deviceName,
        volumePercent: volumePercent ?? this.volumePercent,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        contextUri: contextUri,
        canSkipNext: canSkipNext,
        canSkipPrevious: canSkipPrevious,
      );

  static Playback fromJson(Map<String, dynamic> j) {
    final device = j['device'] as Map<String, dynamic>?;
    final disallows =
        (j['actions'] as Map<String, dynamic>?)?['disallows'] as Map<String, dynamic>?;
    return Playback(
      track: Track.fromJson(j['item'] as Map<String, dynamic>?),
      isPlaying: (j['is_playing'] as bool?) ?? false,
      progressMs: (j['progress_ms'] as num?)?.toInt() ?? 0,
      deviceId: device?['id'] as String?,
      deviceName: device?['name'] as String?,
      volumePercent: (device?['volume_percent'] as num?)?.toInt(),
      shuffle: (j['shuffle_state'] as bool?) ?? false,
      repeat: (j['repeat_state'] as String?) ?? 'off',
      contextUri: (j['context'] as Map<String, dynamic>?)?['uri'] as String?,
      canSkipNext: disallows?['skipping_next'] != true,
      canSkipPrevious: disallows?['skipping_prev'] != true,
    );
  }
}
