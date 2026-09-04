import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'temas.dart';

const String kIdTemaDelSistema = 'sistema';

/// Temas retirados en la 1.3.0 y a qué incluido migra cada uno. Un
/// `config.json` viejo puede traer cualquiera de estos ids; al cargar se
/// cambia por el suyo y se guarda, para que la migración ocurra una vez.
const Map<String, String> kTemasRetirados = {
  'claro': 'material-claro',
  'oscuro': 'material-oscuro',
  'verde-claro': 'material-claro',
  'verde-oscuro': 'material-oscuro',
  'azul-claro': 'material-claro',
  'azul-oscuro': 'material-oscuro',
  'rojo-claro': 'material-claro',
  'rojo-oscuro': 'material-oscuro',
};

const Tema temaLiquidGlass = Tema(
  id: 'liquid-glass',
  nombre: 'Liquid Glass',
  autor: 'NeoFy',
  descripcion: 'Paneles translúcidos sobre la carátula desenfocada, al estilo '
      'del cristal de Apple. Pide GPU: si va a tirones, baja el desenfoque.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  radio: 18,
  radioCaratula: 12,
  colores: Paleta(
    primario: Color(0xFF0A84FF),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFF05070E),
    superficie: Color(0xFF121A2B),
    panel: Color(0xFF16203A),
    texto: Color(0xFFF5F7FF),
    textoTenue: Color(0xFFA9B6D4),
    borde: Color(0xFF2B3A5C),
    error: Color(0xFFFF453A),
  ),
  cristal: Cristal(
    activo: true,
    desenfoque: 28,
    opacidad: 0.16,
    saturacion: 1.8,
    brillo: 0.14,
    borde: 0.16,
    radio: 22,
  ),
  fondo: FondoDeTema(
    usarCaratula: true,
    desenfoque: 60,
    oscurecer: 0.55,
    degradado: [Color(0xFF0B1026), Color(0xFF1A0E2E), Color(0xFF05070E)],
    anguloDegradado: 135,
  ),
);

const Tema temaMaterialClaro = Tema(
  id: 'material-claro',
  nombre: 'Material claro',
  autor: 'NeoFy',
  descripcion: 'Material 3 Expressive: la paleta baseline de Google, '
      'superficies teñidas de violeta y esquinas muy redondeadas.',
  brillo: BrilloDeTema.claro,
  incluido: true,
  radio: 26,
  radioBoton: 999,
  radioCaratula: 16,
  navegacion: EstiloDeNavegacion.pildora,
  movimiento: Movimiento(esquema: EsquemaDeMovimiento.expresivo),
  progreso: EstiloDeProgreso.onda,
  tipografia: Tipografia(pesoTitulos: 600),
  formas: Formas(
    extraPequeno: 8,
    pequeno: 16,
    medio: 20,
    grande: 28,
    extraGrande: 36,
  ),
  colores: Paleta(
    primario: Color(0xFF65558F),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFFFDF7FF),
    superficie: Color(0xFFECE6EE),
    panel: Color(0xFFF2ECF4),
    texto: Color(0xFF1D1B20),
    textoTenue: Color(0xFF49454E),
    borde: Color(0xFF7A757F),
    error: Color(0xFFBA1A1A),
  ),
);

const Tema temaMaterialOscuro = Tema(
  id: 'material-oscuro',
  nombre: 'Material oscuro',
  autor: 'NeoFy',
  descripcion: 'Material 3 Expressive en oscuro. Aquí los paneles son más '
      'claros que el fondo, que es como Material marca la elevación.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  radio: 26,
  radioBoton: 999,
  radioCaratula: 16,
  navegacion: EstiloDeNavegacion.pildora,
  movimiento: Movimiento(esquema: EsquemaDeMovimiento.expresivo),
  progreso: EstiloDeProgreso.onda,
  tipografia: Tipografia(pesoTitulos: 600),
  formas: Formas(
    extraPequeno: 8,
    pequeno: 16,
    medio: 20,
    grande: 28,
    extraGrande: 36,
  ),
  colores: Paleta(
    primario: Color(0xFFCFBDFE),
    sobrePrimario: Color(0xFF36275D),
    fondo: Color(0xFF141218),
    superficie: Color(0xFF2B292F),
    panel: Color(0xFF211F24),
    texto: Color(0xFFE6E0E9),
    textoTenue: Color(0xFFCAC4CF),
    borde: Color(0xFF948F99),
    error: Color(0xFFFFB4AB),
  ),
);

const List<Tema> temasIncluidos = [
  temaMaterialOscuro,
  temaMaterialClaro,
  temaLiquidGlass,
];

Tema? temaIncluidoPorId(String id) {
  for (final tema in temasIncluidos) {
    if (tema.id == id) return tema;
  }
  return null;
}

/// Los únicos temas con editor de color en la app. Liquid Glass y los de
/// la comunidad se editan a mano en el `tema.json`; más adelante se
/// ampliará la personalización.
bool esTemaMaterial(String id) => id.startsWith('material-');

/// Escribe un tema de la comunidad partiendo de [base]. Con un Material
/// personalizado, [base] ya lleva acento, fondo y paneles aplicados, así
/// que la plantilla sale con esos colores y no con los de fábrica.
///
/// [en] es para tests; en la app se escribe en la carpeta de temas.
Future<Directory> crearTemaDeEjemplo({
  Tema base = temaMaterialOscuro,
  String nombre = 'Mi tema',
  Directory? en,
}) async {
  final raiz = en ?? carpetaDeTemas();
  final slug = idDesdeNombre(nombre);
  var destino = Directory(p.join(raiz.path, slug));
  var intento = 2;
  while (destino.existsSync()) {
    destino = Directory(p.join(raiz.path, '$slug-$intento'));
    intento++;
  }
  await destino.create(recursive: true);

  final id = p.basename(destino.path);
  final json = base.aJson()
    ..['id'] = id
    ..['nombre'] = nombre
    ..['autor'] = 'tu nombre'
    ..['version'] = '1.0.0'
    ..['descripcion'] = 'Cámbiame y guarda: NeoFy lo recarga solo.';

  await File(p.join(destino.path, kNombreDelManifiesto))
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  await File(p.join(destino.path, 'LEEME.md')).writeAsString(_leeme(id));
  return destino;
}

String _leeme(String id) => '''
# Mi tema

Plantilla de tema para NeoFy. La guía completa está en `TEMAS.md`, dentro del
repositorio: https://github.com/KOLPSE/NeoFy/blob/main/TEMAS.md

## Cómo trabajar

1. Abre `$kNombreDelManifiesto` y cambia los colores.
2. Guarda. NeoFy vuelve a leer la carpeta solo, sin cerrarse.
3. Si algo no se entiende, el propio selector de temas te dice qué línea falla.

Lo único obligatorio son `nombre`, `brillo` y `colores.primario`; todo lo demás
se deduce si lo borras.

## Publicarlo

Sube la carpeta `$id` a un repositorio y que la gente la copie en:

- Windows: `%APPDATA%\\neofy\\temas`
- Linux: `~/.config/neofy/temas`
''';
