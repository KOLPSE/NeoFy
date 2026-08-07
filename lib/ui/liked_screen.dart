import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/auth.dart';
import '../core/liked_store.dart';
import '../core/models.dart';
import '../core/player_state.dart';
import '../core/spotify_api.dart';
import 'track_tile.dart';

/// "Canciones que te gustan".
///
/// No es una playlist: es la biblioteca guardada, vive en `GET /me/tracks` y no
/// aparece en `GET /me/playlists`. Por eso tiene pantalla propia en vez de
/// reutilizar `PlaylistScreen`.
///
/// La lista **no vive aquí sino en `LikedStore`**: el shell construye solo la
/// vista activa, así que al ir a una playlist y volver esta pantalla se
/// reconstruye entera, y con la lista dentro se rebajaba las ~60 páginas cada
/// vez. Aquí queda solo lo que sí es de la pantalla: el scroll y la ventana de
/// carátulas.
class LikedScreen extends StatefulWidget {
  const LikedScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.playlists,
    required this.likes,
    required this.onReauth,
  });

  final SpotifyApi api;
  final SpotifyAuth auth;
  final PlayerController player;
  final List<Playlist> playlists;
  final LikedStore likes;
  final Future<void> Function() onReauth;

  @override
  State<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends State<LikedScreen> {
  /// Alto fijo de cada fila. Hace falta un valor exacto para poder deducir por
  /// aritmética qué índice está mirando el usuario sin medir nada, y de paso
  /// evita que la lista mida 3.000 filas para saber cuánto scroll hay.
  /// 64 px es el alto de un `ListTile` `dense` de dos líneas.
  static const double _altoFila = 64;

  /// Cuántas filas a cada lado del centro llevan carátula. 25 arriba y 25 abajo
  /// dan una ventana de ~50 imágenes vivas como mucho, sin importar si la lista
  /// tiene 3.000 canciones.
  static const int _radioPortadas = 25;

  final _scroll = ScrollController();

  /// Índice que queda en mitad de la pantalla. Va en un `ValueNotifier` y no en
  /// el estado porque cambia con cada píxel de scroll: así solo se repintan las
  /// carátulas, no la lista entera.
  final ValueNotifier<int> _centro = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alHacerScroll);
    if (widget.auth.hasScope(kScopeLibraryRead)) {
      // Si ya está cargada de una visita anterior, esto no hace nada: es lo que
      // evita rebajarse la biblioteca cada vez que se vuelve a la pantalla.
      unawaited(widget.likes.cargarBiblioteca());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _centro.dispose();
    super.dispose();
  }

  void _alHacerScroll() {
    if (!_scroll.hasClients) return;
    final centro =
        ((_scroll.offset + _scroll.position.viewportDimension / 2) / _altoFila)
            .round();
    // Con histéresis: notificar en cada píxel repintaría las carátulas sin
    // parar y no cambiaría nada, porque la ventana es de 50.
    if ((centro - _centro.value).abs() >= 5) _centro.value = centro;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _addToPlaylist(Track track) async {
    final pl = await pickPlaylist(context, widget.playlists);
    if (pl == null) return;
    try {
      await widget.api.addToPlaylist(pl.id, [track.uri]);
      _toast('Añadida a ${pl.name}');
    } catch (e) {
      _toast('No se pudo añadir: $e');
    }
  }

  /// Reproduce toda la biblioteca desde la posición [offset].
  Future<void> _play({int? offset}) async {
    final userId = widget.player.currentUserId;
    if (userId == null) {
      _toast('Todavía no sé el id de tu cuenta; espera un momento.');
      return;
    }
    await widget.player
        .playContext(SpotifyApi.likedContextUri(userId), offset: offset);
  }

  String _textoProgreso(LikedStore likes) {
    if (likes.biblioteca.isEmpty) {
      return likes.cargandoBiblioteca ? 'Cargando…' : 'Tu biblioteca guardada';
    }
    if (!likes.cargandoBiblioteca) return '${likes.biblioteca.length} canciones';
    final total = likes.totalBiblioteca;
    return total == null
        ? 'Cargando… ${likes.biblioteca.length}'
        : 'Cargando… ${likes.biblioteca.length} de $total';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Solo se mira el permiso que necesita ESTA pantalla: si faltara otro (el
    // de editar favoritos, por ejemplo), la biblioteca se lee igual de bien.
    if (!widget.auth.hasScope(kScopeLibraryRead)) return _reauthNotice(theme);

    return AnimatedBuilder(
      animation: widget.likes,
      builder: (context, _) {
        final likes = widget.likes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                    ),
                    child: const Icon(Icons.favorite, color: Colors.white, size: 40),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Canciones que te gustan',
                            style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          _textoProgreso(likes),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: () => _play(),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Reproducir'),
                            ),
                            const SizedBox(width: 8),
                            // La biblioteca se carga una vez por sesión, así
                            // que hace falta una forma de pedirla otra vez
                            // cuando has guardado algo desde el móvil.
                            IconButton(
                              tooltip: 'Volver a cargar la biblioteca',
                              icon: const Icon(Icons.refresh),
                              onPressed: likes.cargandoBiblioteca
                                  ? null
                                  : () => unawaited(
                                      likes.cargarBiblioteca(forzar: true)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Barra fina mientras entran las ~60 páginas. Con total conocido va
            // progresando; sin él, indeterminada.
            if (likes.cargandoBiblioteca)
              LinearProgressIndicator(
                minHeight: 2,
                value: (likes.totalBiblioteca ?? 0) > 0
                    ? (likes.biblioteca.length / likes.totalBiblioteca!)
                        .clamp(0.0, 1.0)
                    : null,
              )
            else
              const Divider(height: 1),
            Expanded(
              child: likes.errorBiblioteca != null && likes.biblioteca.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(likes.errorBiblioteca!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    )
                  : _lista(likes),
            ),
          ],
        );
      },
    );
  }

  Widget _lista(LikedStore likes) {
    // La uri que suena se escucha aquí y no en el `build` general: así cambiar
    // de canción mueve el título verde a la siguiente, y los sondeos que no
    // cambian nada no repintan la lista.
    return ValueListenableBuilder<String?>(
      valueListenable: widget.player.currentUri,
      builder: (context, currentUri, _) => ListView.builder(
        controller: _scroll,
        // Alto fijo: con miles de filas evita que Flutter mida cada una, y
        // permite deducir el índice central a partir del scroll para saber a
        // quién le toca carátula.
        itemExtent: _altoFila,
        itemCount: likes.biblioteca.length,
        itemBuilder: (context, i) {
          final t = likes.biblioteca[i];
          final tile = TrackActions(
            onPlay: () => _play(offset: i),
            onQueue: () async {
              await widget.player.addToQueue(t.uri);
              _toast('Añadida a la cola');
            },
            onAddToPlaylist: () => _addToPlaylist(t),
          );
          // Solo se repinta la fila cuando entra o sale de la ventana de
          // carátulas; el resto del scroll no la toca.
          return ValueListenableBuilder<int>(
            valueListenable: _centro,
            builder: (context, centro, _) => TrackTile(
              track: t,
              likes: likes,
              leadingNumber: i + 1,
              isCurrent: currentUri != null && currentUri == t.uri,
              showArt: (i - centro).abs() <= _radioPortadas,
              actions: tile,
            ),
          );
        },
      ),
    );
  }

  /// La sesión guardada se concedió antes de que la app pidiera
  /// `user-library-read`, y un token viejo no gana permisos al renovarse.
  Widget _reauthNotice(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Hace falta un permiso más', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tus canciones guardadas no son una playlist: van por otro sitio de '
                'la API y necesitan el permiso «user-library-read», que tu sesión '
                'actual no incluye.\n\n'
                'Un inicio de sesión antiguo no gana permisos al renovarse, así que '
                'hay que volver a pasar por la pantalla de Spotify una vez. No '
                'perderás nada.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: widget.onReauth,
                icon: const Icon(Icons.refresh),
                label: const Text('Volver a iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
