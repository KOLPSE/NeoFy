import 'dart:async';
import 'dart:io';

import 'art_cache.dart';
import 'models.dart';

class EstadoDelSistema {
  const EstadoDelSistema({
    required this.track,
    required this.sonando,
    required this.posicionMs,
    required this.puedeSaltar,
    required this.puedeVolver,
    required this.volumen,
  });

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

  final int? volumen;

  String get estadoDeReproduccion {
    if (track == null) return 'Stopped';
    return sonando ? 'Playing' : 'Paused';
  }
}

File? ficheroDeCaratula(Track track) {
  for (final url in [track.artMedium, track.artSmall]) {
    if (url == null) continue;
    final fichero = ArtCache.ficheroSiEstaEnDisco(url);
    if (fichero != null) return fichero;
  }
  return null;
}

String? caratulaEnDisco(Track track) =>
    ficheroDeCaratula(track)?.uri.toString();

class DescargadorDeCaratula {
  DescargadorDeCaratula(this._uriQueSuena);

  final String? Function() _uriQueSuena;

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
