library;

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

  Track copyWith({
    String? id,
    String? uri,
    String? name,
    String? artists,
    String? album,
    String? artSmall,
    String? artMedium,
    int? durationMs,
    bool? isLocal,
  }) =>
      Track(
        id: id ?? this.id,
        uri: uri ?? this.uri,
        name: name ?? this.name,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        artSmall: artSmall ?? this.artSmall,
        artMedium: artMedium ?? this.artMedium,
        durationMs: durationMs ?? this.durationMs,
        isLocal: isLocal ?? this.isLocal,
      );

  static Track? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
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
      art: pickImage(j['images'] as List<dynamic>?, 300),
    );
  }
}

class Album {
  final String id;
  final String uri;
  final String name;
  final String artists;
  final String? art;

  const Album({
    required this.id,
    required this.uri,
    required this.name,
    required this.artists,
    required this.art,
  });

  static Album? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final artistList = j['artists'] as List<dynamic>?;
    return Album(
      id: (j['id'] as String?) ?? '',
      uri: (j['uri'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Desconocido',
      artists: artistList == null
          ? ''
          : artistList.map((a) => (a as Map)['name'] as String? ?? '').join(', '),
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
