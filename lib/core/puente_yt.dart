library;

import 'models.dart';
import 'yt_models.dart';
import 'yt_music_api.dart';

/// Puente entre las canciones de Spotify y los vídeos de YouTube Music.
///
/// Dada una canción de Spotify ([Track]), busca y selecciona el mejor vídeo
/// o pista equivalente de YouTube Music ([YtTrack]).
class PuenteYt {
  PuenteYt(this.api);

  final YtMusicApi api;

  /// Caché en memoria por `Track.id` para evitar repetir búsquedas en la misma sesión.
  final Map<String, YtTrack?> _cache = {};

  /// Umbral mínimo de puntuación (0..100) para aceptar un candidato como equivalente válido.
  static const int umbralMinimo = 60;

  /// Busca en YouTube Music el equivalente de [t]. Devuelve `null` si no hay nada
  /// suficientemente parecido.
  Future<YtTrack?> equivalenteDe(Track t) async {
    if (_cache.containsKey(t.id)) {
      return _cache[t.id];
    }

    // Consulta: "<primer_artista> <nombre_cancion>"
    final primerArtista = t.artists.split(',').first.trim();
    final consulta = primerArtista.isEmpty ? t.name : '$primerArtista ${t.name}';

    final secciones = await api.buscar(consulta);
    final candidatos = <YtItem>[];
    for (final s in secciones) {
      for (final item in s.items) {
        if (item.tipo == YtTipo.cancion && item.videoId != null && item.videoId!.isNotEmpty) {
          candidatos.add(item);
        }
      }
    }

    final candidatoElegido = mejorCandidato(t, candidatos);
    _cache[t.id] = candidatoElegido;
    return candidatoElegido;
  }

  /// Pura, sin red: elige el mejor candidato de una lista de candidatos ya obtenidos.
  /// Devuelve `null` si ningún candidato supera el [umbralMinimo].
  static YtTrack? mejorCandidato(Track t, List<YtItem> candidatos) {
    if (candidatos.isEmpty) return null;

    YtItem? mejorItem;
    var maxPuntos = -1;

    for (final cand in candidatos) {
      final puntos = puntuar(t, cand);
      if (puntos > maxPuntos) {
        maxPuntos = puntos;
        mejorItem = cand;
      }
    }

    if (mejorItem != null && maxPuntos >= umbralMinimo) {
      return mejorItem.comoPista;
    }
    return null;
  }

  /// Pura: deja un título comparable (minúsculas, sin acentos, sin adornos).
  static String normalizar(String s) {
    if (s.isEmpty) return '';
    var texto = s.toLowerCase();

    // Quitar acentos y caracteres especiales de vocales y eñe
    texto = texto
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n');

    // Quitar "feat. X" o "ft. X" y todo lo que sigue tras esa marca
    texto = texto.replaceAll(RegExp(r'\b(feat|ft)\b\.?.*$', caseSensitive: false), '');

    // Quitar etiquetas comunes de remasterizado, vídeo oficial, audio, letras, HD, 4K
    texto = texto.replaceAll(
      RegExp(
        r'[\-\(\[\{]\s*(remastered|remaster|official video|official music video|official audio|lyric video|lyrics|audio|hd|4k)\b[^\)\]\}]*[\)\]\}]?',
        caseSensitive: false,
      ),
      '',
    );

    // Quitar variaciones de remasterizado con año (p. ej. "- Remastered 2011" o "- 2011 Remaster")
    texto = texto.replaceAll(
      RegExp(r'\-\s*(\d{4}\s*)?remaster(ed)?(\s*\d{4})?', caseSensitive: false),
      '',
    );

    // Quitar texto remanente entre paréntesis o corchetes al final de la cadena
    texto = texto.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '');

    // Convertir signos de puntuación a espacios
    texto = texto.replaceAll(RegExp(r'[^\w\s]'), ' ');

