import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/artistas_favoritos_store.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/letras_service.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/metadata_sidecar.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/core/temporizador_apagado.dart';
import 'package:neofy/ui/like_button.dart';
import 'package:neofy/ui/right_sidebar.dart';

class _ConfigPrueba extends AppConfig {
  @override
  Future<void> save() async {}
}

class _ApiFalsa extends SpotifyApi {
  _ApiFalsa(super.auth);

  @override
  Future<List<Track>> queue() async => const [
        Track(
          id: 'next1',
          uri: 'spotify:track:next1',
          name: 'Siguiente canción',
          artists: 'Otro Artista',
          album: 'Disco Dos',
          artSmall: null,
          artMedium: null,
          durationMs: 180000,
          isLocal: false,
        ),
      ];
}

class _SidecarFalso extends MetadataSidecar {
  @override
  bool get puedeUsarse => true;

  @override
  Future<CreditosDePista?> creditosDePista(String trackId) async =>
      const CreditosDePista(
        personas: [
          CreditoPista(
            nombre: 'Dani Martín',
            artistaId: 'art1',
            artistaUri: 'spotify:artist:art1',
            roles: ['Main Artist', 'Composer', 'Producer'],
          ),
          CreditoPista(
            nombre: 'Luis Fernando Ochoa',
            roles: ['Composer'],
          ),
        ],
        fuentes: ['Sony Music'],
      );

  @override
  Future<InfoArtistaExtendida?> infoArtistaExtendida(String artistId) async =>
      InfoArtistaExtendida(
        id: 'art1',
        nombre: 'Dani Martín',
        verificado: true,
        oyentesMensuales: 1811092,
        biografia: 'Cantante español de pop rock.',
        conciertos: [
          ConciertoArtista(
            id: 'c1',
            ciudad: 'Barcelona',
            artista: 'Dani Martín',
            recinto: 'Palau Sant Jordi',
            fecha: DateTime(2027, 3, 19, 21, 0),
          ),
        ],
      );

  @override
  Future<CanvasDePista?> canvasDePista(String trackId) async =>
      const CanvasDePista();
}

