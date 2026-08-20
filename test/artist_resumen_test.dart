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
      expect(resumenDeArtista(_lista(1, minutos: 3)), '1 canción · 3 min');
    });

    test('sin canciones no se inventa nada', () {
      expect(resumenDeArtista(const []), '0 canciones · 0 min');
    });

    test('se redondea al minuto, no se trunca', () {
      expect(resumenDeArtista(_lista(3, minutos: 1 + 40 / 60)),
          '3 canciones · 5 min');
    });
  });
}
