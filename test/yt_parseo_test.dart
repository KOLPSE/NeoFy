import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/yt_auth.dart';
import 'package:neofy/core/yt_models.dart';
import 'package:neofy/core/yt_music_api.dart';

void main() {
  final api = YtMusicApi(YtAuth());

  Map<String, dynamic> unaColumna(List<dynamic> bloques) => {
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {'contents': bloques},
                  },
                },
              },
            ],
          },
        },
      };

  Map<String, dynamic> tarjeta({
    required String titulo,
    String subtitulo = 'Lista',
    String? videoId,
    String? browseId,
    String? playlistIdDelOverlay,
  }) =>
      {
        'musicTwoRowItemRenderer': {
          'title': {
            'runs': [
              {'text': titulo},
            ],
          },
          'subtitle': {
            'runs': [
              {'text': subtitulo},
            ],
          },
          'thumbnailRenderer': {
            'musicThumbnailRenderer': {
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://ejemplo/pequena.jpg'},
                  {'url': 'https://ejemplo/grande.jpg'},
                ],
              },
            },
          },
          'navigationEndpoint': {
            if (videoId != null) 'watchEndpoint': {'videoId': videoId},
            if (browseId != null) 'browseEndpoint': {'browseId': browseId},
          },
          if (playlistIdDelOverlay != null)
            'thumbnailOverlay': {
              'musicItemThumbnailOverlayRenderer': {
                'content': {
                  'musicPlayButtonRenderer': {
                    'playNavigationEndpoint': {
                      'watchPlaylistEndpoint': {'playlistId': playlistIdDelOverlay},
                    },
                  },
                },
              },
            },
        },
      };

  group('biblioteca', () {
    test('las playlists de un gridRenderer se leen de `items`, no de `contents`',
        () {
      final j = unaColumna([
        {
          'itemSectionRenderer': {
            'contents': [
              {
                'gridRenderer': {
                  'header': {
                    'gridHeaderRenderer': {
                      'title': {
                        'runs': [
                          {'text': 'Playlists'},
                        ],
                      },
                    },
                  },
                  'items': [
                    tarjeta(titulo: 'Rock de casa', browseId: 'VLPLabc123'),
                    tarjeta(titulo: 'Para dormir', browseId: 'VLPLxyz789'),
                  ],
                },
              },
            ],
          },
        },
      ]);

      final secciones = api.seccionesDeRespuesta(j);
      expect(secciones, hasLength(1));
      expect(secciones.first.titulo, 'Playlists');
      expect(secciones.first.items.map((i) => i.titulo),
          ['Rock de casa', 'Para dormir']);
    });

    test('una lista trae su playlistId sin el prefijo VL, listo para browse', () {
      final j = unaColumna([
        {
          'gridRenderer': {
            'items': [tarjeta(titulo: 'Rock de casa', browseId: 'VLPLabc123')],
          },
        },
      ]);

      final item = api.seccionesDeRespuesta(j).single.items.single;
      expect(item.tipo, YtTipo.lista);
      expect(item.playlistId, 'PLabc123');
      expect(item.esNavegable, isTrue);
      expect(item.esCancion, isFalse);
    });
  });

  group('tipos', () {
    test('un álbum se distingue por su browseId MPRE', () {
      final j = unaColumna([
        {
          'gridRenderer': {
            'items': [tarjeta(titulo: 'Un disco', browseId: 'MPREb_xxxx')],
          },
        },
      ]);
      final item = api.seccionesDeRespuesta(j).single.items.single;
      expect(item.tipo, YtTipo.album);
      expect(item.browseId, 'MPREb_xxxx');
      expect(item.esNavegable, isTrue);
    });

    test('un artista se distingue por su browseId UC y no es navegable', () {
      final j = unaColumna([
        {
          'gridRenderer': {
            'items': [tarjeta(titulo: 'Alguien', browseId: 'UC1234')],
          },
        },
      ]);
      final item = api.seccionesDeRespuesta(j).single.items.single;
      expect(item.tipo, YtTipo.artista);
      expect(item.esNavegable, isFalse);
    });

    test('una canción suelta se convierte en pista reproducible', () {
      final j = unaColumna([
        {
          'musicCarouselShelfRenderer': {
            'contents': [
              tarjeta(titulo: 'Una canción', subtitulo: 'Un grupo', videoId: 'abc-_123'),
            ],
          },
        },
      ]);
      final item = api.seccionesDeRespuesta(j).single.items.single;
      expect(item.tipo, YtTipo.cancion);
      expect(item.comoPista?.videoId, 'abc-_123');
      expect(item.comoPista?.artista, 'Un grupo');
      expect(item.miniatura, 'https://ejemplo/grande.jpg');
    });

    test('una mezcla de la portada saca su playlistId del botón de play', () {
      final j = unaColumna([
        {
          'musicCarouselShelfRenderer': {
            'contents': [
              tarjeta(titulo: 'Mi mezcla', playlistIdDelOverlay: 'RDAMVMabc'),
            ],
          },
        },
      ]);
      final item = api.seccionesDeRespuesta(j).single.items.single;
      expect(item.tipo, YtTipo.lista);
      expect(item.playlistId, 'RDAMVMabc');
    });
  });

  group('robustez', () {
    test('un bloque con forma desconocida no se lleva por delante a los demás', () {
      final j = unaColumna([
        {'algoQueNoConocemos': <String, dynamic>{}},
        {
          'gridRenderer': {
            'items': [tarjeta(titulo: 'Sobrevive', browseId: 'VLPL1')],
          },
        },
      ]);
      expect(api.seccionesDeRespuesta(j).single.items.single.titulo, 'Sobrevive');
    });

    test('el botón de "Nueva lista" no se cuela como si fuera una playlist', () {
      final j = unaColumna([
        {
          'gridRenderer': {
            'items': [
              tarjeta(titulo: 'Nueva lista'),
              tarjeta(titulo: 'Una de verdad', browseId: 'VLPL1'),
            ],
          },
        },
      ]);
      expect(api.seccionesDeRespuesta(j).single.items.map((i) => i.titulo),
          ['Una de verdad']);
    });

    test('una respuesta sin la forma esperada devuelve vacío, no lanza', () {
      expect(api.seccionesDeRespuesta({'nada': 'de nada'}), isEmpty);
      expect(api.seccionesDeRespuesta(null), isEmpty);
    });

    test('el subtítulo se une entero, no solo su primer trozo', () {
      final j = unaColumna([
        {
          'gridRenderer': {
            'items': [
              {
                'musicTwoRowItemRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'Mi lista'},
                    ],
                  },
                  'subtitle': {
                    'runs': [
                      {'text': 'Lista'},
                      {'text': ' • '},
                      {'text': '42 canciones'},
                    ],
                  },
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'VLPL1'},
                  },
                },
              },
            ],
          },
        },
      ]);
      expect(api.seccionesDeRespuesta(j).single.items.single.subtitulo,
          'Lista • 42 canciones');
    });
  });

  group('contenido de una lista', () {
    Map<String, dynamic> listaPropia(List<dynamic> pistas, {List<dynamic>? extra}) => {
          'contents': {
            'twoColumnBrowseResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'content': {
                      'sectionListRenderer': {
                        'contents': [
                          {
                            'musicEditablePlaylistDetailHeaderRenderer': {
                              'playlistId': 'PLabc',
                              'header': {
                                'musicResponsiveHeaderRenderer': {
                                  'title': {
                                    'runs': [
                                      {'text': 'C'},
                                    ],
                                  },
                                  'subtitle': {
                                    'runs': [
                                      {'text': 'Lista'},
                                    ],
                                  },
                                  'secondSubtitle': {
                                    'runs': [
                                      {'text': '2 canciones'},
                                    ],
                                  },
                                  'thumbnail': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://ejemplo/portada.jpg'},
                                        ],
                                      },
                                    },
                                  },
                                },
                              },
                            },
                          },
                        ],
                      },
                    },
                  },
                },
              ],
              'secondaryContents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'musicPlaylistShelfRenderer': {
                        'contents': [...pistas, ...?extra],
                      },
                    },
                  ],
                },
              },
            },
          },
        };

    Map<String, dynamic> fila(String titulo, String artista, String videoId,
            {String? duracion}) =>
        {
          'musicResponsiveListItemRenderer': {
            'playlistItemData': {'videoId': videoId},
            'flexColumns': [
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {'text': titulo},
                    ],
                  },
                },
              },
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {'text': artista},
                    ],
                  },
                },
              },
            ],
            if (duracion != null)
              'fixedColumns': [
                {
                  'musicResponsiveListItemFixedColumnRenderer': {
                    'text': {
                      'runs': [
                        {'text': duracion},
                      ],
                    },
                  },
                },
              ],
          },
        };

    test('las pistas se leen de secondaryContents, no de la pestaña', () {
      final (c, _) = api.coleccionDeRespuesta(listaPropia([
        fila('Take On Me', 'a-ha', 'djV11Xbc914', duracion: '3:47'),
        fila('Hola', 'Alguien', 'K4xmzYN3k50'),
      ]));
      expect(c.pistas.map((t) => t.videoId), ['djV11Xbc914', 'K4xmzYN3k50']);
      expect(c.pistas.first.artista, 'a-ha');
      expect(c.pistas.first.duracion, const Duration(minutes: 3, seconds: 47));
      expect(c.pistas.last.duracion, isNull);
    });

    test('la cabecera de una lista propia va envuelta y aun así se lee', () {
      final (c, _) = api.coleccionDeRespuesta(
          listaPropia([fila('Take On Me', 'a-ha', 'djV11Xbc914')]));
      expect(c.titulo, 'C');
      expect(c.subtitulo, 'Lista • 2 canciones');
      expect(c.miniatura, 'https://ejemplo/portada.jpg');
    });

    test('una lista larga devuelve el token del siguiente trozo', () {
      final (c, token) = api.coleccionDeRespuesta(listaPropia(
        [fila('Take On Me', 'a-ha', 'djV11Xbc914')],
        extra: [
          {
            'continuationItemRenderer': {
              'continuationEndpoint': {
                'continuationCommand': {'token': 'sigue-por-aqui'},
              },
            },
          },
        ],
      ));
      expect(c.pistas, hasLength(1));
      expect(token, 'sigue-por-aqui');
    });

    test('una lista que cabe entera no pide continuación', () {
      final (_, token) = api.coleccionDeRespuesta(
          listaPropia([fila('Take On Me', 'a-ha', 'djV11Xbc914')]));
      expect(token, isNull);
    });
  });

  group('dos columnas', () {
    test('las listas modernas llegan en twoColumnBrowseResultsRenderer', () {
      final j = {
        'contents': {
          'twoColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'gridRenderer': {
                            'items': [tarjeta(titulo: 'Desde dos columnas', browseId: 'VLPL9')],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      };
      expect(api.seccionesDeRespuesta(j).single.items.single.titulo,
          'Desde dos columnas');
    });
  });
}
