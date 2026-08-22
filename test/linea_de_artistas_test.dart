import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/ui/linea_de_artistas.dart';

const _uno = ArtistaDePista(
  id: 'a1',
  uri: 'spotify:artist:a1',
  name: 'fnonose',
);
const _dos = ArtistaDePista(
  id: 'a2',
  uri: 'spotify:artist:a2',
  name: 'morningtime',
);

void main() {
  testWidgets('pulsar un nombre llama con ese artista', (t) async {
    ArtistaDePista? abierto;
    await t.pumpWidget(MaterialApp(
      theme: construirThemeData(temaMaterialOscuro),
      home: Scaffold(
        body: LineaDeArtistas(
          artistas: const [_uno, _dos],
          texto: 'fnonose, morningtime',
          onAbrir: (a) => abierto = a,
        ),
      ),
    ));

    await t.tap(find.text('morningtime'));
    expect(abierto?.id, 'a2');
  });

  testWidgets('sin id no es pulsable', (t) async {
    var toques = 0;
    await t.pumpWidget(MaterialApp(
      theme: construirThemeData(temaMaterialOscuro),
      home: Scaffold(
        body: LineaDeArtistas(
          artistas: const [
            ArtistaDePista(id: '', uri: '', name: 'Desconocido'),
          ],
          texto: 'Desconocido',
          onAbrir: (_) => toques++,
        ),
      ),
    ));

    await t.tap(find.text('Desconocido'));
    expect(toques, 0);
  });
}
