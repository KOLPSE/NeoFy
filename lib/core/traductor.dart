import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:translator/translator.dart';

import 'app_config.dart';
import 'idiomas_spotify.dart';
import 'models.dart';

/// Traduce textos de la UI (español → idioma elegido) y biografías al vuelo.
class Traductor extends ChangeNotifier {
  Traductor({
    required this.localeEfectivo,
    this.simulado = false,
    Directory? directorio,
  })  : _directorio = directorio ?? appDataDir() {
    unawaited(_cargarCache());
  }

  /// Callable que devuelve el idioma que hay en uso ahora mismo.
  ///
  /// Es un campo y no un parametro suelto para poder leerlo en cualquier
  /// momento: el idioma puede cambiarse en caliente.
  final String Function() localeEfectivo;
  final Directory _directorio;
  final GoogleTranslator _motor = GoogleTranslator();
  final Map<String, String> _cache = {};

  final bool simulado;

  File get _fichero => File(p.join(_directorio.path, 'traducciones.json'));

  String get locale => localeEfectivo();

  /// Código ISO 639-1 del idioma objetivo (`es`, `en`, `fr`…).
  String get idiomaObjetivo => codigoIdiomaDeLocale(locale);

  /// La UI está escrita en español; solo traducimos si el objetivo no es español.
  bool get traduceUi => !simulado && idiomaObjetivo != 'es';

  String? cacheUi(String texto) {
    if (!traduceUi) return texto;
    final t = texto.trim();
    final fijada = traduccionUiFijada(idiomaObjetivo, t);
    if (fijada != null) return fijada;
    return _cache['ui|$idiomaObjetivo|$t'];
  }

  Future<void> _cargarCache() async {
    try {
      final f = _fichero;
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString());
      if (map is! Map<String, dynamic>) return;
      map.forEach((k, v) {
        if (v is String) _cache[k] = v;
      });
    } catch (_) {}
  }

  Future<void> _guardarCache() async {
    try {
      await _fichero.writeAsString(jsonEncode(_cache));
    } catch (_) {}
  }

  Future<String> traducirUi(String texto) async {
    final t = texto.trim();
    if (t.isEmpty || !traduceUi) return texto;
    final fijada = traduccionUiFijada(idiomaObjetivo, t);
    if (fijada != null) {
      _cache['ui|$idiomaObjetivo|$t'] = fijada;
      unawaited(_guardarCache());
      return fijada;
    }
    final clave = 'ui|$idiomaObjetivo|$t';
    final previa = _cache[clave];
    if (previa != null) return previa;
    try {
      final res = await _motor.translate(t, from: 'es', to: idiomaObjetivo);
      _cache[clave] = res.text;
      unawaited(_guardarCache());
      return res.text;
    } catch (_) {
      return texto;
    }
  }

  /// Biografías: elige idioma de Spotify o traduce si solo hay otro idioma.
  Future<String> biografia(String crudo, {Iterable<String> alternativas = const []}) async {
    final candidatas = [
      for (final b in alternativas)
        if (b.trim().isNotEmpty) b.trim(),
      if (crudo.trim().isNotEmpty) crudo.trim(),
    ];
    if (candidatas.isEmpty) return '';
    if (simulado) {
      return elegirBiografia(candidatas, locale: locale);
    }

    var bio = elegirBiografia(candidatas, locale: locale);
    if (bio.isEmpty) bio = candidatas.first;

    final objetivo = idiomaObjetivo;
    final puntaje = puntajeBiografia(bio, objetivo);
    if (objetivo == 'es' && puntaje >= 3) return bio;
    if (objetivo != 'es' && puntaje >= 5) return bio;

    final clave = 'bio|$objetivo|${bio.hashCode}';
    final previa = _cache[clave];
    if (previa != null) return previa;

    try {
      final origen = puntaje < 0 ? 'auto' : _idiomaOrigenProbable(bio);
      final res = await _motor.translate(bio, from: origen, to: objetivo);
      _cache[clave] = res.text;
      unawaited(_guardarCache());
      return res.text;
    } catch (_) {
      return bio;
    }
  }

  String _idiomaOrigenProbable(String texto) {
    var mejor = 'en';
    var puntaje = -999999;
    for (final lang in ['en', 'es', 'fr', 'de', 'pt', 'it', 'ja', 'ko']) {
      final p = puntajeBiografia(texto, lang);
      if (p > puntaje) {
        puntaje = p;
        mejor = lang;
      }
    }
    return mejor;
  }

  void refrescar() => notifyListeners();

  static final Traductor _sinScope = Traductor(
    localeEfectivo: () => 'es_ES',
    simulado: true,
  );
}

/// Google confunde algunos términos de la app; aquí van fijados por idioma.
String? traduccionUiFijada(String idioma, String texto) {
  const porIdioma = {
    'en': {
      'Temas': 'Themes',
      'Tema': 'Theme',
    },
  };
  return porIdioma[idioma]?[texto];
}

class TraductorScope extends InheritedNotifier<Traductor> {
  const TraductorScope({
    super.key,
    required Traductor super.notifier,
    required super.child,
  });

  static Traductor of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TraductorScope>();
    return scope?.notifier ?? Traductor._sinScope;
  }
}