    // Colapsar múltiples espacios y recortar extremos
    return texto.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Pura: calcula una puntuación de 0 a 100 evaluando la coincidencia entre
  /// la pista de Spotify [t] y el [candidato] de YouTube Music.
  static int puntuar(Track t, YtItem candidato) {
    // -------------------------------------------------------------------------
    // 1. Parecido del título (Pesa hasta 55 puntos).
    // Es el núcleo de la evaluación. Compara las cadenas normalizadas sin adornos.
    // -------------------------------------------------------------------------
    final normTrack = normalizar(t.name);
    final normCand = normalizar(candidato.titulo);

    final simTitulo = _calcularSimilitud(normTrack, normCand);
    final puntosTitulo = (simTitulo * 55).round();

    // -------------------------------------------------------------------------
    // 2. Coincidencia del artista en el subtítulo (Pesa hasta 35 puntos).
    // Suma fuerte si el artista principal de Spotify aparece en el subtítulo del candidato.
    // Si el subtítulo está presente pero el artista no coincide, se aplica una penalización
    // para evitar falsos positivos de versiones por otros artistas.
    // -------------------------------------------------------------------------
    final primerArtista = t.artists.split(',').first.trim();
    final normArtista = normalizar(primerArtista);
    final normSubtitulo = normalizar(candidato.subtitulo);

    var puntosArtista = 0;
    if (normArtista.isNotEmpty && normSubtitulo.isNotEmpty) {
      if (normSubtitulo.contains(normArtista) || normArtista.contains(normSubtitulo)) {
        puntosArtista = 35;
      } else {
        // Penalización por desajuste explícito de artista
        puntosArtista = -20;
      }
    }

    // -------------------------------------------------------------------------
    // 3. Duración (Ajuste de +10 a penalización fuerte).
    // Si la duración es similar (<= 3s de diferencia), otorga +10 puntos.
    // Si difiere más de 10s (hasta 2 min o más), penaliza progresivamente para
    // descartar versiones en directo, intros habladas o mixes extensos.
    // Si el candidato NO trae duración, no suma ni resta puntos.
    // -------------------------------------------------------------------------
    var puntosDuracion = 0;
    if (candidato.duracion != null && t.durationMs > 0) {
      final segTrack = (t.durationMs / 1000).round();
      final segCand = candidato.duracion!.inSeconds;
      final diffSeg = (segTrack - segCand).abs();

      if (diffSeg <= 3) {
        puntosDuracion = 10;
      } else if (diffSeg <= 10) {
        puntosDuracion = 5;
      } else {
        // Penalización progresiva a partir de 10 segundos de diferencia
        final exceso = diffSeg - 10;
        puntosDuracion = -(exceso * 2);
      }
    }

    // -------------------------------------------------------------------------
    // 4. Trampas de versión (Penalización de -60 puntos).
    // Castiga variantes como 'live', 'cover', 'remix', 'sped up', etc., cuando
    // la canción original de Spotify NO especifica esa variante.
    // -------------------------------------------------------------------------
    var penalizacionTrampas = 0;
    final trampas = [
      'live',
      'en vivo',
      'cover',
      'karaoke',
      'instrumental',
      'sped up',
      'slowed',
      'remix',
      '8d',
    ];

    final candTituloLower = candidato.titulo.toLowerCase();
    final candSubLower = candidato.subtitulo.toLowerCase();
    final trackNameLower = t.name.toLowerCase();

    for (final trampa in trampas) {
      final enCandidato = candTituloLower.contains(trampa) || candSubLower.contains(trampa);
      final enSpotify = trackNameLower.contains(trampa);

      if (enCandidato && !enSpotify) {
        penalizacionTrampas += 60;
        break;
      }
    }

    final total = puntosTitulo + puntosArtista + puntosDuracion - penalizacionTrampas;
    return total.clamp(0, 100);
  }

  /// Calcula la similitud de Levenshtein entre dos cadenas normalizadas (0.0 a 1.0).
  static double _calcularSimilitud(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    if (s1.contains(s2) || s2.contains(s1)) {
      final lenMax = s1.length > s2.length ? s1.length : s2.length;
      final lenMin = s1.length < s2.length ? s1.length : s2.length;
      if (lenMin / lenMax >= 0.7) return 0.9;
    }

    final dist = _levenshtein(s1, s2);
    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    return (maxLen - dist) / maxLen;
  }

  static int _levenshtein(String s1, String s2) {
    final a = s1.codeUnits;
    final b = s2.codeUnits;
    final m = a.length;
    final n = b.length;

    List<int> v0 = List<int>.generate(n + 1, (i) => i);
    List<int> v1 = List<int>.filled(n + 1, 0);

    for (var i = 0; i < m; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < n; j++) {
        final cost = (a[i] == b[j]) ? 0 : 1;
        final del = v0[j + 1] + 1;
        final ins = v1[j] + 1;
        final sub = v0[j] + cost;

        var min = del < ins ? del : ins;
        if (sub < min) min = sub;
        v1[j + 1] = min;
      }
      for (var j = 0; j <= n; j++) {
        v0[j] = v1[j];
      }
    }

    return v0[n];
  }
}
