import 'dart:async';

import 'package:flutter/material.dart';

import '../core/yt_home_store.dart';
import '../core/yt_models.dart';
import '../core/yt_player.dart';
import 'art_image.dart';
import 'tira_horizontal.dart';
import 'yt_acciones.dart';

/// Pantalla genérica de secciones: sirve igual para Inicio, Explorar y
/// Biblioteca, que por dentro son el mismo parseo con distinto origen (ver
/// `YtHomeStore`).
///
/// Las filas usan la misma [TiraHorizontal] que la portada de NeoFy, y por el
/// mismo motivo: una `ListView` horizontal dentro de una vertical es un
/// callejón sin salida con un ratón — no se puede arrastrar, la rueda mueve la
/// página en vez de la tira, y nada indica que haya más contenido a la derecha.
/// Aquí se veía tal cual: la fila se cortaba en el borde y no había forma de
/// llegar al resto.
class YtBrowseScreen extends StatefulWidget {
  const YtBrowseScreen({
    super.key,
    required this.store,
    required this.player,
    required this.acciones,
    required this.tituloVacio,
  });

  final YtHomeStore store;
  final YtPlayer player;
  final YtAcciones acciones;

  /// Qué decir si la carga fue bien pero no hay ninguna sección — la
  /// biblioteca de una cuenta nueva, por ejemplo.
  final String tituloVacio;

  @override
  State<YtBrowseScreen> createState() => _YtBrowseScreenState();
}

/// Medidas de la tarjeta. Sueltas y no dentro del widget porque el alto de la
/// tira hay que calcularlo fuera, igual que en `home_screen.dart`.
const double _ladoTarjeta = 132;
const double _margenTarjeta = 4;
const double _huecoTarjeta = 6;

/// Alto exacto que necesita una tira: carátula, hueco y las líneas de texto,
/// **escaladas como las escale el sistema**. A ojo se corta en cuanto alguien
/// tiene el tamaño de letra subido.
double _altoDeTira(BuildContext context, TextStyle estilo, int lineas) {
  final tamano = MediaQuery.textScalerOf(context).scale(estilo.fontSize ?? 14);
  final altoDeLinea = tamano * (estilo.height ?? 1.4);
  return _margenTarjeta * 2 +
      _ladoTarjeta +
      _huecoTarjeta +
      (altoDeLinea * lineas).ceilToDouble();
}

class _YtBrowseScreenState extends State<YtBrowseScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.store.cargarSiHaceFalta());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.player]),
      builder: (context, _) {
        final store = widget.store;
        if (store.cargando && store.vacio) {
          return const Center(child: CircularProgressIndicator());
        }
        if (store.error != null && store.vacio) {
          return _centro(
            theme,
            store.error!,
            esError: true,
            onReintentar: () => unawaited(store.cargar()),
          );
        }
        if (store.vacio) {
          return _centro(
            theme,
            widget.tituloVacio,
            onReintentar: () => unawaited(store.cargar()),
          );
        }
        // Tres líneas: título y hasta dos de subtítulo ("Lista • 42
        // canciones" se parte con frecuencia).
        final estilo = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
        final alto = _altoDeTira(context, estilo, 3);
        return RefreshIndicator(
          onRefresh: store.cargar,
          child: ListView(
            // Sin margen lateral: lo pone la propia tira, para que las flechas
            // queden sobre el borde y no flotando dentro del contenido.
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              for (final seccion in store.secciones) ...[
                if (seccion.titulo.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(seccion.titulo, style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: 12),
                ],
                TiraHorizontal(
                  alto: alto,
                  centroDeFlechas: _margenTarjeta + _ladoTarjeta / 2,
                  itemCount: seccion.items.length,
                  itemBuilder: (context, i) {
                    final item = seccion.items[i];
                    return TarjetaDeYtItem(
                      item: item,
                      cargando: item.videoId != null &&
                          widget.player.resolviendo == item.videoId,
                      sonando: item.videoId != null &&
                          widget.player.actual?.videoId == item.videoId,
                      onTap: () => unawaited(widget.acciones.pulsar(context, item)),
                      onReproducir: item.esCancion || !item.esNavegable
                          ? null
                          : () =>
                              unawaited(widget.acciones.reproducirColeccion(context, item)),
                    );
                  },
                ),
                const SizedBox(height: 28),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _centro(
    ThemeData theme,
    String texto, {
    bool esError = false,
    required VoidCallback onReintentar,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                texto,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: esError
                    ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)
                    : theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh),
                label: Text(esError ? 'Reintentar' : 'Recargar'),
              ),
            ],
          ),
        ),
      );
}

/// La tarjeta de un elemento de una tira. Pública para poder probarla suelta:
/// `YtPlayer` no se puede construir en un test (media_kit necesita sus libs
/// nativas), y lo que hay que fijar aquí no depende de él — que pulsar la
/// tarjeta **abra** la lista y que solo el botón de la esquina reproduzca.
class TarjetaDeYtItem extends StatefulWidget {
  const TarjetaDeYtItem({
    super.key,
    required this.item,
    required this.cargando,
    required this.sonando,
    required this.onTap,
    required this.onReproducir,
  });

  final YtItem item;
  final bool cargando;
  final bool sonando;

  /// Pulsar la tarjeta: una canción suena, una lista o un álbum **se abren**.
  final VoidCallback onTap;

  /// Solo en listas y álbumes: reproducir sin entrar. `null` en lo demás.
  final VoidCallback? onReproducir;

  @override
  State<TarjetaDeYtItem> createState() => _TarjetaState();
}

class _TarjetaState extends State<TarjetaDeYtItem> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    // Los artistas los pinta redondos el cliente oficial, y la forma es la
    // pista más rápida para saber que eso no es un disco.
    final radio = item.tipo == YtTipo.artista ? _ladoTarjeta / 2 : 8.0;
    final abrible = widget.onReproducir != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Tooltip(
        message: abrible ? 'Abrir "${item.titulo}"' : item.titulo,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(_margenTarjeta),
            child: SizedBox(
              width: _ladoTarjeta,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      ArtImage(url: item.miniatura, size: _ladoTarjeta, radius: radio),
                      if (widget.cargando)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        )
                      // ⚠️ El play va **en la esquina**, no centrado. Centrado
                      // se comía el sitio donde todo el mundo pulsa para
                      // entrar en una lista, así que reproducía en vez de
                      // abrirla — y no había forma de ver qué canciones tenía.
                      else if (abrible && _encima)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: _BotonPlay(
                            // Con clave porque el distintivo de una canción usa
                            // este mismo icono: sin ella, un test no puede
                            // distinguir el botón real del adorno.
                            key: claveDelPlayDeTarjeta,
                            onPressed: widget.onReproducir!,
                          ),
                        )
                      else
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.sonando ? Icons.graphic_eq : iconoDe(item.tipo),
                              size: 14,
                              color: widget.sonando
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: _huecoTarjeta),
                  Text(
                    item.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.sonando ? theme.colorScheme.primary : null,
                    ),
                  ),
                  Text(
                    item.subtitulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Identifica el botón de reproducir de una tarjeta. El distintivo de esquina
/// de una canción usa el mismo `Icons.play_arrow`, así que buscar por icono no
/// distingue el botón del adorno.
const Key claveDelPlayDeTarjeta = Key('yt-play-tarjeta');

class _BotonPlay extends StatelessWidget {
  const _BotonPlay({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Reproducir sin abrir',
      child: Material(
        color: theme.colorScheme.primary,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.play_arrow, size: 20, color: theme.colorScheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
