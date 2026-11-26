import 'package:flutter/material.dart';

import 'app_config.dart';
import 'temas.dart';
import 'temas_incluidos.dart';

final ValueNotifier<String?> caratulaDeFondo = ValueNotifier(null);

class TemaStore extends ChangeNotifier {
  TemaStore(this.config);

  final AppConfig config;

  ThemeData? _cacheClaro;
  ThemeData? _cacheOscuro;

  void _invalidarCache() {
    _cacheClaro = null;
    _cacheOscuro = null;
  }

  String get idSeleccionado => config.tema;

  List<Tema> get catalogo => List.unmodifiable(temasIncluidos);

  Tema? porId(String id) => temaIncluidoPorId(id);

  bool get siguiendoAlSistema => porId(idSeleccionado) == null;

  Tema get temaParaClaro =>
      siguiendoAlSistema ? temaNeoFyClaro : porId(idSeleccionado)!;

  Tema get temaParaOscuro =>
      siguiendoAlSistema ? temaNeoFyNocturno : porId(idSeleccionado)!;

  ThemeMode get modo {
    if (siguiendoAlSistema) return ThemeMode.system;
    return porId(idSeleccionado)!.esOscuro ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData get themeDataClaro => _cacheClaro ??= construirThemeData(temaParaClaro);

  ThemeData get themeDataOscuro => _cacheOscuro ??= construirThemeData(temaParaOscuro);

  Future<void> cargar() async {
    await _migrarTemaRetirado();
    _invalidarCache();
    notifyListeners();
  }

  /// Cualquier tema antiguo o personalizado que ya no exista se migra a su
  /// equivalente de NeoFy claro/oscuro (o al predeterminado) y se guarda.
  Future<void> _migrarTemaRetirado() async {
    final actual = config.tema;
    if (actual == kIdTemaDelSistema || temaIncluidoPorId(actual) != null) {
      return;
    }
    config.tema = kTemasRetirados[actual] ?? kTemaPorDefecto;
    _invalidarCache();
    await config.save();
  }

  Future<void> seleccionar(String id) async {
    final normalizado = (id == kIdTemaDelSistema || temaIncluidoPorId(id) != null)
        ? id
        : kTemaPorDefecto;
    if (config.tema == normalizado && config.temaElegido) return;
    config.tema = normalizado;
    config.temaElegido = true;
    _invalidarCache();
    notifyListeners();
    await config.save();
  }
}
