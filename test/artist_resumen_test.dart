import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/ui/artist_screen.dart';

Track _de(int ms) => Track(
      id: 'x',
      uri: 'spotify:track:x',
      name: 'Cancion',
      artists: 'Alguien',
      album: 'Disco',
      artSmall: null,
      artMedium: null,
      durationMs: ms,
      isLocal: false,
    );

/// [cuantas] canciones de [minutos] minutos cada una.
List<Track> _lista(int cuantas, {required double minutos}) =>
    List.generate(cuantas, (_) => _de((minutos * 60000).round()));

void main() {
  group('resumen de la pantalla de artista', () {
    test('por debajo de una hora se cuenta en minutos', () {
      expect(resumenDeArtista(_lista(10, minutos: 3.2)), '10 canciones · 32 min');
    });

    test('pasada la hora se parte en horas y minutos', () {
      expect(resumenDeArtista(_lista(30, minutos: 3)), '30 canciones · 1 h 30 min');
    });

    test('cuando la hora es justa no se arrastra un "0 min"', () {
      expect(resumenDeArtista(_lista(20, minutos: 3)), '20 canciones · 1 h');
      expect(resumenDeArtista(_lista(40, minutos: 3)), '40 canciones · 2 h');
    });

    test('una sola cancion va en singular', () {
      // "1 canciones" se lee mal, y es el caso que siempre se escapa.
      expect(resumenDeArtista(_lista(1, minutos: 3)), '1 canción · 3 min');
    });

    test('sin canciones no se inventa nada', () {
      expect(resumenDeArtista(const []), '0 canciones · 0 min');
    });

    test('se redondea al minuto, no se trunca', () {
      // 3 canciones de 1 min 40 s son 5 min justos; truncando saldrian 4 y el
      // total no cuadraria con lo que suma la lista a ojo.
      expect(resumenDeArtista(_lista(3, minutos: 1 + 40 / 60)),
          '3 canciones · 5 min');
    });
  });
}
