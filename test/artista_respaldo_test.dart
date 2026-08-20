import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/spotify_api.dart';

class _AuthDeMentira extends SpotifyAuth {
  _AuthDeMentira() : super(AppConfig());

  @override
  Future<String> accessToken() async => 'token-de-mentira';
}

const _json = {'content-type': 'application/json'};

http.Response _ok(Object cuerpo) =>
    http.Response(jsonEncode(cuerpo), 200, headers: _json);

http.Response _prohibido() => http.Response(
      jsonEncode({
        'error': {'status': 403, 'message': 'Forbidden'}
      }),
      403,
      headers: _json,
    );

Map<String, dynamic> _disco(String id, List<String> canciones) => {
      'id': id,
      'name': 'Disco $id',
      'images': [
        {'url': 'http://art/$id', 'width': 640},
      ],
      'tracks': {
        'items': [
          for (final c in canciones)
            {
              'id': c,
              'uri': 'spotify:track:$c',
              'name': c,
              'duration_ms': 180000,
              'artists': [
                {'name': 'Manu Cort'}
              ],
            },
        ],
      },
    };

void main() {
  late List<String> pedidas;

  SpotifyApi apiCon(Map<String, http.Response Function()> rutas) {
    pedidas = [];
    return SpotifyApi(
      _AuthDeMentira(),
      cliente: MockClient((req) async {
        pedidas.add(req.url.path);
        final ruta = rutas[req.url.path];
        if (ruta == null) return http.Response('{}', 404, headers: _json);
        return ruta();
      }),
    );
  }

  group('las populares del artista, capadas en Modo Desarrollo', () {
    test('si Spotify las prohíbe, se reconstruyen desde sus discos', () async {
      final api = apiCon({
        '/v1/artists/A1/top-tracks': _prohibido,
        '/v1/artists/A1/albums': () => _ok({
              'items': [
                {'id': 'd1'},
                {'id': 'd2'},
                {'id': 'd1'},
              ],
            }),
        '/v1/albums/d1': () => _ok(_disco('d1', ['Uno', 'Dos'])),
        '/v1/albums/d2': () => _ok(_disco('d2', ['Uno', 'Tres'])),
      });

      final pistas = await api.artistTopTracks('A1');

      expect([for (final t in pistas) t.name], ['Uno', 'Dos', 'Tres']);
      expect(pistas.first.artMedium, 'http://art/d1');
      expect(pistas.first.uri, 'spotify:track:Uno');
      expect(pedidas.where((p) => p.startsWith('/v1/albums/')), hasLength(2));
    });

    test('un disco que falla no se lleva por delante a los demás', () async {
      final api = apiCon({
        '/v1/artists/A1/top-tracks': _prohibido,
        '/v1/artists/A1/albums': () => _ok({
              'items': [
                {'id': 'roto'},
                {'id': 'd2'},
              ],
            }),
        '/v1/albums/roto': () => http.Response('{}', 500, headers: _json),
        '/v1/albums/d2': () => _ok(_disco('d2', ['Tres'])),
      });

      expect([for (final t in await api.artistTopTracks('A1')) t.name], ['Tres']);
    });

    test('sin discos que enseñar no se inventa una lista', () async {
      final api = apiCon({
        '/v1/artists/A1/top-tracks': _prohibido,
        '/v1/artists/A1/albums': () => _ok({'items': []}),
      });

      expect(await api.artistTopTracks('A1'), isEmpty);
    });

    test('el respaldo se puede desactivar para no gastar cuota', () async {
      final api = apiCon({'/v1/artists/A1/top-tracks': _prohibido});

      await expectLater(
        api.artistTopTracks('A1', discosDeRespaldo: 0),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'es 403', isTrue)),
      );
      expect(pedidas, ['/v1/artists/A1/top-tracks']);
    });

    test('si vuelven a funcionar, no se pide ni un disco', () async {
      final api = apiCon({
        '/v1/artists/A1/top-tracks': () => _ok({
              'tracks': [
                {
                  'id': 'p1',
                  'uri': 'spotify:track:p1',
                  'name': 'La popular',
                  'duration_ms': 200000,
                },
              ],
            }),
      });

      final pistas = await api.artistTopTracks('A1');

      expect([for (final t in pistas) t.name], ['La popular']);
      expect(pedidas, ['/v1/artists/A1/top-tracks']);
    });

    test('el aleatorio inteligente se queda en un disco por artista', () async {
      final api = apiCon({
        '/v1/artists/A1/top-tracks': _prohibido,
        '/v1/artists/A1/albums': () => _ok({
              'items': [
                {'id': 'd1'},
                {'id': 'd2'},
                {'id': 'd3'},
              ],
            }),
        '/v1/albums/d1': () => _ok(_disco('d1', ['Uno'])),
        '/v1/albums/d2': () => _ok(_disco('d2', ['Dos'])),
        '/v1/albums/d3': () => _ok(_disco('d3', ['Tres'])),
      });

      await api.artistTopTracks('A1', discosDeRespaldo: 1);

      expect(pedidas.where((p) => p.startsWith('/v1/albums/')), ['/v1/albums/d1']);
    });
  });
}
