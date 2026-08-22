import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;

import 'app_config.dart';

const int kFormatoDeTema = 1;

const String kIdTemaPorDefecto = 'oscuro';

const String kNombreDelManifiesto = 'tema.json';

enum BrilloDeTema { claro, oscuro }

enum AjusteDeFondo { cubrir, contener, repetir, estirar, centrar }

enum EstiloDeNavegacion { lista, pildora }

enum EsquemaDeMovimiento { ninguno, sobrio, expresivo }

enum EstiloDeProgreso { linea, onda }

class Movimiento {
  const Movimiento({
    this.esquema = EsquemaDeMovimiento.sobrio,
    this.rebote = 0.3,
    this.velocidad = 1,
  });

  final EsquemaDeMovimiento esquema;
  final double rebote;
  final double velocidad;

  static const Movimiento porDefecto = Movimiento();

  bool get seMueve => esquema != EsquemaDeMovimiento.ninguno;

  bool get rebota => esquema == EsquemaDeMovimiento.expresivo && rebote > 0;

  /// Fast spatial. M3E: expresivo 800/0.6, estándar 1400/0.9.
  SpringDescription get espacialRapido => _muelleM3e(
        stiffness: rebota ? 800 : 1400,
        ratio: rebota ? _ratioExpresivo : 0.9,
      );

  /// Default spatial. Para cosas a tamaño de rail o sheet, no de botón.
  /// M3E: expresivo 380/0.75, estándar 700/0.9.
  SpringDescription get espacialNormal => _muelleM3e(
        stiffness: rebota ? 380 : 700,
        ratio: rebota ? _ratioExpresivo : 0.9,
      );

  /// Cerrar es más rápido que abrir. M3E: standard spatial fast.
  SpringDescription get espacialCierre =>
      _muelleM3e(stiffness: 1400, ratio: 0.9);

  /// Effects default. M3E: 1600/1, nunca rebota.
  SpringDescription get efecto => _muelleM3e(stiffness: 1600, ratio: 1);

  /// Effects fast. M3E: 3800/1.
  SpringDescription get efectoRapido => _muelleM3e(stiffness: 3800, ratio: 1);

  /// `rebote` 0.3 (el de fábrica) equivale al 0.75 de *expressive spatial default*.
  double get _ratioExpresivo => (1.0 - rebote * 0.833).clamp(0.55, 1.0);

  SpringDescription _muelleM3e({
    required double stiffness,
    required double ratio,
  }) =>
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness * velocidad * velocidad,
        ratio: ratio,
      );

  static Movimiento lerp(Movimiento a, Movimiento b, double t) =>
      t < 0.5 ? a : b;

  Map<String, dynamic> aJson() => {
        'esquema': esquema.name,
        'rebote': rebote,
        'velocidad': velocidad,
      };
}

const double kRadioDeCaratulaPorDefecto = 6;

class Formas {
  const Formas({
    required this.extraPequeno,
    required this.pequeno,
    required this.medio,
    required this.grande,
    required this.extraGrande,
  });

  factory Formas.desdeRadio(double radio) => Formas(
        extraPequeno: radio / 3,
        pequeno: radio * 2 / 3,
        medio: radio,
        grande: radio * 4 / 3,
        extraGrande: radio * 2,
      );

  final double extraPequeno;
  final double pequeno;
  final double medio;
  final double grande;
  final double extraGrande;

  Formas conOverrides(Map<String, dynamic>? crudo) {
    if (crudo == null) return this;
    double leer(String clave, double actual) =>
        _numero(crudo[clave], 0, 60) ?? actual;
    return Formas(
      extraPequeno: leer('extraPequeno', extraPequeno),
      pequeno: leer('pequeno', pequeno),
      medio: leer('medio', medio),
      grande: leer('grande', grande),
      extraGrande: leer('extraGrande', extraGrande),
    );
  }

  bool igualA(Formas otra) =>
      extraPequeno == otra.extraPequeno &&
      pequeno == otra.pequeno &&
      medio == otra.medio &&
      grande == otra.grande &&
      extraGrande == otra.extraGrande;

  Map<String, dynamic> aJson() => {
        'extraPequeno': extraPequeno,
        'pequeno': pequeno,
        'medio': medio,
        'grande': grande,
        'extraGrande': extraGrande,
      };
}

