import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/ui/track_tile.dart';

const _pista = Track(
  id: '1',
  uri: 'spotify:track:1',
  name: 'Una canción con un título razonablemente largo',
  artists: 'Un artista, Otro artista',
  album: 'Un álbum',
  artSmall: null,
  artMedium: null,
  durationMs: 185000,
  isLocal: false,
);

Future<Size> _medir(WidgetTester tester, Widget tile) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(mainAxisSize: MainAxisSize.min, children: [tile]),
    ),
  ));
  return tester.getSize(find.byType(TrackTile));
}

void main() {
  testWidgets('la fila mide exactamente los 64 px que asume la lista', (tester) async {
    final size = await _medir(
      tester,
      const TrackTile(track: _pista, actions: TrackActions(), leadingNumber: 1),
    );
    expect(size.height, 64);
  });

  testWidgets('sin número de orden sigue midiendo 64', (tester) async {
    final size = await _medir(
      tester,
      const TrackTile(track: _pista, actions: TrackActions()),
    );
    expect(size.height, 64);
  });

  testWidgets('ocultar la carátula no cambia el alto', (tester) async {
    final size = await _medir(
      tester,
      const TrackTile(
        track: _pista,
        actions: TrackActions(),
        leadingNumber: 1,
        showArt: false,
      ),
    );
    expect(size.height, 64);
  });

  testWidgets('el texto largo se recorta en vez de desbordar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: TrackTile(track: _pista, actions: TrackActions(), leadingNumber: 999),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  group('PlaylistSearchTile', () {
    const pl = Playlist(
      id: 'pl1',
      uri: 'spotify:playlist:pl1',
      name: 'Mi Playlist Favorita',
      owner: 'Spotify',
      ownerId: 'spotify',
      art: null,
      trackCount: 42,
    );

    testWidgets('la fila de playlist mide exactamente 64 px', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlaylistSearchTile(playlist: pl, onTap: () {}),
            ],
          ),
        ),
      ));
      final size = tester.getSize(find.byType(PlaylistSearchTile));
      expect(size.height, 64);
    });

    testWidgets('renderiza el título y el propietario', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlaylistSearchTile(playlist: pl, onTap: () {}),
        ),
      ));
      expect(find.text('Mi Playlist Favorita'), findsOneWidget);
      expect(find.text('Playlist • Spotify'), findsOneWidget);
    });
  });
}
