import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/metadata_sidecar.dart';

void main() {
  test('el perfil del sidecar rellena canciones, discos y bio', () {
    final p = PerfilDeArtista.desdeJson({
      'id': 'a1',
      'uri': 'spotify:artist:a1',
      'name': 'Skrillex',
      'biography': 'Sonny John Moore.',
      'images': [
        {'url': 'grande', 'width': 640},
        {'url': 'media', 'width': 300},
      ],
      'top_tracks': [
        {
          'id': 't1',
          'uri': 'spotify:track:t1',
          'name': 'Bangarang',
          'duration_ms': 180000,
          'artists': [
            {'id': 'a1', 'name': 'Skrillex'}
          ],
          'album': {
            'name': 'Bangarang',
            'images': [
              {'url': 'caratula', 'width': 300}
            ],
          },
        },
      ],
      'albums': [
        {
          'id': 'd1',
          'uri': 'spotify:album:d1',
          'name': 'Recess',
          'album_group': 'album',
          'release_date': '2014-03-14',
          'artists': [
            {'name': 'Skrillex'}
          ],
          'images': [
            {'url': 'disco', 'width': 300}
          ],
        },
      ],
      'singles': const [],
      'appears_on': const [],
      'related': [
        {
          'id': 'a2',
          'uri': 'spotify:artist:a2',
          'name': 'Diplo',
          'images': [
            {'url': 'diplo', 'width': 300}
          ],
        },
      ],
    });

    expect(p.artista.name, 'Skrillex');
    expect(p.artista.biografia, 'Sonny John Moore.');
    expect(p.artista.artGrande, 'grande');
    expect(p.top.single.name, 'Bangarang');
    expect(p.albumes.single.name, 'Recess');
    expect(p.albumes.single.anio, '2014');
    expect(p.relacionados.single.name, 'Diplo');
  });
}
