import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/artistas_favoritos_store.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/carpetas_store.dart';
import 'package:neofy/core/followed_playlists_store.dart';
import 'package:neofy/core/home_store.dart';
import 'package:neofy/core/librespot.dart';
import 'package:neofy/core/liked_store.dart';
import 'package:neofy/core/metadata_sidecar.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/resource_monitor.dart';
import 'package:neofy/core/settings.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/tema_store.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:neofy/core/updater.dart';
import 'package:neofy/core/yt_auth.dart';
import 'package:neofy/ui/shell.dart';

class _ConfiguracionDePrueba extends AppConfig {
  @override
  Future<void> save() async {}
}

class _ApiDePrueba extends SpotifyApi {
  _ApiDePrueba(super.auth);

  @override
  Future<ApiPage<Playlist>> myPlaylists({
    int limit = 50,
    int offset = 0,
  }) async => const ApiPage.empty();

  @override
  Future<List<Track>> queue() async => const [];
}

class _InicioDePrueba extends HomeStore {
  _InicioDePrueba({required super.api, required super.auth});

  @override
  bool get puedeLeer => true;

  @override
  bool get cargado => true;

  @override
  Future<void> cargar({bool forzar = false}) async {}
}

Future<void> _sinAccion() async {}

void main() {
  test('un perfil sin product conserva la reproducción normal de Spotify', () {
    final config = _ConfiguracionDePrueba();
    final player = PlayerController(_ApiDePrueba(SpotifyAuth(config)), config);
    addTearDown(player.dispose);

    player.aplicarPerfilSpotify({'id': 'cuenta', 'product': 'free'});
    expect(player.premiumChecked, isTrue);
    expect(player.isPremium, isFalse);

    player.aplicarPerfilSpotify({'id': 'cuenta', 'display_name': 'Nombre'});
    expect(player.currentUserId, 'cuenta');
    expect(player.currentDisplayName, 'Nombre');
    expect(player.premiumChecked, isFalse);
    expect(player.isPremium, isTrue);

    player.aplicarPerfilSpotify({'id': 'cuenta', 'product': 'premium'});
    expect(player.premiumChecked, isTrue);
    expect(player.isPremium, isTrue);
  });

  testWidgets('Nocturno y Material muestran distribuciones distintas', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(820, 560));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final config = _ConfiguracionDePrueba();
    final auth = SpotifyAuth(config);
    final api = _ApiDePrueba(auth);
    final player = PlayerController(api, config);
    final temas = TemaStore(config);
    final temporal = Directory.systemTemp;
    final home = _InicioDePrueba(api: api, auth: auth)
      ..recientes = const [
        Track(
          id: 'historial',
          uri: 'spotify:track:historial',
          name: 'Una canción del historial',
          artists: 'Artista',
          album: 'Álbum',
          artSmall: null,
          artMedium: null,
          durationMs: 200000,
          isLocal: false,
        ),
      ];
    var cierresDeSesion = 0;
    final shell = AppShell(
      api: api,
      auth: auth,
      player: player,
      librespot: LibrespotManager(config),
      sidecar: MetadataSidecar(),
      likes: LikedStore(api: api, auth: auth, directorio: temporal),
      followed: FollowedPlaylistsStore(
        api: api,
        auth: auth,
        obtenerUserId: () => null,
      ),
      favoritos: ArtistasFavoritosStore(directorio: temporal),
      carpetas: CarpetasStore(directorio: temporal),
      home: home,
      ram: ResourceMonitor(pidsDeSidecars: () => const []),
      settings: Settings(config),
      temas: temas,
      updater: Updater(),
      ytAuth: YtAuth(),
      onSalirParaActualizar: _sinAccion,
      onReiniciarAudio: _sinAccion,
      onLogout: () async {
        cierresDeSesion++;
      },
      onReauth: _sinAccion,
    );
    addTearDown(temas.dispose);
    addTearDown(player.dispose);

    await t.pumpWidget(
      AnimatedBuilder(
        animation: temas,
        builder: (context, _) =>
            MaterialApp(theme: temas.themeDataOscuro, home: shell),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('Última escucha'), findsOneWidget);
    final buscar = find.byType(TextField);
    expect(buscar, findsOneWidget);
    expect(
      t.getTopLeft(buscar).dy,
      lessThan(t.getTopLeft(find.text('Biblioteca')).dy),
    );

    final avatar = find.byTooltip('Cuenta de Spotify');
    expect(find.text('Ajustes'), findsNothing);
    expect(find.byTooltip('Salir'), findsNothing);
    await t.tap(avatar);
    await t.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Cuenta')).dy,
      greaterThan(t.getBottomLeft(avatar).dy),
    );
    expect(
      t.getTopRight(find.widgetWithText(MenuItemButton, 'Ajustes')).dx,
      closeTo(t.getTopRight(avatar).dx - 8, 10),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Ajustes'), findsNothing);

    await t.tap(avatar);
    await t.pumpAndSettle();
    await t.tap(find.text('Ajustes'));
    await t.pumpAndSettle();
    expect(find.text('Apariencia e idioma'), findsOneWidget);
    await t.tap(find.byTooltip('Atrás'));
    await t.pumpAndSettle();
    expect(find.text('Última escucha'), findsOneWidget);

    await t.tap(find.byTooltip('Cola'));
    await t.pumpAndSettle();
    expect(find.text('La cola está vacía.'), findsOneWidget);
    expect(find.text('Última escucha'), findsOneWidget);
    await t.tap(find.byTooltip('Cerrar cola'));
    await t.pumpAndSettle();
    expect(find.text('La cola está vacía.'), findsNothing);

    await t.binding.setSurfaceSize(const Size(1920, 1000));
    await t.pumpAndSettle();
    final contraer = find.byTooltip('Contraer barra lateral');
    final posicion = t.getCenter(contraer);
    await t.tap(contraer);
    await t.pumpAndSettle();
    final expandir = find.byTooltip('Expandir barra lateral');
    expect(expandir, findsOneWidget);
    expect(t.getCenter(expandir), posicion);
    expect(find.text('Ajustes'), findsNothing);
    expect(find.byTooltip('Salir'), findsNothing);
    await t.tap(expandir);
    await t.pump();
    await t.pump(const Duration(milliseconds: 55));
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    await t.pumpAndSettle();

    await t.tap(avatar);
    await t.pumpAndSettle();
    await t.tap(find.text('Cerrar sesión'));
    await t.pumpAndSettle();
    expect(cierresDeSesion, 1);

    await t.binding.setSurfaceSize(const Size(820, 560));
    await temas.seleccionar(temaMaterialOscuro.id);
    await t.pumpAndSettle();
    expect(find.text('Biblioteca'), findsNothing);
    expect(find.text('Última escucha'), findsNothing);
    expect(find.text('Una canción del historial'), findsOneWidget);
    expect(buscar, findsNothing);
    expect(find.text('Buscar'), findsOneWidget);
  });
}
