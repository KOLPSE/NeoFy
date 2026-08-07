import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/ui/home_screen.dart';

const _pista = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Un título de canción bastante largo para una tarjeta',
  artists: 'Un artista, Otro artista, Un tercero',
  album: 'Un álbum',
  artSmall: null,
  artMedium: null,
  durationMs: 185000,
  isLocal: false,
);

const _artista = Artist(
  id: '1',
  uri: 'spotify:artist:1',
  name: 'Un nombre de artista largo',
  art: null,
);

Future<void> _pintar(WidgetTester tester, Widget tira, double escala) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(escala)),
      child: Scaffold(body: Center(child: tira)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // Los altos de las dos tiras estaban a ojo (`lado + 46` y `lado + 28`) y el
  // de artistas se quedaba dos píxeles corto: el nombre salía recortado por
  // abajo. Ahora salen del estilo real y de la escala de texto del sistema, así
  // que hay que comprobarlo también con Windows al 125 %.
  for (final escala in [1.0, 1.25, 1.5]) {
    testWidgets('las canciones caben en su tira al ${escala}x', (tester) async {
      await _pintar(
        tester,
        TiraDeCanciones(tracks: const [_pista, _pista], onPlay: (_) {}),
        escala,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('los artistas caben en su tira al ${escala}x', (tester) async {
      await _pintar(
        tester,
        TiraDeArtistas(artistas: const [_artista, _artista], onPlay: (_) {}),
        escala,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