class ErrorDeTema implements Exception {
  ErrorDeTema(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

class Paleta {
  const Paleta({
    required this.primario,
    required this.sobrePrimario,
    required this.fondo,
    required this.superficie,
    required this.panel,
    required this.texto,
    required this.textoTenue,
    required this.borde,
    required this.error,
  });

  final Color primario;
  final Color sobrePrimario;
  final Color fondo;
  final Color superficie;
  final Color panel;
  final Color texto;
  final Color textoTenue;
  final Color borde;
  final Color error;

  Map<String, dynamic> aJson() => {
        'primario': _aHex(primario),
        'sobrePrimario': _aHex(sobrePrimario),
        'fondo': _aHex(fondo),
        'superficie': _aHex(superficie),
        'panel': _aHex(panel),
        'texto': _aHex(texto),
        'textoTenue': _aHex(textoTenue),
        'borde': _aHex(borde),
        'error': _aHex(error),
      };
}

class Cristal {
  const Cristal({
    this.activo = false,
    this.desenfoque = 24,
    this.opacidad = 0.16,
    this.saturacion = 1.6,
    this.brillo = 0.28,
    this.borde = 0.26,
    this.radio = 18,
  });

  final bool activo;
  final double desenfoque;
  final double opacidad;
  final double saturacion;
  final double brillo;
  final double borde;
  final double radio;

  static const Cristal ninguno = Cristal();

  Cristal escalar(double factor) => Cristal(
        activo: activo,
        desenfoque: desenfoque * factor,
        opacidad: opacidad,
        saturacion: saturacion,
        brillo: brillo,
        borde: borde,
        radio: radio,
      );

  static Cristal lerp(Cristal a, Cristal b, double t) => Cristal(
        activo: t < 0.5 ? a.activo : b.activo,
        desenfoque: _lerpD(a.desenfoque, b.desenfoque, t),
        opacidad: _lerpD(a.opacidad, b.opacidad, t),
        saturacion: _lerpD(a.saturacion, b.saturacion, t),
        brillo: _lerpD(a.brillo, b.brillo, t),
        borde: _lerpD(a.borde, b.borde, t),
        radio: _lerpD(a.radio, b.radio, t),
      );

  Map<String, dynamic> aJson() => {
        'activo': activo,
        'desenfoque': desenfoque,
        'opacidad': opacidad,
        'saturacion': saturacion,
        'brillo': brillo,
        'borde': borde,
        'radio': radio,
      };
}

class FondoDeTema {
  const FondoDeTema({
    this.imagen,
    this.ajuste = AjusteDeFondo.cubrir,
    this.opacidad = 1,
    this.desenfoque = 0,
    this.oscurecer = 0,
    this.usarCaratula = false,
    this.degradado = const [],
    this.anguloDegradado = 135,
  });

  final String? imagen;
  final AjusteDeFondo ajuste;
  final double opacidad;
  final double desenfoque;
  final double oscurecer;
  final bool usarCaratula;
  final List<Color> degradado;
  final double anguloDegradado;

  static const FondoDeTema ninguno = FondoDeTema();

  bool get hayAlgoQuePintar =>
      imagen != null || usarCaratula || degradado.length >= 2;

  static FondoDeTema lerp(FondoDeTema a, FondoDeTema b, double t) =>
      t < 0.5 ? a : b;

  Map<String, dynamic> aJson() => {
        if (imagen != null) 'imagen': imagen,
        'ajuste': ajuste.name,
        'opacidad': opacidad,
        'desenfoque': desenfoque,
        'oscurecer': oscurecer,
        'usarCaratula': usarCaratula,
        if (degradado.isNotEmpty)
          'degradado': [for (final c in degradado) _aHex(c)],
        'anguloDegradado': anguloDegradado,
      };
}

class Tipografia {
  const Tipografia({
    this.familia,
    this.ficheros = const [],
    this.escala = 1,
    this.pesoTitulos,
  });

  final String? familia;
  final List<String> ficheros;
  final double escala;
  final int? pesoTitulos;

  static const Tipografia porDefecto = Tipografia();

  bool get esLaDeSiempre =>
      familia == null && ficheros.isEmpty && escala == 1 && pesoTitulos == null;

  Map<String, dynamic> aJson() => {
        if (familia != null) 'familia': familia,
        if (ficheros.isNotEmpty) 'ficheros': ficheros,
        'escala': escala,
        if (pesoTitulos != null) 'pesoTitulos': pesoTitulos,
      };
}

class Tema {
  const Tema({
    required this.id,
    required this.nombre,
    required this.brillo,
    required this.colores,
    this.autor = '',
    this.version = '',
    this.descripcion = '',
    this.cristal = Cristal.ninguno,
    this.fondo = FondoDeTema.ninguno,
    this.tipografia = Tipografia.porDefecto,
    this.radio = 12,
    this.radioBoton,
    this.radioCaratula = kRadioDeCaratulaPorDefecto,
    this.navegacion = EstiloDeNavegacion.lista,
    this.movimiento = Movimiento.porDefecto,
    this.progreso = EstiloDeProgreso.linea,
    this.formas,
    this.carpeta,
    this.incluido = false,
  });

  final String id;
  final String nombre;
  final String autor;
  final String version;
  final String descripcion;
  final BrilloDeTema brillo;
  final Paleta colores;
  final Cristal cristal;
  final FondoDeTema fondo;
  final Tipografia tipografia;
  final double radio;
  final double? radioBoton;
  final double radioCaratula;
  final EstiloDeNavegacion navegacion;
  final Movimiento movimiento;
  final EstiloDeProgreso progreso;
  final Formas? formas;
  final String? carpeta;
  final bool incluido;

  Formas get escalaDeFormas => formas ?? Formas.desdeRadio(radio);

  bool get esOscuro => brillo == BrilloDeTema.oscuro;

  String? rutaDeRecurso(String relativo) {
    final base = carpeta;
    if (base == null) return null;
    final relNormalizado = relativo.replaceAll(r'\', '/');
    final baseNormalizada = p.normalize(base);
    final destino = p.normalize(p.join(baseNormalizada, relNormalizado));
    if (!p.isWithin(baseNormalizada, destino)) return null;
    return destino;
  }

  Map<String, dynamic> aJson() => {
        'formato': kFormatoDeTema,
        'id': id,
        'nombre': nombre,
        if (autor.isNotEmpty) 'autor': autor,
        if (version.isNotEmpty) 'version': version,
        if (descripcion.isNotEmpty) 'descripcion': descripcion,
        'brillo': brillo.name,
        'colores': colores.aJson(),
        if (cristal.activo) 'cristal': cristal.aJson(),
        if (fondo.hayAlgoQuePintar) 'fondo': fondo.aJson(),
        if (!tipografia.esLaDeSiempre) 'tipografia': tipografia.aJson(),
        if (formas != null && !formas!.igualA(Formas.desdeRadio(radio)))
          'formas': formas!.aJson(),
        'radio': radio,
        if (radioBoton != null) 'radioBoton': radioBoton,
        if (radioCaratula != kRadioDeCaratulaPorDefecto)
          'radioCaratula': radioCaratula,
        if (navegacion != EstiloDeNavegacion.lista)
          'navegacion': navegacion.name,
        if (movimiento.esquema != EsquemaDeMovimiento.sobrio)
          'movimiento': movimiento.aJson(),
        if (progreso != EstiloDeProgreso.linea) 'progreso': progreso.name,
      };

  static Tema desdeJson(
    Map<String, dynamic> raiz, {
    String? id,
    String? carpeta,
    List<String>? avisos,
  }) {
    void avisar(String texto) => avisos?.add(texto);

    final formato = _entero(raiz['formato']) ?? kFormatoDeTema;
    if (formato > kFormatoDeTema) {
      avisar(
        'El tema declara formato $formato y esta versión de NeoFy entiende '
        'hasta el $kFormatoDeTema. Puede verse mal.',
      );
    }

    final nombre = _texto(raiz['nombre'])?.trim();
    if (nombre == null || nombre.isEmpty) {
      throw ErrorDeTema('Falta "nombre", que es obligatorio.');
    }

    final identificador =
        _texto(raiz['id'])?.trim().toLowerCase() ?? id ?? _aId(nombre);

    final brillo = switch (_texto(raiz['brillo'])?.trim().toLowerCase()) {
      'claro' || 'light' => BrilloDeTema.claro,
      'oscuro' || 'dark' => BrilloDeTema.oscuro,
      null => BrilloDeTema.oscuro,
      final otro => () {
          avisar('"brillo" vale "$otro"; solo valen "claro" y "oscuro". '
              'Se usa "oscuro".');
          return BrilloDeTema.oscuro;
        }(),
    };

    final crudos = _mapa(raiz['colores']) ?? const {};
    if (crudos.isEmpty) {
      throw ErrorDeTema('Falta el bloque "colores".');
    }

    Color? leer(String clave) {
      final valor = crudos[clave];
      if (valor == null) return null;
      final color = parsearColor(_texto(valor));
      if (color == null) {
        avisar('No entiendo el color de "$clave": ${jsonEncode(valor)}. '
            'Se usa el derivado.');
      }
      return color;
    }

    final primario = leer('primario');
    if (primario == null) {
      throw ErrorDeTema('Falta "colores.primario", que es obligatorio.');
    }

    final oscuro = brillo == BrilloDeTema.oscuro;
    final fondo = leer('fondo') ??
        (oscuro ? const Color(0xFF121212) : const Color(0xFFFAFAFA));
    final texto = leer('texto') ??
        (oscuro ? const Color(0xFFF2F2F2) : const Color(0xFF141414));

    final colores = Paleta(
      primario: primario,
      sobrePrimario: leer('sobrePrimario') ?? contrasteSobre(primario),
      fondo: fondo,
      superficie: leer('superficie') ??
          Color.lerp(fondo, oscuro ? Colors.white : Colors.black, 0.06)!,
      panel: leer('panel') ??
          Color.lerp(fondo, Colors.black, oscuro ? 0.40 : 0.06)!,
      texto: texto,
      textoTenue: leer('textoTenue') ?? Color.lerp(texto, fondo, 0.38)!,
      borde: leer('borde') ?? Color.lerp(fondo, texto, 0.16)!,
      error: leer('error') ??
          (oscuro ? const Color(0xFFFF6B6B) : const Color(0xFFB3261E)),
    );

    final cristalCrudo = _mapa(raiz['cristal']);
    final cristal = cristalCrudo == null
        ? Cristal.ninguno
        : Cristal(
            activo: _booleano(cristalCrudo['activo']) ?? true,
            desenfoque: _numero(cristalCrudo['desenfoque'], 0, 80) ?? 24,
            opacidad: _numero(cristalCrudo['opacidad'], 0, 1) ?? 0.16,
            saturacion: _numero(cristalCrudo['saturacion'], 0, 3) ?? 1.6,
            brillo: _numero(cristalCrudo['brillo'], 0, 1) ?? 0.28,
            borde: _numero(cristalCrudo['borde'], 0, 1) ?? 0.26,
            radio: _numero(cristalCrudo['radio'], 0, 48) ?? 18,
          );

    final fondoCrudo = _mapa(raiz['fondo']);
    final degradado = <Color>[];
    if (fondoCrudo != null) {
      for (final valor in _lista(fondoCrudo['degradado'])) {
        final color = parsearColor(_texto(valor));
        if (color != null) {
          degradado.add(color);
        } else {
          avisar('Color de degradado no válido: ${jsonEncode(valor)}.');
        }
      }
      if (degradado.length == 1) {
        avisar('"fondo.degradado" necesita al menos dos colores; se ignora.');
        degradado.clear();
      }
    }

    final fondoDeTema = fondoCrudo == null
        ? FondoDeTema.ninguno
        : FondoDeTema(
            imagen: _texto(fondoCrudo['imagen'])?.trim().isEmpty ?? true
                ? null
                : _texto(fondoCrudo['imagen'])!.trim(),
            ajuste: switch (
                _texto(fondoCrudo['ajuste'])?.trim().toLowerCase()) {
              'contener' => AjusteDeFondo.contener,
              'repetir' => AjusteDeFondo.repetir,
              'estirar' => AjusteDeFondo.estirar,
              'centrar' => AjusteDeFondo.centrar,
              _ => AjusteDeFondo.cubrir,
            },
            opacidad: _numero(fondoCrudo['opacidad'], 0, 1) ?? 1,
            desenfoque: _numero(fondoCrudo['desenfoque'], 0, 80) ?? 0,
            oscurecer: _numero(fondoCrudo['oscurecer'], 0, 1) ?? 0,
            usarCaratula: _booleano(fondoCrudo['usarCaratula']) ?? false,
            degradado: degradado,
            anguloDegradado:
                _numero(fondoCrudo['anguloDegradado'], -360, 360) ?? 135,
          );

    final tipoCrudo = _mapa(raiz['tipografia']);
    final tipografia = tipoCrudo == null
        ? Tipografia.porDefecto
        : Tipografia(
            familia: _texto(tipoCrudo['familia'])?.trim().isEmpty ?? true
                ? null
                : _texto(tipoCrudo['familia'])!.trim(),
            ficheros: [
              for (final f in _lista(tipoCrudo['ficheros']))
                if (_texto(f) != null) _texto(f)!.trim(),
            ],
            escala: _numero(tipoCrudo['escala'], 0.7, 1.6) ?? 1,
            pesoTitulos: _entero(tipoCrudo['pesoTitulos']) == null
                ? null
                : _numero(tipoCrudo['pesoTitulos'], 100, 900)!.round(),
          );

    if (tipografia.familia != null && tipografia.ficheros.isEmpty) {
      avisar('"tipografia.familia" está puesta pero no hay "ficheros"; '
          'solo funcionará si la fuente ya está instalada en el sistema.');
    }

    return Tema(
      id: identificador,
      nombre: nombre,
      autor: _texto(raiz['autor'])?.trim() ?? '',
      version: _texto(raiz['version'])?.trim() ?? '',
      descripcion: _texto(raiz['descripcion'])?.trim() ?? '',
      brillo: brillo,
      colores: colores,
      cristal: cristal,
      fondo: fondoDeTema,
      tipografia: tipografia,
      radio: _numero(raiz['radio'], 0, 40) ?? 12,
      radioBoton: _numero(raiz['radioBoton'], 0, 999),
      radioCaratula:
          _numero(raiz['radioCaratula'], 0, 40) ?? kRadioDeCaratulaPorDefecto,
      movimiento: _movimiento(_mapa(raiz['movimiento']), avisar),
      progreso: switch (_texto(raiz['progreso'])?.trim().toLowerCase()) {
        'onda' => EstiloDeProgreso.onda,
        'linea' || 'línea' || null => EstiloDeProgreso.linea,
        final otro => () {
            avisar('"progreso" vale "$otro"; solo valen "linea" y "onda". '
                'Se usa "linea".');
            return EstiloDeProgreso.linea;
          }(),
      },
      formas: raiz['formas'] == null
          ? null
          : Formas.desdeRadio(_numero(raiz['radio'], 0, 40) ?? 12)
              .conOverrides(_mapa(raiz['formas'])),
      navegacion: switch (
          _texto(raiz['navegacion'])?.trim().toLowerCase()) {
        'pildora' || 'píldora' => EstiloDeNavegacion.pildora,
        'lista' || null => EstiloDeNavegacion.lista,
        final otro => () {
            avisar('"navegacion" vale "$otro"; solo valen "lista" y '
                '"pildora". Se usa "lista".');
            return EstiloDeNavegacion.lista;
          }(),
      },
      carpeta: carpeta,
    );
  }
}

Movimiento _movimiento(
  Map<String, dynamic>? crudo,
  void Function(String) avisar,
) {
  if (crudo == null) return Movimiento.porDefecto;
  final esquema = switch (_texto(crudo['esquema'])?.trim().toLowerCase()) {
    'expresivo' => EsquemaDeMovimiento.expresivo,
    'sobrio' => EsquemaDeMovimiento.sobrio,
    'ninguno' => EsquemaDeMovimiento.ninguno,
    null => EsquemaDeMovimiento.sobrio,
    final otro => () {
        avisar('"movimiento.esquema" vale "$otro"; solo valen "sobrio", '
            '"expresivo" y "ninguno". Se usa "sobrio".');
        return EsquemaDeMovimiento.sobrio;
      }(),
  };
  return Movimiento(
    esquema: esquema,
    rebote: _numero(crudo['rebote'], 0, 1) ?? 0.3,
    velocidad: _numero(crudo['velocidad'], 0.5, 2) ?? 1,
  );
}

class EstiloNeoFy extends ThemeExtension<EstiloNeoFy> {
  const EstiloNeoFy({
    required this.cristal,
    required this.fondo,
    required this.radio,
    required this.idDelTema,
    this.radioCaratula = kRadioDeCaratulaPorDefecto,
    this.navegacion = EstiloDeNavegacion.lista,
    this.movimiento = Movimiento.porDefecto,
    this.progreso = EstiloDeProgreso.linea,
    this.carpeta,
  });

  final Cristal cristal;
  final FondoDeTema fondo;
  final double radio;
  final double radioCaratula;
  final EstiloDeNavegacion navegacion;
  final Movimiento movimiento;
  final EstiloDeProgreso progreso;
  final String idDelTema;
  final String? carpeta;

  static const EstiloNeoFy neutro = EstiloNeoFy(
    cristal: Cristal.ninguno,
    fondo: FondoDeTema.ninguno,
    radio: 12,
    idDelTema: kIdTemaPorDefecto,
  );

  bool get navegacionEnPildora => navegacion == EstiloDeNavegacion.pildora;

  double radioDeCaratula(double lado) =>
      radioCaratula < lado * 0.28 ? radioCaratula : lado * 0.28;

  static EstiloNeoFy de(BuildContext context) =>
      Theme.of(context).extension<EstiloNeoFy>() ?? neutro;

  bool get hayCristal => cristal.activo;

  String? rutaDeRecurso(String relativo) {
    final base = carpeta;
    if (base == null) return null;
    final relNormalizado = relativo.replaceAll(r'\', '/');
    final baseNormalizada = p.normalize(base);
    final destino = p.normalize(p.join(baseNormalizada, relNormalizado));
    if (!p.isWithin(baseNormalizada, destino)) return null;
    return destino;
  }

  @override
  EstiloNeoFy copyWith({
    Cristal? cristal,
    FondoDeTema? fondo,
    double? radio,
    double? radioCaratula,
    EstiloDeNavegacion? navegacion,
    Movimiento? movimiento,
    EstiloDeProgreso? progreso,
    String? idDelTema,
    String? carpeta,
  }) =>
      EstiloNeoFy(
        cristal: cristal ?? this.cristal,
        fondo: fondo ?? this.fondo,
        radio: radio ?? this.radio,
        radioCaratula: radioCaratula ?? this.radioCaratula,
        navegacion: navegacion ?? this.navegacion,
        movimiento: movimiento ?? this.movimiento,
        progreso: progreso ?? this.progreso,
        idDelTema: idDelTema ?? this.idDelTema,
        carpeta: carpeta ?? this.carpeta,
      );

  @override
  EstiloNeoFy lerp(ThemeExtension<EstiloNeoFy>? otro, double t) {
    if (otro is! EstiloNeoFy) return this;
    return EstiloNeoFy(
      cristal: Cristal.lerp(cristal, otro.cristal, t),
      fondo: FondoDeTema.lerp(fondo, otro.fondo, t),
      radio: _lerpD(radio, otro.radio, t),
      radioCaratula: _lerpD(radioCaratula, otro.radioCaratula, t),
      navegacion: t < 0.5 ? navegacion : otro.navegacion,
      movimiento: Movimiento.lerp(movimiento, otro.movimiento, t),
      progreso: t < 0.5 ? progreso : otro.progreso,
      idDelTema: t < 0.5 ? idDelTema : otro.idDelTema,
      carpeta: t < 0.5 ? carpeta : otro.carpeta,
    );
  }
}

ColorScheme esquemaDeTema(Tema tema) {
  final c = tema.colores;
  final oscuro = tema.esOscuro;
  final hsl = HSLColor.fromColor(c.primario);
  final secundario = hsl
      .withHue((hsl.hue + 28) % 360)
      .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
      .toColor();
  final terciario = hsl
      .withHue((hsl.hue + 320) % 360)
      .withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0))
      .toColor();

  Color haciaFondo(Color base, double t) => Color.lerp(base, c.fondo, t)!;

  return ColorScheme(
    brightness: oscuro ? Brightness.dark : Brightness.light,
    primary: c.primario,
    onPrimary: c.sobrePrimario,
    primaryContainer: haciaFondo(c.primario, oscuro ? 0.68 : 0.78),
    onPrimaryContainer: c.texto,
    secondary: secundario,
    onSecondary: contrasteSobre(secundario),
    secondaryContainer: haciaFondo(secundario, oscuro ? 0.72 : 0.82),
    onSecondaryContainer: c.texto,
    tertiary: terciario,
    onTertiary: contrasteSobre(terciario),
    tertiaryContainer: haciaFondo(terciario, oscuro ? 0.72 : 0.82),
    onTertiaryContainer: c.texto,
    error: c.error,
    onError: contrasteSobre(c.error),
    errorContainer: haciaFondo(c.error, oscuro ? 0.7 : 0.82),
    onErrorContainer: c.texto,
    surface: c.fondo,
    onSurface: c.texto,
    surfaceDim: Color.lerp(c.fondo, Colors.black, oscuro ? 0.18 : 0.08)!,
    surfaceBright: Color.lerp(c.fondo, Colors.white, oscuro ? 0.12 : 0.04)!,
    surfaceContainerLowest: c.panel,
    surfaceContainerLow: Color.lerp(c.panel, c.superficie, 0.5)!,
    surfaceContainer: c.panel,
    surfaceContainerHigh: c.superficie,
    surfaceContainerHighest:
        Color.lerp(c.superficie, c.texto, oscuro ? 0.06 : 0.04)!,
    onSurfaceVariant: c.textoTenue,
    outline: c.borde,
    outlineVariant: Color.lerp(c.borde, c.fondo, 0.5)!,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: c.texto,
    onInverseSurface: c.fondo,
    inversePrimary: haciaFondo(c.primario, 0.35),
    surfaceTint: c.primario,
  );
}

ThemeData construirThemeData(Tema tema) {
  final esquema = esquemaDeTema(tema);
  final radio = tema.radio;
  final formas = tema.escalaDeFormas;
  final radioBoton = tema.radioBoton ?? radio + 8;
  final base = ThemeData(colorScheme: esquema, useMaterial3: true);
  final familia = tema.tipografia.familia;
  final escala = tema.tipografia.escala;

  var texto = base.textTheme;
  if (familia != null) {
    texto = texto.apply(fontFamily: familia);
  }
  if (escala != 1) {
    texto = texto.apply(fontSizeFactor: escala);
  }
  final peso = tema.tipografia.pesoTitulos;
  if (peso != null) {
    final grosor = FontWeight.values.firstWhere(
      (w) => w.value >= peso,
      orElse: () => FontWeight.w900,
    );
    texto = texto.copyWith(
      titleLarge: texto.titleLarge?.copyWith(fontWeight: grosor),
      titleMedium: texto.titleMedium?.copyWith(fontWeight: grosor),
      titleSmall: texto.titleSmall?.copyWith(fontWeight: grosor),
      labelLarge: texto.labelLarge?.copyWith(fontWeight: grosor),
      labelMedium: texto.labelMedium?.copyWith(fontWeight: grosor),
      labelSmall: texto.labelSmall?.copyWith(fontWeight: grosor),
    );
  }

  final transparente = tema.cristal.activo || tema.fondo.hayAlgoQuePintar;

  return base.copyWith(
    textTheme: texto,
    scaffoldBackgroundColor:
        transparente ? Colors.transparent : esquema.surface,
    canvasColor: transparente ? Colors.transparent : esquema.surface,
    dividerTheme: DividerThemeData(
      color: esquema.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    cardTheme: base.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(formas.medio),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: esquema.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(formas.extraGrande),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(formas.pequeno),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(formas.pequeno),
          ),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(formas.pequeno),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioBoton),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioBoton),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioBoton),
        ),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: esquema.primary,
      thumbColor: esquema.primary,
      inactiveTrackColor: esquema.outlineVariant,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: esquema.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: esquema.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(formas.extraPequeno),
      ),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(formas.extraPequeno),
        border: Border.all(color: esquema.outlineVariant),
      ),
      textStyle: TextStyle(color: esquema.onSurface, fontSize: 12),
    ),
    extensions: [
      EstiloNeoFy(
        cristal: tema.cristal,
        fondo: tema.fondo,
        radio: radio,
        radioCaratula: tema.radioCaratula,
        navegacion: tema.navegacion,
        movimiento: tema.movimiento,
        progreso: tema.progreso,
        idDelTema: tema.id,
        carpeta: tema.carpeta,
      ),
    ],
  );
}

