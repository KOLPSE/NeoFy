import 'package:flutter/material.dart';

import 'app_config.dart';
import 'temas.dart';

const String kIdTemaDelSistema = 'sistema';

const Tema temaNeoFyNocturno = Tema(
  id: kIdTemaNocturno,
  nombre: 'NeoFy Nocturno',
  autor: 'NeoFy',
  descripcion: 'Negro y carbón, acentos verdes y portadas protagonistas.',
  brillo: BrilloDeTema.oscuro,
  incluido: true,
  radio: 10,
  radioBoton: 22,
  radioCaratula: 6,
  tipografia: Tipografia(pesoTitulos: 700),
  colores: Paleta(
    primario: Color(0xFF55DF79),
    sobrePrimario: Color(0xFF0C1910),
    fondo: Color(0xFF090909),
    superficie: Color(0xFF252525),
    panel: Color(0xFF161616),
    texto: Color(0xFFF7F7F7),
    textoTenue: Color(0xFFB8B8B8),
    borde: Color(0xFF595959),
    error: Color(0xFFFFA0AA),
  ),
);

const Tema temaNeoFyClaro = Tema(
  id: kIdTemaClaro,
  nombre: 'NeoFy Claro',
  autor: 'NeoFy',
  descripcion: 'Blanco y piedra suave, acentos verdes y portadas protagonistas.',
  brillo: BrilloDeTema.claro,
  incluido: true,
  radio: 10,
  radioBoton: 22,
  radioCaratula: 6,
  tipografia: Tipografia(pesoTitulos: 700),
  colores: Paleta(
    primario: Color(0xFF15803D),
    sobrePrimario: Color(0xFFFFFFFF),
    fondo: Color(0xFFEEF0EE),
    superficie: Color(0xFFE4E7E4),
    panel: Color(0xFFFFFFFF),
    texto: Color(0xFF111312),
    textoTenue: Color(0xFF555956),
    borde: Color(0xFFA2A8A4),
    error: Color(0xFFC62828),
  ),
);

/// Temas retirados y a qué tema de NeoFy migra cada uno. Un `config.json`
/// antiguo puede traer cualquiera de estos ids; al cargar se sustituye por el
/// suyo y se guarda.
const Map<String, String> kTemasRetirados = {
  'claro': kIdTemaClaro,
  'oscuro': kIdTemaNocturno,
  'verde-claro': kIdTemaClaro,
  'verde-oscuro': kIdTemaNocturno,
  'azul-claro': kIdTemaClaro,
  'azul-oscuro': kIdTemaNocturno,
  'rojo-claro': kIdTemaClaro,
  'rojo-oscuro': kIdTemaNocturno,
  'material-claro': kIdTemaClaro,
  'material-oscuro': kIdTemaNocturno,
  'liquid-glass': kIdTemaNocturno,
};

const List<Tema> temasIncluidos = [
  temaNeoFyNocturno,
  temaNeoFyClaro,
];

Tema? temaIncluidoPorId(String id) {
  for (final tema in temasIncluidos) {
    if (tema.id == id) return tema;
  }
  return null;
}
