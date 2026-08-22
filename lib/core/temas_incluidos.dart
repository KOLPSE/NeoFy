import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'temas.dart';

const String kIdTemaDelSistema = 'sistema';

const Tema temaClaro = Tema(
  id: 'claro',
  nombre: 'Claro',
  autor: 'NeoFy',
  descripcion: 'El de siempre, en claro. Blanco limpio y el verde de NeoFy.',
  brillo: BrilloDeTema.claro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFF1DB954),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFFFFFFFF),
    superficie: Color(0xFFF4F4F4),
    panel: Color(0xFFF0F0F0),
    texto: Color(0xFF121212),
    textoTenue: Color(0xFF5B5B5B),
    borde: Color(0xFFE1E1E1),
    error: Color(0xFFB3261E),
  ),
);

const Tema temaOscuro = Tema(
  id: 'oscuro',
  nombre: 'Oscuro',
  autor: 'NeoFy',
  descripcion: 'El de siempre. Negro casi puro y el verde de NeoFy.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFF1DB954),
    sobrePrimario: Color(0xFF06210F),
    fondo: Color(0xFF121212),
    superficie: Color(0xFF1C1C1C),
    panel: Color(0xFF0A0A0A),
    texto: Color(0xFFF2F2F2),
    textoTenue: Color(0xFFA8A8A8),
    borde: Color(0xFF2A2A2A),
    error: Color(0xFFFF6B6B),
  ),
);

const Tema temaVerdeClaro = Tema(
  id: 'verde-claro',
  nombre: 'Verde claro',
  autor: 'NeoFy',
  descripcion: 'Menta sobre papel. Todo el fondo tirando a verde.',
  brillo: BrilloDeTema.claro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFF128C43),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFFF2FBF5),
    superficie: Color(0xFFE6F5EB),
    panel: Color(0xFFDCEFE3),
    texto: Color(0xFF0C2A18),
    textoTenue: Color(0xFF4A6B58),
    borde: Color(0xFFC6E2D0),
    error: Color(0xFFB3261E),
  ),
);

const Tema temaVerdeOscuro = Tema(
  id: 'verde-oscuro',
  nombre: 'Verde oscuro',
  autor: 'NeoFy',
  descripcion: 'Bosque de noche. Verde encendido sobre fondo verde apagado.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFF1ED760),
    sobrePrimario: Color(0xFF04160B),
    fondo: Color(0xFF0B1710),
    superficie: Color(0xFF12241A),
    panel: Color(0xFF071009),
    texto: Color(0xFFE8F7EE),
    textoTenue: Color(0xFF93B7A2),
    borde: Color(0xFF1E3A29),
    error: Color(0xFFFF6B6B),
  ),
);

const Tema temaAzulClaro = Tema(
  id: 'azul-claro',
  nombre: 'Azul claro',
  autor: 'NeoFy',
  descripcion: 'Cielo de mediodía. Azules fríos y mucho aire.',
  brillo: BrilloDeTema.claro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFF1D6FE0),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFFF5F8FF),
    superficie: Color(0xFFE9F0FD),
    panel: Color(0xFFDEE9FB),
    texto: Color(0xFF101B2E),
    textoTenue: Color(0xFF4C5E7A),
    borde: Color(0xFFC9DAF4),
    error: Color(0xFFB3261E),
  ),
);

const Tema temaAzulOscuro = Tema(
  id: 'azul-oscuro',
  nombre: 'Azul oscuro',
  autor: 'NeoFy',
  descripcion: 'Medianoche. Azul eléctrico sobre azul marino.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFF4C8DFF),
    sobrePrimario: Color(0xFF04101F),
    fondo: Color(0xFF0A1020),
    superficie: Color(0xFF121C33),
    panel: Color(0xFF060A16),
    texto: Color(0xFFE9EFFC),
    textoTenue: Color(0xFF97A8C6),
    borde: Color(0xFF1E2C4A),
    error: Color(0xFFFF6B6B),
  ),
);

const Tema temaRojoClaro = Tema(
  id: 'rojo-claro',
  nombre: 'Rojo claro',
  autor: 'NeoFy',
  descripcion: 'Carmín sobre crema. Cálido sin llegar a cansar.',
  brillo: BrilloDeTema.claro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFFC62B3E),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFFFFF6F6),
    superficie: Color(0xFFFBE9EA),
    panel: Color(0xFFF8DEE0),
    texto: Color(0xFF2B1013),
    textoTenue: Color(0xFF7A5054),
    borde: Color(0xFFF0CBCE),
    error: Color(0xFF8C1D28),
  ),
);

const Tema temaRojoOscuro = Tema(
  id: 'rojo-oscuro',
  nombre: 'Rojo oscuro',
  autor: 'NeoFy',
  descripcion: 'Sala oscura con luz roja. Contraste alto, fondo cálido.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  colores: Paleta(
    primario: Color(0xFFFF5A67),
    sobrePrimario: Color(0xFF1E0507),
    fondo: Color(0xFF170B0D),
    superficie: Color(0xFF241315),
    panel: Color(0xFF100708),
    texto: Color(0xFFFBE9EA),
    textoTenue: Color(0xFFC09499),
    borde: Color(0xFF3A1E22),
    error: Color(0xFFFF8A94),
  ),
);

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
  temaOscuro,
  temaClaro,
  temaVerdeOscuro,
  temaVerdeClaro,
  temaAzulOscuro,
  temaAzulClaro,
  temaRojoOscuro,
  temaRojoClaro,
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

Future<Directory> crearTemaDeEjemplo({Tema base = temaOscuro}) async {
  final raiz = carpetaDeTemas();
  var destino = Directory(p.join(raiz.path, 'mi-tema'));
  var intento = 2;
  while (destino.existsSync()) {
    destino = Directory(p.join(raiz.path, 'mi-tema-$intento'));
    intento++;
  }
  await destino.create(recursive: true);

  final id = p.basename(destino.path);
  final json = base.aJson()
    ..['id'] = id
    ..['nombre'] = 'Mi tema'
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
