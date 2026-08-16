import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/puente_yt.dart';
import 'package:neofy/core/yt_models.dart';

void main() {
  Track crearTrack({
    String id = 'track_1',
    String name = 'Take On Me',
    String artists = 'a-ha',
    int durationMs = 227000,
  }) {
    return Track(
      id: id,
      uri: 'spotify:track:$id',
      name: name,
      artists: artists,
      album: 'Hunting High and Low',
      artSmall: null,
      artMedium: null,
      durationMs: durationMs,
      isLocal: false,
    );
  }

  YtItem crearCandidato({
    required String videoId,
    required String titulo,
    required String subtitulo,
    Duration? duracion,
  }) {
    return YtItem(
      tipo: YtTipo.cancion,
      titulo: titulo,
      subtitulo: subtitulo,
      videoId: videoId,
      duracion: duracion,
    );
  }

  group('PuenteYt.normalizar', () {
    test('convierte a minúsculas y elimina acentos', () {
      expect(PuenteYt.normalizar('Canción Única'), 'cancion unica');
    });

    test('elimina etiquetas de remasterizado y adornos comunes', () {
      expect(PuenteYt.normalizar('Take On Me - Remastered 2011'), 'take on me');
      expect(PuenteYt.normalizar('Bohemian Rhapsody (2011 Remaster)'), 'bohemian rhapsody');
      expect(PuenteYt.normalizar('Shape of You (Official Video) [HD]'), 'shape of you');
    });

    test('elimina colaboraciones indicadas con feat, ft o entre paréntesis con', () {
      expect(PuenteYt.normalizar('Despacito feat. Daddy Yankee'), 'despacito');
      expect(PuenteYt.normalizar('Despacito ft. Daddy Yankee'), 'despacito');
      expect(PuenteYt.normalizar('Despacito (con Daddy Yankee)'), 'despacito');
    });

    test('no elimina la preposición con en títulos normales', () {
      expect(PuenteYt.normalizar('Con Altura'), 'con altura');
      expect(PuenteYt.normalizar('Tú Con Él'), 'tu con el');
    });

    test('dos títulos normalizados a cadena vacía no puntúan como coincidencia', () {
      final track = crearTrack(name: '[...]', artists: 'Artista');
      final cand = crearCandidato(videoId: 'v_vacio', titulo: '(...)', subtitulo: 'Artista');
      expect(PuenteYt.puntuar(track, cand), 35);
    });
  });

  group('PuenteYt.mejorCandidato (funciones puras)', () {
    test('coincidencia exacta de título y artista -> la elige', () {
      final track = crearTrack(name: 'Take On Me', artists: 'a-ha', durationMs: 227000);
      final candidatos = [
        crearCandidato(
          videoId: 'v1',
          titulo: 'Take On Me',
          subtitulo: 'a-ha',
          duracion: const Duration(minutes: 3, seconds: 47),
        ),
      ];

      final resultado = PuenteYt.mejorCandidato(track, candidatos);
      expect(resultado, isNotNull);
      expect(resultado!.videoId, 'v1');
      expect(resultado.titulo, 'Take On Me');
      expect(resultado.artista, 'a-ha');
    });

    test('el mismo tema con - Remastered 2011 en un lado y sin él en el otro -> la elige igual', () {
      final track = crearTrack(name: 'Take On Me - Remastered 2011', artists: 'a-ha');
      final candidatos = [
        crearCandidato(
          videoId: 'v2',
          titulo: 'Take On Me',
          subtitulo: 'a-ha',
          duracion: const Duration(minutes: 3, seconds: 47),
        ),
      ];

      final resultado = PuenteYt.mejorCandidato(track, candidatos);
      expect(resultado, isNotNull);
      expect(resultado!.videoId, 'v2');
    });

    test('una versión en directo cuando la de Spotify es de estudio -> la descarta', () {
      final track = crearTrack(name: 'Hotel California', artists: 'Eagles');
      final candidatos = [
        crearCandidato(
          videoId: 'v_live',
          titulo: 'Hotel California (Live)',
          subtitulo: 'Eagles',
          duracion: const Duration(minutes: 6, seconds: 30),
        ),
      ];

      final resultado = PuenteYt.mejorCandidato(track, candidatos);
      expect(resultado, isNull);
    });

    test('un candidato con duración muy distinta (p. ej. 2 min de diferencia) -> la descarta', () {
      final track = crearTrack(name: 'Take On Me', artists: 'a-ha', durationMs: 227000);
      final candidatos = [
        crearCandidato(
          videoId: 'v_largo',
          titulo: 'Take On Me',
          subtitulo: 'a-ha',
          duracion: const Duration(minutes: 5, seconds: 47),
        ),
      ];

      final resultado = PuenteYt.mejorCandidato(track, candidatos);
      expect(resultado, isNull);
    });

    test('título casi igual pero otro artista -> la descarta', () {
      final track = crearTrack(name: 'Yesterday', artists: 'The Beatles');
      final candidatos = [
        crearCandidato(
          videoId: 'v_otro',
          titulo: 'Yesterday',
          subtitulo: 'Boyz II Men',
          duracion: const Duration(minutes: 2, seconds: 30),
        ),
      ];

      final resultado = PuenteYt.mejorCandidato(track, candidatos);
      expect(resultado, isNull);
    });

    test('lista de candidatos vacía -> null', () {
      final track = crearTrack();
      final resultado = PuenteYt.mejorCandidato(track, []);
      expect(resultado, isNull);
    });

    test('un candidato sin duración -> sigue siendo elegible si el título y el artista encajan', () {
      final track = crearTrack(name: 'Take On Me', artists: 'a-ha');
      final candidatos = [
        crearCandidato(
          videoId: 'v_sin_duracion',
          titulo: 'Take On Me',
          subtitulo: 'a-ha',
          duracion: null,
        ),
      ];

      final resultado = PuenteYt.mejorCandidato(track, candidatos);
      expect(resultado, isNotNull);
      expect(resultado!.videoId, 'v_sin_duracion');
    });
  });
}
