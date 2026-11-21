import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/idiomas_spotify.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/metadata_sidecar.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/updater.dart';
import 'package:neofy/core/volumen_local.dart';
import 'package:neofy/ui/artist_screen.dart';

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
