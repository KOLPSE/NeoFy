/// Modelos mínimos: solo los campos que la interfaz pinta de verdad.
///
/// Deserializar la respuesta entera de Spotify a objetos ricos es la vía rápida
/// para inflar la RAM — una playlist de 5.000 canciones son 5.000 objetos, y
/// cada campo de más se multiplica por 5.000.
library;

/// Elige la imagen más pequeña que llegue al tamaño pedido.
///
/// Spotify devuelve cada carátula en 640/300/64 px. Bajarse la de 640 para
/// pintarla en una fila de 48 px es el error que más dispara la memoria, porque
/// Flutter guarda el bitmap decodificado a resolución completa.
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

/// Una página de un listado paginado de Spotify.
///
/// Se llama `ApiPage` y no `Page` porque Flutter ya exporta un `Page` desde
/// `material.dart` (el del Navigator) y los dos nombres chocan.
///
/// [hasMore] sale del campo `next` de la respuesta, que es la única señal
/// fiable: contar los elementos devueltos no vale, porque descartamos los que
/// no son pistas reproducibles y una página de 50 puede dejarnos 48. Con el
/// criterio de contar, una biblioteca larga se cortaba por la mitad.
///
/// [rawCount] son los elementos **antes** de filtrar, que es lo que hay que
/// sumarle al offset para pedir la página siguiente.
class ApiPage<T> {
  final List<T> items;
  final bool hasMore;
  final int rawCount;

  /// Total de elementos del listado completo, cuando Spotify lo informa.
  /// Sirve para poder decir "cargando 1.250 de 3.014".
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

class Track {
  final String id;
  final String uri;
  final String name;
  final String artists;
  final String album;
  final String? artSmall;
  final String? artMedium;
  final int durationMs;
  final bool isLocal;

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
  });

  static Track? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    // Los episodios de podcast no traen `artists`; se descartan porque la
    // interfaz está pensada para música.
    final artistList = j['artists'] as List<dynamic>?;
    final album = j['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>?;
    return Track(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Desconocido',
      artists: artistList == null
          ? ''
          : artistList.map((a) => (a as Map)['name'] as String? ?? '').join(', '),
      album: (album?['name'] as String?) ?? '',
      artSmall: pickImage(images, 64),
      artMedium: pickImage(images, 300),
      durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
      isLocal: (j['is_local'] as bool?) ?? false,
    );
  }
}

class Playlist {
  final String id;
  final String uri;
  final String name;
  final String owner;

  /// Id del dueño. Hace falta para distinguir "eliminar mi playlist" de
  /// "quitar de mi biblioteca la de otro": la API es la misma llamada, pero lo
  /// que hay que decirle al usuario no.
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
    // ⚠️ El objeto playlist trae el recuento en `items`, no en `tracks`: el
    // renombrado de febrero de 2026 llegó también al cuerpo de la respuesta,
    // no solo a la ruta del endpoint. Se acepta `tracks` de reserva por si
    // alguna respuesta antigua sigue usándolo.
    final counts = (j['items'] ?? j['tracks']) as Map<String, dynamic>?;
    final owner = j['owner'] as Map<String, dynamic>?;
    return Playlist(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Sin nombre',
      owner: (owner?['display_name'] as String?) ?? '',
      ownerId: (owner?['id'] as String?) ?? '',
      // Las carátulas de playlist llegan sin `width`/`height` (y en WebP), así
      // que pickImage cae en la única que hay. Es lo correcto aquí.
      art: pickImage(j['images'] as List<dynamic>?, 64),
      trackCount: (counts?['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Un artista, con lo justo para pintar una tarjeta y poder reproducirlo.
class Artist {
  final String id;
  final String uri;
  final String name;
  final String? art;

  const Artist({
    required this.id,
    required this.uri,
    required this.name,
    required this.art,
  });

  static Artist? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return Artist(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Desconocido',
      // Las fotos de artista sí traen dimensiones; se coge la de 300 para las
      // tarjetas y no la de 640, que es el error caro de siempre.
      art: pickImage(j['images'] as List<dynamic>?, 300),
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

/// Instantánea de `GET /v1/me/player`.
class Playback {
  final Track? track;
  final bool isPlaying;
  final int progressMs;
  final String? deviceId;
  final String? deviceName;
  final int? volumePercent;
  final bool shuffle;
  final String repeat; // off | track | context
  final String? contextUri;

  /// ¿Queda algo detrás de esta canción?
  ///
  /// Sale de `actions.disallows` y es la única señal que da la API de que se ha
  /// llegado al final de la lista: en la última canción con la repetición
  /// apagada, Spotify marca `skipping_next` como prohibido. Saltar de todos
  /// modos no da la vuelta a la lista — para la reproducción.
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
    // `disallows` solo lista lo prohibido, y solo con valor `true`: lo que no
    // aparece está permitido. De ahí el `!= true` en vez de un `?? false`.
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
      // ⚠️ La clave es `skipping_prev`, abreviada, no `skipping_previous`.
      canSkipPrevious: disallows?['skipping_prev'] != true,
    );
  }
}
