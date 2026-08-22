import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'temas.dart';
import 'temas_incluidos.dart';

final ValueNotifier<String?> caratulaDeFondo = ValueNotifier(null);

class TemaStore extends ChangeNotifier {
  TemaStore(this.config);

  final AppConfig config;

  final List<Tema> _deDisco = [];
  final Map<String, String> _fallos = {};
  final Map<String, List<String>> _avisos = {};
  final Set<String> _fuentesCargadas = {};

  StreamSubscription<FileSystemEvent>? _vigilante;
  Timer? _rebote;

  List<Tema> get temasDeDisco => List.unmodifiable(_deDisco);

  Map<String, String> get fallos => Map.unmodifiable(_fallos);

  Map<String, List<String>> get avisos => Map.unmodifiable(_avisos);

  String get idSeleccionado => config.tema;

  List<Tema> get catalogo {
    final porId = <String, Tema>{};
    for (final tema in temasIncluidos) {
      porId[tema.id] = tema;
    }
    for (final tema in _deDisco) {
      porId[tema.id] = tema;
    }
    return porId.values.toList();
  }

  Tema? porId(String id) {
    for (final tema in _deDisco) {
      if (tema.id == id) return tema;
    }
    return temaIncluidoPorId(id);
  }

  bool get siguiendoAlSistema => porId(idSeleccionado) == null;

  Tema get temaParaClaro =>
      siguiendoAlSistema ? temaClaro : porId(idSeleccionado)!;

  Tema get temaParaOscuro =>
      siguiendoAlSistema ? temaOscuro : porId(idSeleccionado)!;

  ThemeMode get modo {
    if (siguiendoAlSistema) return ThemeMode.system;
    return porId(idSeleccionado)!.esOscuro ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData get themeDataClaro => construirThemeData(temaParaClaro);

  ThemeData get themeDataOscuro => construirThemeData(temaParaOscuro);

  Future<void> cargar() async {
    await recargar(notificar: false);
    await _cargarFuentes();
    notifyListeners();
  }

  Future<void> recargar({bool notificar = true}) async {
    final carpeta = carpetaDeTemas();
    final encontrados = <Tema>[];
    _fallos.clear();
    _avisos.clear();

    if (carpeta.existsSync()) {
      final entradas = carpeta.listSync().whereType<Directory>().toList()
        ..sort((a, b) => p.basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()));
      for (final entrada in entradas) {
        final nombre = p.basename(entrada.path);
        try {
          final cargado = leerTemaDeCarpeta(entrada);
          encontrados.add(cargado.tema);
          if (cargado.avisos.isNotEmpty) {
            _avisos[cargado.tema.id] = cargado.avisos;
          }
        } on ErrorDeTema catch (e) {
          _fallos[nombre] = e.mensaje;
        } catch (e) {
          _fallos[nombre] = '$e';
        }
      }
    }

    _deDisco
      ..clear()
      ..addAll(encontrados);

    if (notificar) {
      await _cargarFuentes();
      notifyListeners();
    }
  }

  Future<void> seleccionar(String id) async {
    if (config.tema == id) return;
    config.tema = id;
    await _cargarFuentes();
    notifyListeners();
    await config.save();
  }

  Future<void> _cargarFuentes() async {
    for (final tema in [temaParaClaro, temaParaOscuro]) {
      final familia = tema.tipografia.familia;
      if (familia == null) continue;
      final marca = '${tema.id}/$familia';
      if (!_fuentesCargadas.add(marca)) continue;
      final cargada = await cargarFuenteDelTema(tema);
      if (!cargada) {
        _fuentesCargadas.remove(marca);
        (_avisos[tema.id] ??= []).add(
          'No se pudo cargar la fuente "$familia". Revisa '
          '"tipografia.ficheros".',
        );
      }
    }
  }

  void vigilarLaCarpeta() {
    if (_vigilante != null) return;
    final carpeta = carpetaDeTemas();
    if (!carpeta.existsSync()) return;
    try {
      _vigilante = carpeta.watch(recursive: true).listen((_) {
        _rebote?.cancel();
        _rebote = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(recargar()),
        );
      }, onError: (_) {});
    } catch (_) {}
  }

  void dejarDeVigilar() {
    _rebote?.cancel();
    _rebote = null;
    unawaited(_vigilante?.cancel());
    _vigilante = null;
  }

  @override
  void dispose() {
    dejarDeVigilar();
    super.dispose();
  }
}
