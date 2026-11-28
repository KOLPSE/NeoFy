import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/artistas_favoritos_store.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/carpetas_store.dart';
import 'package:neofy/core/followed_playlists_store.dart';
import 'package:neofy/core/home_store.dart';
import 'package:neofy/core/letras_service.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/metadata_sidecar.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/resource_monitor.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/tema_store.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/core/temporizador_apagado.dart';
import 'package:neofy/core/updater.dart';
import 'package:neofy/core/yt_auth.dart';
import 'package:neofy/ui/like_button.dart';
import 'package:neofy/ui/right_sidebar.dart';
import 'package:neofy/ui/shell.dart';

class _ConfigPrueba extends AppConfig {
  @override
  Future<void> save() async {}
}

class _AuthPrueba extends SpotifyAuth {
  _AuthPrueba(super.config);

  @override
  bool hasScope(String scope) => true;
}

class _ApiFalsa extends SpotifyApi {
  _ApiFalsa(super.auth);

  @override
  Future<ApiPage<Playlist>> myPlaylists({
    int limit = 50,
    int offset = 0,
  }) async => const ApiPage.empty();

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

class _InicioFalso extends HomeStore {
  _InicioFalso({required super.api, required super.auth});

  @override
  bool get puedeLeer => true;

  @override
  bool get cargado => true;

  @override
  Future<void> cargar({bool forzar = false}) async {}
}

Future<void> _sinAccion() async {}

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
      final auth = _AuthPrueba(config);
      final api = _ApiFalsa(auth);
      final player = PlayerController(api, config);
      final dir = Directory.systemTemp;
      final likes = LikedStore(api: api, auth: auth, directorio: dir);
      final favoritos = ArtistasFavoritosStore(api: api, auth: auth);
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

