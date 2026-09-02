import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/artistas_favoritos_store.dart';
import 'package:neofy/core/models.dart';

const _skrillex = Artist(
  id: 'skr',
  uri: 'spotify:artist:skr',
  name: 'Skrillex',
  art: 'http://art/skr',
);

const _dani = Artist(
  id: 'dani',
  uri: 'spotify:artist:dani',
  name: 'Dani Martín',
  art: null,
);

void main() {
  Directory dirTemporal() {
    final d = Directory('${Directory.systemTemp.path}'
        '/neofy_favart_${DateTime.now().microsecondsSinceEpoch}');
    d.createSync(recursive: true);
    return d;
  }

  test('el corazón añade, quita y sobrevive a recargar', () async {
    final dir = dirTemporal();
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = ArtistasFavoritosStore(directorio: dir);
    addTearDown(store.dispose);
    await store.cargar();
    expect(store.artistas, isEmpty);

    await store.toggle(_skrillex);
    await store.toggle(_dani);
    expect(store.esFavorito('skr'), isTrue);
    expect(store.artistas.first.id, 'dani');

    await store.toggle(_skrillex);
    expect(store.esFavorito('skr'), isFalse);
    expect(store.artistas.map((a) => a.id), ['dani']);

    final recargado = ArtistasFavoritosStore(directorio: dir);
    addTearDown(recargado.dispose);
    await recargado.cargar();
    expect(recargado.artistas.map((a) => a.id), ['dani']);
    expect(recargado.artistas.first.name, 'Dani Martín');
  });
}
