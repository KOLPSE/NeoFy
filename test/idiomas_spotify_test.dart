import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/idiomas_spotify.dart';

void main() {
  group('localeSpotifyEfectivo', () {
    test('respeta el idioma elegido en ajustes', () {
      expect(localeSpotifyEfectivo('es_MX'), 'es_MX');
      expect(localeSpotifyEfectivo('ja_JP'), 'ja_JP');
    });

    test('un código inválido cae al del PC', () {
      expect(localeSpotifyEfectivo('xx_YY'), localeSpotifyDesdePc());
    });
  });

  group('idiomasFiltrados', () {
    test('encuentra por nombre o código', () {
      final porNombre = idiomasFiltrados('español');
      expect(porNombre.any((i) => i.codigo == 'es_ES'), isTrue);

      final porCodigo = idiomasFiltrados('ko_kr');
      expect(porCodigo.single.codigo, 'ko_KR');
    });
  });

  group('nombreIdiomaPreferido', () {
    test('muestra el nombre legible', () {
      expect(nombreIdiomaPreferido('fr_FR'), 'Francés (Francia)');
      expect(nombreIdiomaPreferido(''), startsWith('Automático'));
    });
  });
}