      // Copiar enlace está entre el título y el corazón, y anima a check y vuelve.
      String? copiadoPortapapeles;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiadoPortapapeles =
                  (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final tituloBox = t.getRect(find.text('Cero'));
      final copyFinder = find.byTooltip('Copiar enlace de la canción');
      final shareBox = t.getRect(copyFinder);
      final heartBox = t.getRect(find.byType(LikeButton));
      expect(shareBox.left, greaterThan(tituloBox.right - 1));
      expect(shareBox.right, lessThanOrEqualTo(heartBox.left + 1));

      await t.tap(copyFinder);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(copiadoPortapapeles, 'https://open.spotify.com/track/cero1');
      expect(find.byTooltip('Enlace copiado'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await t.pump(const Duration(milliseconds: 1600));
      await t.pumpAndSettle();
      expect(find.byTooltip('Copiar enlace de la canción'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

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

  testWidgets(
    'AppShell pliega y despliega el sidebar derecho al pulsar sus botones en escritorio y en ventana estrecha',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final config = _ConfigPrueba();
      final auth = _AuthPrueba(config);
      final api = _ApiFalsa(auth);
      final player = PlayerController(api, config);
      final temas = TemaStore(config);
      final settings = Settings(config);
      final dir = Directory.systemTemp;
      final likes = LikedStore(api: api, auth: auth, directorio: dir);
      final followed = FollowedPlaylistsStore(
        api: api,
        auth: auth,
        obtenerUserId: () => null,
      );
      final favoritos = ArtistasFavoritosStore(api: api, auth: auth);
      final carpetas = CarpetasStore(directorio: dir);
      final home = _InicioFalso(api: api, auth: auth);
      final sidecar = _SidecarFalso();
      final librespot = LibrespotManager(config);
      final ram = ResourceMonitor(pidsDeSidecars: () => const []);
      final updater = Updater();
      final ytAuth = YtAuth();

      addTearDown(() {
        temas.dispose();
        settings.dispose();
        player.dispose();
        likes.dispose();
        followed.dispose();
        favoritos.dispose();
        carpetas.dispose();
        home.dispose();
        sidecar.dispose();
        librespot.dispose();
        ram.dispose();
        updater.dispose();
      });

      final shell = AppShell(
        api: api,
        auth: auth,
        player: player,
        librespot: librespot,
        sidecar: sidecar,
        likes: likes,
        followed: followed,
        favoritos: favoritos,
        home: home,
        carpetas: carpetas,
        ram: ram,
        settings: settings,
        temas: temas,
        updater: updater,
        ytAuth: ytAuth,
        onSalirParaActualizar: _sinAccion,
        onReiniciarAudio: _sinAccion,
        onLogout: _sinAccion,
        onReauth: _sinAccion,
      );

      await t.pumpWidget(
        AnimatedBuilder(
          animation: temas,
          builder: (context, _) =>
              MaterialApp(theme: temas.themeDataOscuro, home: shell),
        ),
      );
      await t.pumpAndSettle();

      // En escritorio arranca desplegado (312 px) y con el botón Ocultar panel.
      expect(find.byTooltip('Ocultar panel'), findsOneWidget);
      expect(t.getSize(find.byType(RightSidebar)).width, 312);

      // Redimensionar sidebar izquierdo y derecho arrastrando y restablecer con doble clic.
      final sepIzq = find.byKey(const ValueKey('separador-sidebar-izq'));
      final sepDer = find.byKey(const ValueKey('separador-sidebar-der'));
      expect(sepIzq, findsOneWidget);
      expect(sepDer, findsOneWidget);

      final xIzqInicial = t.getCenter(sepIzq).dx;
      await t.drag(sepIzq, const Offset(60, 0));
      await t.pumpAndSettle();
      expect(t.getCenter(sepIzq).dx, greaterThan(xIzqInicial + 20));
      expect(settings.anchoSidebarIzquierdo, isNotNull);

      await t.drag(sepDer, const Offset(-70, 0));
      await t.pumpAndSettle();
      final anchoDerTrasArrastre = t.getSize(find.byType(RightSidebar)).width;
      expect(anchoDerTrasArrastre, greaterThan(330));
      expect(settings.anchoSidebarDerecho, closeTo(anchoDerTrasArrastre, 2));

      // Doble clic en ambos separadores restablece a los valores por defecto.
      final posIzq = t.getCenter(sepIzq);
      await t.tapAt(posIzq);
      await t.pump(const Duration(milliseconds: 40));
      await t.tapAt(posIzq);
      await t.pumpAndSettle();
      expect(settings.anchoSidebarIzquierdo, isNull);

      final posDer = t.getCenter(sepDer);
      await t.tapAt(posDer);
      await t.pump(const Duration(milliseconds: 40));
      await t.tapAt(posDer);
      await t.pumpAndSettle();
      expect(settings.anchoSidebarDerecho, isNull);
      expect(t.getSize(find.byType(RightSidebar)).width, 312);

      // Plegar desde el botón [>|]
      await t.tap(find.byTooltip('Ocultar panel'));
      await t.pumpAndSettle();
      expect(settings.sidebarDerechoPlegado, isTrue);
      expect(find.byTooltip('Ocultar panel'), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(t.getSize(find.byType(RightSidebar)).width, 24);

      // Volver a desplegar desde la franja <
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(settings.sidebarDerechoPlegado, isFalse);
      expect(find.byTooltip('Ocultar panel'), findsOneWidget);
      expect(t.getSize(find.byType(RightSidebar)).width, 312);

      // En ventana estrecha (< 980) arranca plegado y permite abrir/plegar flotando.
      await t.binding.setSurfaceSize(const Size(820, 560));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(t.getSize(find.byType(RightSidebar)).width, 24);

      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(find.byTooltip('Ocultar panel'), findsOneWidget);
      expect(t.getSize(find.byType(RightSidebar)).width, 312);

      await t.tap(find.byTooltip('Ocultar panel'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(t.getSize(find.byType(RightSidebar)).width, 24);
    },
  );
}