Color contrasteSobre(Color color) =>
    ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

Color? parsearColor(String? crudo) {
  if (crudo == null) return null;
  var texto = crudo.trim();
  if (texto.isEmpty) return null;

  if (texto.contains(',')) {
    final partes = texto.split(',');
    if (partes.length != 3 && partes.length != 4) return null;
    final numeros = <int>[];
    for (final parte in partes) {
      final n = int.tryParse(parte.trim());
      if (n == null || n < 0 || n > 255) return null;
      numeros.add(n);
    }
    if (numeros.length == 3) {
      return Color.fromARGB(255, numeros[0], numeros[1], numeros[2]);
    }
    return Color.fromARGB(numeros[3], numeros[0], numeros[1], numeros[2]);
  }

  if (texto.startsWith('#')) texto = texto.substring(1);
  if (texto.startsWith('0x') || texto.startsWith('0X')) {
    texto = texto.substring(2);
  }
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(texto)) return null;

  switch (texto.length) {
    case 3:
      texto = texto.split('').map((c) => '$c$c').join();
      texto = 'ff$texto';
    case 4:
      final expandido = texto.split('').map((c) => '$c$c').join();
      texto = expandido.substring(6) + expandido.substring(0, 6);
    case 6:
      texto = 'ff$texto';
    case 8:
      break;
    default:
      return null;
  }

  final valor = int.tryParse(texto, radix: 16);
  return valor == null ? null : Color(valor);
}

