import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/idiomas_spotify.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/metadata_sidecar.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/updater.dart';
import 'package:neofy/core/volumen_local.dart';
import 'package:neofy/ui/artist_screen.dart';
import 'package:path/path.dart' as p;

void main() {
  group('volumen local (PulseAudio / PipeWire)', () {
    test('encuentra el sink-input de librespot y no el de otras apps', () {
      const listado = '''
Sink Input #12
	Volume: front-left: 65536
	application.name = "Firefox"
	application.process.binary = "firefox"
Sink Input #18
	Volume: front-left: 65536
	application.name = "librespot"
	application.process.binary = "librespot"
Sink Input #21
	application.process.binary = "pipewire"
''';

      expect(entradasDeLibrespot(listado), ['18']);
    });

    test('sin librespot no inventa ids', () {
      expect(
        entradasDeLibrespot('Sink Input #1\n\tapplication.name = "mpv"'),
        isEmpty,
      );
      expect(entradasDeLibrespot(''), isEmpty);
    });
  });

  group('idiomas de Spotify', () {
    test('respeta el idioma elegido en ajustes', () {
      expect(localeSpotifyEfectivo('es_MX'), 'es_MX');
      expect(localeSpotifyEfectivo('ja_JP'), 'ja_JP');
    });

    test('un código inválido cae al del PC', () {
      expect(localeSpotifyEfectivo('xx_YY'), localeSpotifyDesdePc());
    });

    test('encuentra por nombre o código', () {
      final porNombre = idiomasFiltrados('español');
      expect(porNombre.any((i) => i.codigo == 'es_ES'), isTrue);

      final porCodigo = idiomasFiltrados('ko_kr');
      expect(porCodigo.single.codigo, 'ko_KR');
    });

    test('muestra el nombre legible', () {
      expect(nombreIdiomaPreferido('fr_FR'), 'Francés (Francia)');
      expect(nombreIdiomaPreferido(''), startsWith('Automático'));
    });
  });

  group('detección de fallos de audio en librespot', () {
    test('reconoce errores de backend de audio', () {
      const lineas = [
        '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::rodio] '
            'Rodio play error: device no longer valid',
        '[2026-08-07T10:12:00Z ERROR librespot_playback::player] Audio Sink Error '
            'Write: NoDevice',
        'ERROR cpal: the requested output device is no longer available',
        '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::pulseaudio] '
            'PulseAudio failed to write: ConnectionTerminated',
        '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::alsa] '
            'Alsa error PCM write failed',
      ];
      for (final linea in lineas) {
        expect(esFalloDeAudio(linea), isTrue, reason: linea);
      }
    });

    test('ignora líneas normales o errores de red', () {
      const lineas = [
        '[2026-08-07T10:12:00Z INFO  librespot] librespot 0.8.0 loading',
        '[2026-08-07T10:12:00Z INFO  librespot_playback::audio_backend::rodio] '
            'Using audio device: Altavoces',
        '[2026-08-07T10:12:00Z ERROR librespot_core::session] Connection failed: '
            'IO error',
        '[2026-08-07T10:12:00Z WARN  librespot_playback::player] Loading track '
            'took a long time',
      ];
      for (final linea in lineas) {
        expect(esFalloDeAudio(linea), isFalse, reason: linea);
      }
    });
  });

  group('updater y versiones', () {
    test('compara versiones numéricamente', () {
      expect(Updater.esMasNueva('0.2.0', '0.1.0'), isTrue);
      expect(Updater.esMasNueva('1.0.0', '0.9.9'), isTrue);
      expect(Updater.esMasNueva('0.1.1', '0.1.0'), isTrue);
      expect(Updater.esMasNueva('0.1.0', '0.1.0'), isFalse);
      expect(Updater.esMasNueva('0.1.0', '0.2.0'), isFalse);
      expect(Updater.esMasNueva('0.10.0', '0.9.0'), isTrue);
      expect(Updater.esMasNueva('0.9.0', '0.10.0'), isFalse);
      expect(Updater.esMasNueva('1.0.0', '0.99.99'), isTrue);
      expect(Updater.esMasNueva('0.2', '0.1.9'), isTrue);
      expect(Updater.esMasNueva('0.1.0', '0.1'), isFalse);
      expect(Updater.esMasNueva('0.1.0+2', '0.1.0+1'), isTrue);
      expect(Updater.esMasNueva('', '0.1.0'), isFalse);
      expect(Updater.esMasNueva('vX.Y', '0.1.0'), isFalse);
    });

    test('la versión que anuncia el updater es la constante del proyecto', () {
      final updater = Updater();
      addTearDown(updater.dispose);
      expect(updater.versionActual, kVersion);
      expect(
        RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kVersion),
        isTrue,
        reason: 'kVersion debe ser x.y.z: el instalador la usa tal cual',
      );
    });

    test('la URI de última release apunta a apps/neofy sin doble codificación', () {
      expect(
        Updater.uriUltimaRelease.toString(),
        'https://git.neogex.xyz/api/v4/projects/apps%2Fneofy/releases/permalink/latest',
      );
    });

    test('buscar() detecta release en GitLab y descarga desde el paquete genérico', () async {
      final peticiones = <Uri>[];
      const pkgUrl =
          'https://git.neogex.xyz/api/v4/projects/10/packages/generic/neofy/9.9.9/NeoFy-9.9.9-windows-x64.exe';
      const directUrl =
          'https://git.neogex.xyz/apps/neofy/-/releases/v9.9.9/downloads/NeoFy-9.9.9-windows-x64.exe';
      final destinoEsperado =
          File(p.join(Directory.systemTemp.path, 'NeoFy-9.9.9-setup.exe'));
      addTearDown(() async {
        if (await destinoEsperado.exists()) {
          await destinoEsperado.delete().catchError((_) => destinoEsperado);
        }
      });

      final cliente = MockClient.streaming((request, _) async {
        peticiones.add(request.url);
        if (request.url == Updater.uriUltimaRelease) {
          final cuerpo = jsonEncode({
            'tag_name': 'v9.9.9',
            'description': 'Notas de prueba',
            'assets': {
              'links': [
                {
                  'name': 'Linux portable x86_64 (.tar.gz)',
                  'url':
                      'https://git.neogex.xyz/api/v4/projects/10/packages/generic/neofy/9.9.9/NeoFy-9.9.9-linux-x86_64.tar.gz',
                  'direct_asset_url':
                      'https://git.neogex.xyz/apps/neofy/-/releases/v9.9.9/downloads/NeoFy-9.9.9-linux-x86_64.tar.gz',
                  'link_type': 'package',
                },
                {
                  'name': 'Instalador Windows x64 (.exe)',
                  'url': pkgUrl,
                  'direct_asset_url': directUrl,
                  'link_type': 'package',
                },
              ],
            },
          });
          return http.StreamedResponse(
            Stream.value(utf8.encode(cuerpo)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == pkgUrl) {
          final bytes = utf8.encode('MZ-instalador-prueba');
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
            headers: {'content-type': 'application/octet-stream'},
          );
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });

      final updater = Updater(cliente: cliente, instalaSolo: true);
      addTearDown(updater.dispose);

      await updater.buscar();
      expect(updater.estado, EstadoActualizacion.disponible);
      expect(updater.versionDisponible, '9.9.9');
      expect(updater.notas, 'Notas de prueba');

      await updater.descargar();
      expect(updater.estado, EstadoActualizacion.listaParaInstalar);
      expect(peticiones.map((u) => u.toString()), [
        Updater.uriUltimaRelease.toString(),
        pkgUrl,
      ]);
      expect(await destinoEsperado.exists(), isTrue);
    });

    test('buscar() rechaza instaladores de hosts no fiables o sin HTTPS', () async {
      for (final urlMala in [
        'https://github.com/KOLPSE/NeoFy/releases/download/v9.9.9/NeoFy-9.9.9-windows-x64.exe',
        'http://git.neogex.xyz/api/v4/projects/10/packages/generic/neofy/9.9.9/NeoFy-9.9.9-windows-x64.exe',
      ]) {
        final cliente = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v9.9.9',
              'description': 'Notas',
              'assets': {
                'links': [
                  {
                    'name': 'Instalador Windows x64 (.exe)',
                    'url': urlMala,
                  },
                ],
              },
            }),
            200,
          ),
        );
        final updater = Updater(cliente: cliente, instalaSolo: true);
        addTearDown(updater.dispose);

        await updater.buscar();
        expect(updater.estado, EstadoActualizacion.fallo, reason: urlMala);
        expect(updater.error, contains('git.neogex.xyz'));
      }
    });

    test('buscar() marca al día ante 404 o versión igual o inferior', () async {
      final cliente404 = MockClient((_) async => http.Response('', 404));
      final updater404 = Updater(cliente: cliente404, instalaSolo: true);
      addTearDown(updater404.dispose);
      await updater404.buscar();
      expect(updater404.estado, EstadoActualizacion.alDia);

      final clienteIgual = MockClient(
        (_) async => http.Response(jsonEncode({'tag_name': 'v$kVersion'}), 200),
      );
      final updaterIgual = Updater(cliente: clienteIgual, instalaSolo: true);
      addTearDown(updaterIgual.dispose);
      await updaterIgual.buscar();
      expect(updaterIgual.estado, EstadoActualizacion.alDia);
    });

    test('buscar() falla si la release no incluye enlace .exe', () async {
      final cliente = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v9.9.9',
            'description': 'Solo Linux',
            'assets': {
              'links': [
                {
                  'name': 'Linux portable',
                  'url':
                      'https://git.neogex.xyz/api/v4/projects/10/packages/generic/neofy/9.9.9/NeoFy-9.9.9-linux-x86_64.tar.gz',
                },
              ],
            },
          }),
          200,
        ),
      );
      final updater = Updater(cliente: cliente, instalaSolo: true);
      addTearDown(updater.dispose);

      await updater.buscar();
      expect(updater.estado, EstadoActualizacion.fallo);
      expect(updater.error, contains('instalador'));
    });

    test('descargar() rechaza respuestas text/html para no guardar páginas web', () async {
      const pkgUrl =
          'https://git.neogex.xyz/api/v4/projects/10/packages/generic/neofy/9.9.9/NeoFy-9.9.9-windows-x64.exe';
      final cliente = MockClient.streaming((request, _) async {
        if (request.url == Updater.uriUltimaRelease) {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'tag_name': 'v9.9.9',
                  'description': 'Notas',
                  'assets': {
                    'links': [
                      {'name': 'Instalador Windows x64 (.exe)', 'url': pkgUrl},
                    ],
                  },
                }),
              ),
            ),
            200,
          );
        }
        return http.StreamedResponse(
          Stream.value(utf8.encode('<html><body>No binario</body></html>')),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final updater = Updater(cliente: cliente, instalaSolo: true);
      addTearDown(updater.dispose);

      await updater.buscar();
      expect(updater.estado, EstadoActualizacion.disponible);

      await updater.descargar();
      expect(updater.estado, EstadoActualizacion.fallo);
      expect(updater.error, contains('HTML'));
    });
  });

  group('perfil de artista del sidecar y listas propias', () {
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
              {'id': 'a1', 'name': 'Skrillex'},
            ],
            'album': {
              'name': 'Bangarang',
              'images': [
                {'url': 'caratula', 'width': 300},
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
              {'name': 'Skrillex'},
            ],
            'images': [
              {'url': 'disco', 'width': 300},
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
              {'url': 'diplo', 'width': 300},
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

    test('playlistsDelArtista solo deja las que son del propio artista', () {
      Playlist lista(String id, String owner) => Playlist(
        id: id,
        uri: 'spotify:playlist:$id',
        name: 'Lista $id',
        owner: owner,
        ownerId: 'u$id',
        art: null,
        trackCount: 10,
      );

      final suyas = playlistsDelArtista([
        lista('1', 'Skrillex'),
        lista('2', 'Spotify'),
        lista('3', 'skrillex'),
        lista('4', 'Someone else'),
      ], 'Skrillex');

      expect(suyas.map((p) => p.id), ['1', '3']);
      expect(playlistsDelArtista([lista('1', 'Skrillex')], ''), isEmpty);
    });
  });
}
