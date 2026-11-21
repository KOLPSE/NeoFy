library;

import 'models.dart';
import 'yt_models.dart';
import 'yt_music_api.dart';

class PuenteYt {
  PuenteYt(this.api);

  final YtMusicApi api;

  final Map<String, YtTrack?> _cache = {};

  static const int _maxCache = 250;
  static const int umbralMinimo = 60;

  static final _reA = RegExp(r'[áàäâ]');
  static final _reE = RegExp(r'[éèëê]');
  static final _reI = RegExp(r'[íìïî]');
  static final _reO = RegExp(r'[óòöô]');
  static final _reU = RegExp(r'[úùüû]');
  static final _reFeat = RegExp(r'\b(feat|ft)\b\.?.*$', caseSensitive: false);
  static final _reEtiquetas = RegExp(
    r'[\-\(\[\{]\s*(remastered|remaster|official video|official music video|official audio|lyric video|lyrics|audio|hd|4k)\b[^\)\]\}]*[\)\]\}]?',
    caseSensitive: false,
  );
  static final _reRemaster = RegExp(
    r'\-\s*(\d{4}\s*)?remaster(ed)?(\s*\d{4})?',
    caseSensitive: false,
  );
  static final _reParentesis = RegExp(r'[\(\[\{].*?[\)\]\}]');
  static final _reNoPalabra = RegExp(r'[^\w\s]');
  static final _reEspacios = RegExp(r'\s+');

  static const _trampas = [
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

  Future<YtTrack?> equivalenteDe(Track t) async {
    if (_cache.containsKey(t.id)) {
      return _cache[t.id];
    }

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
    if (_cache.length >= _maxCache) {
      _cache.remove(_cache.keys.first);
    }
    _cache[t.id] = candidatoElegido;
    return candidatoElegido;
  }

  static YtTrack? mejorCandidato(Track t, List<YtItem> candidatos) {
    if (candidatos.isEmpty) return null;

    final normTrack = normalizar(t.name);
    final normArtista = normalizar(t.artists.split(',').first.trim());
    final trackNameLower = t.name.toLowerCase();

    YtItem? mejorItem;
    var maxPuntos = -1;

    for (final cand in candidatos) {
      final puntos = _puntuarPreparado(
        t,
        cand,
        normTrack: normTrack,
        normArtista: normArtista,
        trackNameLower: trackNameLower,
      );
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

  static String normalizar(String s) {
    if (s.isEmpty) return '';
    var texto = s
        .toLowerCase()
        .replaceAll(_reA, 'a')
        .replaceAll(_reE, 'e')
        .replaceAll(_reI, 'i')
        .replaceAll(_reO, 'o')
        .replaceAll(_reU, 'u')
        .replaceAll('ñ', 'n');

    texto = texto.replaceAll(_reFeat, '');
    texto = texto.replaceAll(_reEtiquetas, '');
    texto = texto.replaceAll(_reRemaster, '');
    texto = texto.replaceAll(_reParentesis, '');
    texto = texto.replaceAll(_reNoPalabra, ' ');

    return texto.replaceAll(_reEspacios, ' ').trim();
  }

  static int puntuar(Track t, YtItem candidato) => _puntuarPreparado(
        t,
        candidato,
        normTrack: normalizar(t.name),
        normArtista: normalizar(t.artists.split(',').first.trim()),
        trackNameLower: t.name.toLowerCase(),
      );

  static int _puntuarPreparado(
    Track t,
    YtItem candidato, {
    required String normTrack,
    required String normArtista,
    required String trackNameLower,
  }) {
    final normCand = normalizar(candidato.titulo);

    final simTitulo = _calcularSimilitud(normTrack, normCand);
    final puntosTitulo = (simTitulo * 55).round();

    final normSubtitulo = normalizar(candidato.subtitulo);

    var puntosArtista = 0;
    if (normArtista.isNotEmpty && normSubtitulo.isNotEmpty) {
      if (normSubtitulo.contains(normArtista) || normArtista.contains(normSubtitulo)) {
        puntosArtista = 35;
      } else {
        puntosArtista = -20;
      }
    }

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
        final exceso = diffSeg - 10;
        puntosDuracion = -(exceso * 2);
      }
    }

    var penalizacionTrampas = 0;
    final candTituloLower = candidato.titulo.toLowerCase();
    final candSubLower = candidato.subtitulo.toLowerCase();

    for (final trampa in _trampas) {
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