String _aHex(Color color) {
  String dos(double canal) =>
      (canal * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final alfa = color.a >= 1 ? '' : dos(color.a);
  return '#$alfa${dos(color.r)}${dos(color.g)}${dos(color.b)}'.toUpperCase();
}

String _aId(String nombre) {
  final limpio = nombre
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return limpio.isEmpty ? 'tema' : limpio;
}

String idDesdeNombre(String nombre) => _aId(nombre);

double _lerpD(double a, double b, double t) => a + (b - a) * t;

String? _texto(Object? valor) => valor is String ? valor : null;

bool? _booleano(Object? valor) => valor is bool ? valor : null;

int? _entero(Object? valor) => valor is num ? valor.toInt() : null;

double? _numero(Object? valor, double minimo, double maximo) {
  if (valor is! num) return null;
  return valor.toDouble().clamp(minimo, maximo);
}

Map<String, dynamic>? _mapa(Object? valor) =>
    valor is Map ? valor.cast<String, dynamic>() : null;

List<Object?> _lista(Object? valor) => valor is List ? valor : const [];

String _lugarDelFallo(FormatException e) {
  final fuente = e.source;
  final posicion = e.offset;
  if (fuente is! String || posicion == null || posicion > fuente.length) {
    return '';
  }
  final hasta = fuente.substring(0, posicion);
  final linea = '\n'.allMatches(hasta).length + 1;
  final columna = posicion - hasta.lastIndexOf('\n');
  return ' (línea $linea, columna $columna)';
}

Directory carpetaDeTemas() {
  final dir = Directory(p.join(appDataDir().path, 'temas'));
  if (!dir.existsSync()) {
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
  }
  return dir;
}

class TemaCargado {
  const TemaCargado({required this.tema, this.avisos = const []});

  final Tema tema;
  final List<String> avisos;
}

TemaCargado leerTemaDeCarpeta(Directory carpeta) {
  final manifiesto = File(p.join(carpeta.path, kNombreDelManifiesto));
  if (!manifiesto.existsSync()) {
    throw ErrorDeTema('No hay $kNombreDelManifiesto en ${carpeta.path}.');
  }
  return leerTemaDeTexto(
    manifiesto.readAsStringSync(),
    id: p.basename(carpeta.path).toLowerCase(),
    carpeta: carpeta.path,
  );
}

TemaCargado leerTemaDeTexto(String contenido, {String? id, String? carpeta}) {
  final Object? decodificado;
  try {
    decodificado = jsonDecode(contenido);
  } on FormatException catch (e) {
    throw ErrorDeTema('El JSON no es válido${_lugarDelFallo(e)}: ${e.message}');
  }
  final mapa = _mapa(decodificado);
  if (mapa == null) {
    throw ErrorDeTema('El fichero debe contener un objeto JSON.');
  }
  final avisos = <String>[];
  final tema = Tema.desdeJson(mapa, id: id, carpeta: carpeta, avisos: avisos);
  return TemaCargado(tema: tema, avisos: avisos);
}

Future<bool> cargarFuenteDelTema(Tema tema) async {
  final familia = tema.tipografia.familia;
  if (familia == null || tema.tipografia.ficheros.isEmpty) return false;
  final cargador = FontLoader(familia);
  var alguna = false;
  for (final relativo in tema.tipografia.ficheros) {
    final ruta = tema.rutaDeRecurso(relativo);
    if (ruta == null) continue;
    final fichero = File(ruta);
    if (!fichero.existsSync()) continue;
    cargador.addFont(
      fichero.readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
    alguna = true;
  }
  if (!alguna) return false;
  try {
    await cargador.load();
    return true;
  } catch (_) {
    return false;
  }
}
