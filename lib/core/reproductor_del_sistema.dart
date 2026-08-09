import 'dart:async';
import 'dart:io';

import 'art_cache.dart';
import 'models.dart';

/// Lo que los controles del sistema necesitan saber del reproductor.
///
/// Está aquí y no dentro de [MprisService] o de [SmtcService] porque los dos
/// piden exactamente lo mismo: qué suena, si suena, por dónde va y qué botones
/// tienen sentido. Que sea el mismo objeto es lo que permite que `main.dart` lo
/// construya una vez y que las dos plataformas queden imposibilitadas de
/// enseñar cosas distintas.
class EstadoDelSistema {
  const EstadoDelSistema({
    required this.track,
    required this.sonando,
    required this.posicionMs,
    required this.puedeSaltar,
    required this.puedeVolver,
    required this.volumen,
  });

  /// Sin nada sonando. Es lo que se manda al cerrar sesión o al salir, para que
  /// el escritorio no se quede enseñando la última canción de una app que ya no
  /// está.
  static const vacio = EstadoDelSistema(
    track: null,
    sonando: false,
    posicionMs: 0,
    puedeSaltar: false,
    puedeVolver: false,
    volumen: null,
  );

  final Track? track;
  final bool sonando;
  final int posicionMs;
  final bool puedeSaltar;
  final bool puedeVolver;

  /// 0..100, como lo da la Web API. MPRIS lo quiere de 0.0 a 1.0; el panel de
  /// Windows no lo usa (allí el volumen es el del sistema, no el del
  /// reproductor).
  final int? volumen;

  /// `Playing`, `Paused` o `Stopped`, que son los tres valores que admite la
  /// especificación de MPRIS y los tres que distingue también Windows.
  String get estadoDeReproduccion {
    if (track == null) return 'Stopped';
    return sonando ? 'Playing' : 'Paused';
  }
}

/// El fichero de la carátula de [track] que **ya esté descargado**, o `null`.
///
/// Se sirve desde disco para que el escritorio la pinte sin bajar nada y sin
/// gastar cuota: no se puede esperar a una descarga para contestar por D-Bus, y
/// dar la url `http` haría que el escritorio (o Windows) se la bajara por su
/// cuenta.
///
/// ⚠️ **Se prueban las dos variantes, y esa es la corrección de un fallo real**:
/// unas carátulas salían en el reproductor del sistema y otras no, sin patrón
/// aparente. La causa es que `ArtImage` elige qué variante descarga **según los
/// píxeles reales** en los que va a pintarla: las filas de una lista caben en la
/// de 64 y las tarjetas de la portada necesitan la de 300. Pidiendo aquí solo la
/// mediana, las canciones que solo se habían visto en una lista no tenían ese
/// fichero y se quedaban sin carátula.
File? ficheroDeCaratula(Track track) {
  for (final url in [track.artMedium, track.artSmall]) {
    if (url == null) continue;
    final fichero = ArtCache.ficheroSiEstaEnDisco(url);
    if (fichero != null) return fichero;
  }
  return null;
}

/// Lo mismo, como url `file://`, que es la forma en la que MPRIS quiere la
/// carátula. Windows, en cambio, quiere la ruta a secas.
String? caratulaEnDisco(Track track) =>
    ficheroDeCaratula(track)?.uri.toString();

/// Se trae la carátula que falta y avisa cuando ya está en disco.
///
/// Hace falta porque el escritorio no sabe volver a preguntar: si el anuncio del
/// cambio de canción va sin carátula, ahí se queda el hueco para siempre. Así
/// que cuando no está en disco se pide y se vuelve a anunciar al llegar.
class DescargadorDeCaratula {
  DescargadorDeCaratula(this._uriQueSuena);

  /// Qué está sonando **ahora mismo**. Bajar tarda, y para entonces puede estar
  /// sonando otra cosa: reanunciar la carátula de la canción anterior dejaría el
  /// escritorio desincronizado.
  final String? Function() _uriQueSuena;

  /// Uri de la canción cuya carátula se está bajando, para no pedir la misma una
  /// y otra vez en cada sondeo mientras la descarga está en curso.
  String? _bajando;

  void asegurar(Track track, void Function() alLlegar) {
    final url = track.artMedium ?? track.artSmall;
    if (url == null || _bajando == track.uri) return;
    _bajando = track.uri;
    unawaited(ArtCache.file(url).then((_) {
      _bajando = null;
      if (_uriQueSuena() != track.uri) return;
      alLlegar();
    }).catchError((_) {
      _bajando = null;
    }));
  }
}