void main() {
  test('formatea roles inclusivos, oyentes mensuales y fechas de gira', () {
    expect(formatearRolCredito('Main Artist'), 'Artista Principal');
    expect(formatearRolCredito('Composer'), 'Compositor/A');
    expect(formatearRolCredito('Producer'), 'Productor/A');
    expect(formatearRolCredito('Performer'), 'Intérprete');
    expect(formatearOyentesMensuales(1811092), '1.811.092');

    const credito = CreditoPista(
      nombre: 'Dani Martín',
      roles: ['Main Artist', 'Composer', 'Writer', 'Producer'],
    );
    expect(
      credito.rolesTexto,
      'Artista Principal • Compositor/A • Productor/A',
    );

    final concierto = ConciertoArtista(
      id: 'c1',
      ciudad: 'Barcelona',
      artista: 'Dani Martín',
      recinto: 'Palau Sant Jordi',
      fecha: DateTime(2027, 3, 19, 21, 0),
    );
    expect(concierto.mesCorto, 'Mar');
    expect(concierto.diaNumero, '19');
    expect(concierto.lineaDetalle, 'vie, 21:00 • Palau Sant Jordi');
  });

  testWidgets(
    'RightSidebar muestra secciones reales, compartir entre título y corazón, plegado con hover y menú funcional',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 820));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final config = _ConfigPrueba();
      final auth = SpotifyAuth(config);
      final api = _ApiFalsa(auth);
      final player = PlayerController(api, config);
      final dir = Directory.systemTemp;
      final likes = LikedStore(api: api, auth: auth, directorio: dir);
      final favoritos = ArtistasFavoritosStore(directorio: dir);
      final sidecar = _SidecarFalso();
      final letras = LetrasService(
        cliente: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'syncedLyrics':
                    '[00:01.00] Todo lo que vimos se nos fue\n[00:05.00] Soñé que siempre iría al lado\n[00:09.00] Eso que inventamos ya no es',
                'plainLyrics':
                    'Todo lo que vimos se nos fue\nSoñé que siempre iría al lado',
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final temporizador = TemporizadorApagado(player);
      addTearDown(() {
        player.dispose();
        likes.dispose();
        favoritos.dispose();
        sidecar.dispose();
        letras.dispose();
        temporizador.dispose();
      });

      const track = Track(
        id: 'cero1',
        uri: 'spotify:track:cero1',
        name: 'Cero',
        artists: 'Dani Martín',
        listaDeArtistas: [
          ArtistaDePista(
            id: 'art1',
            uri: 'spotify:artist:art1',
            name: 'Dani Martín',
          ),
        ],
        album: 'Dani Martín',
        artSmall: null,
        artMedium: null,
        durationMs: 220000,
        isLocal: false,
      );
      player.state = const Playback(
        track: track,
        isPlaying: false,
        progressMs: 2000,
        deviceId: 'd1',
        deviceName: 'NeoFy',
        volumePercent: 60,
        shuffle: false,
        repeat: 'off',
        contextUri: 'spotify:user:u1:collection',
      );
      player.currentUri.value = track.uri;
      player.progressMs.value = 2000;

      var plegadoClicks = 0;
      var expandidoClicks = 0;
      var colaClicks = 0;

      Widget construir({required bool plegado, bool expandido = false}) =>
          MaterialApp(
            theme: construirThemeData(temaNeoFyNocturno),
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(
                    child: expandido
                        ? RightSidebar(
                            api: api,
                            player: player,
                            likes: likes,
                            favoritos: favoritos,
                            sidecar: sidecar,
                            letras: letras,
                            temporizador: temporizador,
                            playlists: const [],
                            plegado: false,
                            expandido: true,
                            mostrarCola: false,
                            contextoTitulo: 'Canciones que te gustan',
                            onTogglePlegado: () => plegadoClicks++,
                            onToggleExpandido: () => expandidoClicks++,
                            onAbrirCola: () => colaClicks++,
                            onCerrarCola: () {},
                            onAbrirLetraCompleta: () {},
                            onAbrirArtista: (_) {},
                            onAbrirAlbum: (_) {},
                          )
                        : const SizedBox.expand(),
                  ),
                  if (!expandido)
                    RightSidebar(
                      api: api,
                      player: player,
                      likes: likes,
                      favoritos: favoritos,
                      sidecar: sidecar,
                      letras: letras,
                      temporizador: temporizador,
                      playlists: const [],
                      plegado: plegado,
                      expandido: false,
                      mostrarCola: false,
                      contextoTitulo: 'Canciones que te gustan',
                      onTogglePlegado: () => plegadoClicks++,
                      onToggleExpandido: () => expandidoClicks++,
                      onAbrirCola: () => colaClicks++,
                      onCerrarCola: () {},
                      onAbrirLetraCompleta: () {},
                      onAbrirArtista: (_) {},
                      onAbrirAlbum: (_) {},
                    ),
                ],
              ),
            ),
          );

      // 1. Estado plegado: flecha <, hover ensancha sin mostrar contenido, click abre.
      await t.pumpWidget(construir(plegado: true));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.text('Canciones que te gustan'), findsNothing);
      final anchoInicial = t.getSize(find.byType(RightSidebar)).width;
      expect(anchoInicial, 24);

      final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(t.getCenter(find.byIcon(Icons.chevron_left)));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(RightSidebar)).width, 38);
      expect(find.text('Canciones que te gustan'), findsNothing);

      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(plegadoClicks, 1);

      // 2. Estado compacto completo
      await t.pumpWidget(construir(plegado: false));
      await t.pumpAndSettle();

      expect(find.text('Canciones que te gustan'), findsOneWidget);
      expect(find.text('Cero'), findsOneWidget);
      expect(find.text('Vista previa de la letra'), findsOneWidget);
      expect(find.text('Todo lo que vimos se nos fue'), findsOneWidget);

      // Compartir está entre el título y el corazón.
      final tituloBox = t.getRect(find.text('Cero'));
      final shareBox = t.getRect(find.byTooltip('Compartir canción'));
      final heartBox = t.getRect(find.byType(LikeButton));
      expect(shareBox.left, greaterThan(tituloBox.right - 1));
      expect(shareBox.right, lessThanOrEqualTo(heartBox.left + 1));

      // Desplegar un poco la vista previa de la letra inline
      await t.tap(find.byTooltip('Desplegar un poco la letra'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Contraer vista previa'), findsOneWidget);

      // Menú de tres puntos (...) sin placeholders y con opciones reales
      await t.tap(find.byTooltip('Más opciones de reproducción'));
      await t.pumpAndSettle();
      expect(find.text('Añadir a lista'), findsOneWidget);
      expect(find.text('Temporizador de apagado'), findsOneWidget);
      expect(find.text('Ir a radio de la canción'), findsOneWidget);
      expect(find.text('Ver créditos'), findsOneWidget);
      expect(find.text('Empezar una Jam'), findsNothing);
      expect(find.text('Excluir de tu perfil de gustos'), findsNothing);

      // Cerrar menú y verificar secciones inferiores desplazando
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();

      await t.scrollUntilVisible(
        find.text('1.811.092 oyentes mensuales'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RightSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('1.811.092 oyentes mensuales'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);

      await t.scrollUntilVisible(
        find.text('A continuación en la cola'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RightSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Créditos'), findsOneWidget);
      expect(find.text('Luis Fernando Ochoa'), findsOneWidget);
      expect(find.text('Compositor/A'), findsOneWidget);
      expect(find.text('De gira'), findsOneWidget);
      expect(find.text('Barcelona'), findsOneWidget);
      expect(find.text('Mar'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      expect(find.text('vie, 21:00 • Palau Sant Jordi'), findsOneWidget);
      expect(find.text('Siguiente canción'), findsOneWidget);

      await t.tap(find.text('Abrir cola'));
      await t.pumpAndSettle();
      expect(colaClicks, 1);

      // Botón expandir vista
      await t.tap(find.byTooltip('Expandir vista'));
      await t.pumpAndSettle();
      expect(expandidoClicks, 1);

      // 3. Estado expandido
      await t.pumpWidget(construir(plegado: false, expandido: true));
      await t.pumpAndSettle();
      expect(find.byTooltip('Contraer vista'), findsOneWidget);
      expect(find.text('Información sobre el artista'), findsOneWidget);
    },
  );
}
