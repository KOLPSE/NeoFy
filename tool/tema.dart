import 'dart:convert';
import 'dart:io';

const String kNombreDelManifiesto = 'tema.json';

const int kFormatoDeTema = 1;

const List<String> clavesDeRaiz = [
  'formato',
  'id',
  'nombre',
  'autor',
  'version',
  'descripcion',
  'brillo',
  'radio',
  'radioBoton',
  'radioCaratula',
  'navegacion',
  'movimiento',
  'progreso',
  'formas',
  'colores',
  'cristal',
  'fondo',
  'tipografia',
];

const List<String> clavesDeColores = [
  'primario',
  'sobrePrimario',
  'fondo',
  'superficie',
  'panel',
  'texto',
  'textoTenue',
  'borde',
  'error',
];

const Map<String, List<double>> rangosDeCristal = {
  'desenfoque': [0, 80],
  'opacidad': [0, 1],
  'saturacion': [0, 3],
  'brillo': [0, 1],
  'borde': [0, 1],
  'radio': [0, 48],
};

const Map<String, List<double>> rangosDeFondo = {
  'opacidad': [0, 1],
  'desenfoque': [0, 80],
  'oscurecer': [0, 1],
  'anguloDegradado': [-360, 360],
};

const List<String> ajustesDeFondo = [
  'cubrir',
  'contener',
  'repetir',
  'estirar',
  'centrar',
];

String _numeroCorto(double n) =>
    n == n.roundToDouble() ? '${n.round()}' : '$n';

String _rango(List<double> rango) =>
    '${_numeroCorto(rango[0])}..${_numeroCorto(rango[1])}';

String lugarDelFallo(FormatException e) {
  final fuente = e.source;
  final posicion = e.offset;
  if (fuente is! String || posicion == null || posicion > fuente.length) {
    return '';
  }
  final hasta = fuente.substring(0, posicion);
  final linea = '\n'.allMatches(hasta).length + 1;
  final ultimoSalto = hasta.lastIndexOf('\n');
  final columna = posicion - ultimoSalto;
  return ' (línea $linea, columna $columna)';
}

class Problema {
  Problema(this.ruta, this.mensaje, {this.grave = true});

  final String ruta;
  final String mensaje;
  final bool grave;

  @override
  String toString() => '$ruta: $mensaje';
}

int? parsearColor(String? crudo) {
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
    final alfa = numeros.length == 4 ? numeros[3] : 255;
    return (alfa << 24) | (numeros[0] << 16) | (numeros[1] << 8) | numeros[2];
  }

  if (texto.startsWith('#')) texto = texto.substring(1);
  if (texto.startsWith('0x') || texto.startsWith('0X')) {
    texto = texto.substring(2);
  }
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(texto)) return null;

  switch (texto.length) {
    case 3:
      texto = 'ff${texto.split('').map((c) => '$c$c').join()}';
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
  return int.tryParse(texto, radix: 16);
}

List<Problema> validarManifiesto(
  Map<String, dynamic> raiz, {
  Set<String> ficherosPresentes = const {},
  bool comprobarFicheros = false,
}) {
  final problemas = <Problema>[];

  void grave(String ruta, String mensaje) =>
      problemas.add(Problema(ruta, mensaje));
  void aviso(String ruta, String mensaje) =>
      problemas.add(Problema(ruta, mensaje, grave: false));

  for (final clave in raiz.keys) {
    if (!clavesDeRaiz.contains(clave)) {
      aviso(clave, 'no la entiendo; se ignorará. ¿Un typo?');
    }
  }

  final formato = raiz['formato'];
  if (formato != null && formato is! int) {
    grave('formato', 'tiene que ser un número entero.');
  } else if (formato is int && formato > kFormatoDeTema) {
    aviso('formato',
        'declaras $formato y la guía documenta hasta el $kFormatoDeTema.');
  }

  final nombre = raiz['nombre'];
  if (nombre is! String || nombre.trim().isEmpty) {
    grave('nombre', 'falta, y es obligatorio.');
  }

  final brillo = raiz['brillo'];
  if (brillo == null) {
    aviso('brillo', 'no está; se asumirá "oscuro".');
  } else if (brillo is! String ||
      !['claro', 'oscuro', 'light', 'dark'].contains(brillo.toLowerCase())) {
    grave('brillo', 'tiene que ser "claro" u "oscuro".');
  }

  final radio = raiz['radio'];
  if (radio != null && radio is! num) {
    grave('radio', 'tiene que ser un número.');
  } else if (radio is num && (radio < 0 || radio > 40)) {
    aviso('radio', 'se recortará al rango 0..40.');
  }

  final radioBoton = raiz['radioBoton'];
  if (radioBoton != null && radioBoton is! num) {
    grave('radioBoton', 'tiene que ser un número.');
  } else if (radioBoton is num && (radioBoton < 0 || radioBoton > 999)) {
    aviso('radioBoton', 'se recortará al rango 0..999.');
  }

  final radioCaratula = raiz['radioCaratula'];
  if (radioCaratula != null && radioCaratula is! num) {
    grave('radioCaratula', 'tiene que ser un número.');
  } else if (radioCaratula is num &&
      (radioCaratula < 0 || radioCaratula > 40)) {
    aviso('radioCaratula', 'se recortará al rango 0..40.');
  }

  final navegacion = raiz['navegacion'];
  if (navegacion != null &&
      (navegacion is! String ||
          !['lista', 'pildora'].contains(navegacion.toLowerCase()))) {
    grave('navegacion', 'vale "lista" o "pildora".');
  }

  final colores = raiz['colores'];
  if (colores is! Map) {
    grave('colores', 'falta el bloque, y es obligatorio.');
  } else {
    if (!colores.containsKey('primario')) {
      grave('colores.primario', 'falta, y es el único color obligatorio.');
    }
    for (final entrada in colores.entries) {
      final clave = '${entrada.key}';
      if (!clavesDeColores.contains(clave)) {
        aviso('colores.$clave',
            'no la entiendo; las válidas son: ${clavesDeColores.join(', ')}.');
        continue;
      }
      final valor = entrada.value;
      if (valor is! String || parsearColor(valor) == null) {
        grave('colores.$clave',
            'no es un color válido (${jsonEncode(valor)}). Vale "#RRGGBB", '
            '"#AARRGGBB", "#RGB" o "R,G,B".');
      }
    }
  }

  final cristal = raiz['cristal'];
  if (cristal != null && cristal is! Map) {
    grave('cristal', 'tiene que ser un objeto.');
  } else if (cristal is Map) {
    final activo = cristal['activo'];
    if (activo != null && activo is! bool) {
      grave('cristal.activo', 'tiene que ser true o false.');
    }
    for (final entrada in cristal.entries) {
      final clave = '${entrada.key}';
      if (clave == 'activo') continue;
      final rango = rangosDeCristal[clave];
      if (rango == null) {
        aviso('cristal.$clave', 'no la entiendo; se ignorará.');
        continue;
      }
      final valor = entrada.value;
      if (valor is! num) {
        grave('cristal.$clave', 'tiene que ser un número.');
      } else if (valor < rango[0] || valor > rango[1]) {
        aviso('cristal.$clave', 'se recortará al rango ${_rango(rango)}.');
      }
    }
    if (cristal['desenfoque'] is num && (cristal['desenfoque'] as num) > 40) {
      aviso('cristal.desenfoque',
          'por encima de 40 se nota en equipos sin GPU dedicada.');
    }
  }

  final fondo = raiz['fondo'];
  if (fondo != null && fondo is! Map) {
    grave('fondo', 'tiene que ser un objeto.');
  } else if (fondo is Map) {
    for (final entrada in fondo.entries) {
      final clave = '${entrada.key}';
      if (const ['imagen', 'ajuste', 'usarCaratula', 'degradado']
          .contains(clave)) {
        continue;
      }
      final rango = rangosDeFondo[clave];
      if (rango == null) {
        aviso('fondo.$clave', 'no la entiendo; se ignorará.');
        continue;
      }
      final valor = entrada.value;
      if (valor is! num) {
        grave('fondo.$clave', 'tiene que ser un número.');
      } else if (valor < rango[0] || valor > rango[1]) {
        aviso('fondo.$clave', 'se recortará al rango ${_rango(rango)}.');
      }
    }

    final ajuste = fondo['ajuste'];
    if (ajuste != null &&
        (ajuste is! String || !ajustesDeFondo.contains(ajuste))) {
      grave('fondo.ajuste', 'vale ${ajustesDeFondo.join(', ')}.');
    }

    final usarCaratula = fondo['usarCaratula'];
    if (usarCaratula != null && usarCaratula is! bool) {
      grave('fondo.usarCaratula', 'tiene que ser true o false.');
    }

    final degradado = fondo['degradado'];
    if (degradado != null && degradado is! List) {
      grave('fondo.degradado', 'tiene que ser una lista de colores.');
    } else if (degradado is List) {
      if (degradado.length == 1) {
        grave('fondo.degradado', 'necesita al menos dos colores.');
      }
      for (var i = 0; i < degradado.length; i++) {
        final valor = degradado[i];
        if (valor is! String || parsearColor(valor) == null) {
          grave('fondo.degradado[$i]',
              'no es un color válido (${jsonEncode(valor)}).');
        }
      }
    }

    final imagen = fondo['imagen'];
    if (imagen != null && imagen is! String) {
      grave('fondo.imagen', 'tiene que ser el nombre de un fichero.');
    } else if (imagen is String && imagen.trim().isNotEmpty) {
      if (imagen.contains('..') ||
          imagen.startsWith('/') ||
          imagen.startsWith('\\') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(imagen)) {
        grave('fondo.imagen',
            'tiene que ser una ruta relativa dentro de la carpeta del tema; '
            'NeoFy no sale de ahí.');
      } else if (comprobarFicheros && !ficherosPresentes.contains(imagen)) {
        grave('fondo.imagen', 'no existe "$imagen" en la carpeta del tema.');
      }
    }

    if (fondo['usarCaratula'] != true &&
        (imagen == null || '$imagen'.trim().isEmpty) &&
        (degradado is! List || degradado.length < 2)) {
      aviso('fondo',
          'el bloque no pinta nada: sin "imagen", sin "usarCaratula" y sin '
          '"degradado" es como no ponerlo.');
    }
  }

  final progreso = raiz['progreso'];
  if (progreso != null &&
      (progreso is! String ||
          !['linea', 'onda'].contains(progreso.toLowerCase()))) {
    grave('progreso', 'vale "linea" u "onda".');
  }

  final formas = raiz['formas'];
  if (formas != null && formas is! Map) {
    grave('formas', 'tiene que ser un objeto.');
  } else if (formas is Map) {
    const pasos = [
      'extraPequeno',
      'pequeno',
      'medio',
      'grande',
      'extraGrande',
    ];
    for (final entrada in formas.entries) {
      final clave = '${entrada.key}';
      if (!pasos.contains(clave)) {
        aviso('formas.$clave',
            'no la entiendo; los pasos son: ${pasos.join(', ')}.');
        continue;
      }
      final valor = entrada.value;
      if (valor is! num) {
        grave('formas.$clave', 'tiene que ser un número.');
      } else if (valor < 0 || valor > 60) {
        aviso('formas.$clave', 'se recortará al rango 0..60.');
      }
    }
    final leidos = [
      for (final paso in pasos)
        if (formas[paso] is num) (formas[paso] as num).toDouble(),
    ];
    if (leidos.length > 1) {
      for (var i = 1; i < leidos.length; i++) {
        if (leidos[i] < leidos[i - 1]) {
          aviso('formas',
              'la escala no va de menor a mayor; Material la define '
              'creciente y con los pasos desordenados quedan diálogos más '
              'cuadrados que las tarjetas.');
          break;
        }
      }
    }
  }

  final movimiento = raiz['movimiento'];
  if (movimiento != null && movimiento is! Map) {
    grave('movimiento', 'tiene que ser un objeto.');
  } else if (movimiento is Map) {
    final esquema = movimiento['esquema'];
    if (esquema != null &&
        (esquema is! String ||
            !['sobrio', 'expresivo', 'ninguno']
                .contains(esquema.toLowerCase()))) {
      grave('movimiento.esquema',
          'vale "sobrio", "expresivo" o "ninguno".');
    }
    for (final clave in ['rebote', 'velocidad']) {
      final valor = movimiento[clave];
      if (valor == null) continue;
      if (valor is! num) {
        grave('movimiento.$clave', 'tiene que ser un número.');
      } else {
        final limites = clave == 'rebote' ? [0.0, 1.0] : [0.5, 2.0];
        if (valor < limites[0] || valor > limites[1]) {
          aviso('movimiento.$clave',
              'se recortará al rango ${_rango(limites)}.');
        }
      }
    }
    for (final clave in movimiento.keys) {
      if (!['esquema', 'rebote', 'velocidad'].contains('$clave')) {
        aviso('movimiento.$clave', 'no la entiendo; se ignorará.');
      }
    }
  }

  final tipografia = raiz['tipografia'];
  if (tipografia != null && tipografia is! Map) {
    grave('tipografia', 'tiene que ser un objeto.');
  } else if (tipografia is Map) {
    final familia = tipografia['familia'];
    if (familia != null && familia is! String) {
      grave('tipografia.familia', 'tiene que ser texto.');
    }
    final escala = tipografia['escala'];
    if (escala != null && escala is! num) {
      grave('tipografia.escala', 'tiene que ser un número.');
    } else if (escala is num && (escala < 0.7 || escala > 1.6)) {
      aviso('tipografia.escala', 'se recortará al rango 0.7..1.6.');
    }
    final peso = tipografia['pesoTitulos'];
    if (peso != null && peso is! num) {
      grave('tipografia.pesoTitulos', 'tiene que ser un número.');
    } else if (peso is num && (peso < 100 || peso > 900)) {
      aviso('tipografia.pesoTitulos', 'se recortará al rango 100..900.');
    }
    for (final clave in tipografia.keys) {
      if (!['familia', 'ficheros', 'escala', 'pesoTitulos']
          .contains('$clave')) {
        aviso('tipografia.$clave', 'no la entiendo; se ignorará.');
      }
    }
    final ficheros = tipografia['ficheros'];
    if (ficheros != null && ficheros is! List) {
      grave('tipografia.ficheros', 'tiene que ser una lista de ficheros.');
    } else if (ficheros is List) {
      for (var i = 0; i < ficheros.length; i++) {
        final valor = ficheros[i];
        if (valor is! String) {
          grave('tipografia.ficheros[$i]', 'tiene que ser texto.');
          continue;
        }
        if (valor.contains('..') || RegExp(r'^[a-zA-Z]:').hasMatch(valor)) {
          grave('tipografia.ficheros[$i]',
              'tiene que ser una ruta relativa dentro de la carpeta.');
        } else if (comprobarFicheros && !ficherosPresentes.contains(valor)) {
          grave('tipografia.ficheros[$i]', 'no existe "$valor" en la carpeta.');
        }
      }
      if (familia is String && ficheros.isEmpty) {
        aviso('tipografia.ficheros',
            'pones "familia" pero no adjuntas la fuente: solo funcionará en '
            'equipos que ya la tengan instalada.');
      }
    }
  }

  return problemas;
}

const String plantilla = '''{
  "formato": 1,
  "nombre": "__NOMBRE__",
  "autor": "tu nombre",
  "version": "1.0.0",
  "descripcion": "Una línea contando de qué va.",

  "brillo": "oscuro",

  "colores": {
    "primario": "#1DB954",
    "fondo": "#121212",
    "superficie": "#1C1C1C",
    "panel": "#0A0A0A",
    "texto": "#F2F2F2",
    "textoTenue": "#A8A8A8",
    "borde": "#2A2A2A"
  },

  "radio": 12
}
''';

const String plantillaCristal = '''{
  "formato": 1,
  "nombre": "__NOMBRE__",
  "autor": "tu nombre",
  "version": "1.0.0",
  "descripcion": "Paneles de cristal sobre la carátula.",

  "brillo": "oscuro",

  "colores": {
    "primario": "#0A84FF",
    "fondo": "#05070E",
    "superficie": "#121A2B",
    "panel": "#16203A",
    "texto": "#F5F7FF",
    "textoTenue": "#A9B6D4",
    "borde": "#2B3A5C"
  },

  "cristal": {
    "activo": true,
    "desenfoque": 28,
    "opacidad": 0.16,
    "saturacion": 1.8,
    "brillo": 0.34,
    "borde": 0.30,
    "radio": 22
  },

  "fondo": {
    "usarCaratula": true,
    "desenfoque": 60,
    "oscurecer": 0.55,
    "degradado": ["#0B1026", "#1A0E2E", "#05070E"],
    "anguloDegradado": 135
  },

  "radio": 18
}
''';

Directory carpetaDeTemas() {
  final base = Platform.isWindows
      ? Platform.environment['APPDATA']
      : (Platform.environment['XDG_CONFIG_HOME'] ??
          (Platform.environment['HOME'] == null
              ? null
              : '${Platform.environment['HOME']}${Platform.pathSeparator}.config'));
  final raiz = base ?? Directory.systemTemp.path;
  return Directory(
      '$raiz${Platform.pathSeparator}neofy${Platform.pathSeparator}temas');
}

String aId(String nombre) {
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

bool _color = stdout.supportsAnsiEscapes;

String _rojo(String t) => _color ? '\x1b[31m$t\x1b[0m' : t;
String _amarillo(String t) => _color ? '\x1b[33m$t\x1b[0m' : t;
String _verde(String t) => _color ? '\x1b[32m$t\x1b[0m' : t;
String _gris(String t) => _color ? '\x1b[90m$t\x1b[0m' : t;

String _muestra(int argb) {
  if (!_color) return '';
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return '\x1b[48;2;$r;$g;${b}m    \x1b[0m ';
}

void main(List<String> args) {
  exitCode = despachar(args);
}

int despachar(List<String> args) {
  if (args.isEmpty) {
    _ayuda();
    return 0;
  }
  final orden = args.first;
  final resto = args.skip(1).toList();
  return switch (orden) {
    'nuevo' => _nuevo(resto),
    'validar' => _validar(resto),
    'listar' => _listar(),
    'instalar' => _instalar(resto),
    'donde' => _donde(),
    '-h' || '--help' || 'ayuda' => () {
        _ayuda();
        return 0;
      }(),
    _ => () {
        stderr.writeln('No conozco la orden "$orden".');
        _ayuda();
        return 2;
      }(),
  };
}

void _ayuda() {
  stdout.writeln('''
Ayudante de temas de NeoFy.

  dart run tool/tema.dart <orden> [opciones]

Órdenes:
  nuevo <nombre> [--cristal] [--en <ruta>]
      Crea la carpeta del tema con su $kNombreDelManifiesto ya relleno.
      Sin --en va a la carpeta de temas de NeoFy, y la app lo ve al instante.
      Con --cristal parte de la plantilla translúcida en vez de la plana.

  validar [ruta ...]
      Repasa uno o varios temas. Sin argumentos repasa los instalados.
      Sale con código 1 si algo es un error de verdad.

  listar
      Enseña los temas instalados con su paleta.

  instalar <ruta>
      Copia una carpeta de tema a la carpeta de NeoFy.

  donde
      Dice dónde está la carpeta de temas.

La guía para desarrolladores está en TEMAS.md.''');
}

int _donde() {
  stdout.writeln(carpetaDeTemas().path);
  return 0;
}

int _nuevo(List<String> args) {
  final sueltos = args.where((a) => !a.startsWith('--')).toList();
  if (sueltos.isEmpty) {
    stderr.writeln('Dime cómo se llama: dart run tool/tema.dart nuevo "Mi tema"');
    return 2;
  }
  final nombre = sueltos.first;
  final conCristal = args.contains('--cristal');

  final indiceEn = args.indexOf('--en');
  final base = indiceEn >= 0 && indiceEn + 1 < args.length
      ? Directory(args[indiceEn + 1])
      : carpetaDeTemas();

  final id = aId(nombre);
  final destino = Directory('${base.path}${Platform.pathSeparator}$id');
  if (destino.existsSync()) {
    stderr.writeln('Ya existe ${destino.path}. Borra esa carpeta o cambia el '
        'nombre.');
    return 1;
  }

  destino.createSync(recursive: true);
  final cuerpo = (conCristal ? plantillaCristal : plantilla)
      .replaceAll('__NOMBRE__', nombre.replaceAll('"', r'\"'));
  File('${destino.path}${Platform.pathSeparator}$kNombreDelManifiesto')
      .writeAsStringSync(cuerpo);

  stdout.writeln(_verde('Creado ${destino.path}'));
  stdout.writeln('Edita $kNombreDelManifiesto y guarda: NeoFy lo recarga solo, '
      'sin cerrarse.');
  return 0;
}

int _listar() {
  final carpeta = carpetaDeTemas();
  if (!carpeta.existsSync()) {
    stdout.writeln('No hay carpeta de temas todavía (${carpeta.path}).');
    return 0;
  }
  final carpetas = carpeta.listSync().whereType<Directory>().toList();
  if (carpetas.isEmpty) {
    stdout.writeln('No hay ningún tema instalado en ${carpeta.path}.');
    return 0;
  }
  for (final entrada in carpetas) {
    final manifiesto =
        File('${entrada.path}${Platform.pathSeparator}$kNombreDelManifiesto');
    final id = entrada.path.split(Platform.pathSeparator).last;
    if (!manifiesto.existsSync()) {
      stdout.writeln('${_rojo('x')} $id  ${_gris('sin $kNombreDelManifiesto')}');
      continue;
    }
    try {
      final raiz = jsonDecode(manifiesto.readAsStringSync()) as Map;
      final colores = (raiz['colores'] as Map?) ?? const {};
      final tira = StringBuffer();
      for (final clave in ['fondo', 'panel', 'primario', 'texto']) {
        final argb = parsearColor(colores[clave] as String?);
        if (argb != null) tira.write(_muestra(argb));
      }
      stdout.writeln('${_verde('·')} ${raiz['nombre'] ?? id}  '
          '${_gris(id)}  $tira');
    } catch (e) {
      stdout.writeln('${_rojo('x')} $id  ${_gris('$e')}');
    }
  }
  return 0;
}

int _instalar(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Dime qué carpeta: dart run tool/tema.dart instalar ./mi-tema');
    return 2;
  }
  final origen = Directory(args.first);
  if (!origen.existsSync()) {
    stderr.writeln('No existe ${origen.path}.');
    return 1;
  }
  final manifiesto =
      File('${origen.path}${Platform.pathSeparator}$kNombreDelManifiesto');
  if (!manifiesto.existsSync()) {
    stderr.writeln('${origen.path} no tiene $kNombreDelManifiesto: eso no es '
        'un tema.');
    return 1;
  }

  final id = origen.path
      .replaceAll(RegExp(r'[\\/]+$'), '')
      .split(RegExp(r'[\\/]'))
      .last;
  final destino =
      Directory('${carpetaDeTemas().path}${Platform.pathSeparator}$id');
  if (destino.existsSync()) destino.deleteSync(recursive: true);
  destino.createSync(recursive: true);

  for (final entrada in origen.listSync(recursive: true)) {
    final relativa = entrada.path.substring(origen.path.length + 1);
    final nueva = '${destino.path}${Platform.pathSeparator}$relativa';
    if (entrada is Directory) {
      Directory(nueva).createSync(recursive: true);
    } else if (entrada is File) {
      Directory(nueva.substring(0, nueva.lastIndexOf(Platform.pathSeparator)))
          .createSync(recursive: true);
      entrada.copySync(nueva);
    }
  }

  stdout.writeln(_verde('Instalado en ${destino.path}'));
  return 0;
}

int _validar(List<String> args) {
  final objetivos = <Directory>[];
  if (args.isEmpty) {
    final carpeta = carpetaDeTemas();
    if (carpeta.existsSync()) {
      objetivos.addAll(carpeta.listSync().whereType<Directory>());
    }
    if (objetivos.isEmpty) {
      stdout.writeln('No hay temas instalados en ${carpeta.path}.');
      return 0;
    }
  } else {
    objetivos.addAll(args.map(Directory.new));
  }

  var errores = 0;
  var avisos = 0;

  for (final carpeta in objetivos) {
    final nombre = carpeta.path
        .replaceAll(RegExp(r'[\\/]+$'), '')
        .split(RegExp(r'[\\/]'))
        .last;
    stdout.writeln('\n${_gris('──')} $nombre');

    if (!carpeta.existsSync()) {
      stdout.writeln('  ${_rojo('error')}  no existe ${carpeta.path}');
      errores++;
      continue;
    }
    final manifiesto =
        File('${carpeta.path}${Platform.pathSeparator}$kNombreDelManifiesto');
    if (!manifiesto.existsSync()) {
      stdout.writeln('  ${_rojo('error')}  falta $kNombreDelManifiesto');
      errores++;
      continue;
    }

    Map<String, dynamic> raiz;
    try {
      final decodificado = jsonDecode(manifiesto.readAsStringSync());
      if (decodificado is! Map) {
        stdout.writeln('  ${_rojo('error')}  el fichero debe ser un objeto '
            'JSON, empezando por {');
        errores++;
        continue;
      }
      raiz = decodificado.cast<String, dynamic>();
    } on FormatException catch (e) {
      stdout.writeln(
          '  ${_rojo('error')}  JSON roto${lugarDelFallo(e)}: ${e.message}');
      stdout.writeln('  ${_gris('pista: en JSON no valen comentarios ni una '
          'coma detrás del último campo.')}');
      errores++;
      continue;
    }

    final presentes = <String>{};
    for (final entrada in carpeta.listSync(recursive: true)) {
      if (entrada is File) {
        presentes.add(entrada.path
            .substring(carpeta.path.length + 1)
            .replaceAll('\\', '/'));
      }
    }

    final problemas = validarManifiesto(
      raiz,
      ficherosPresentes: presentes,
      comprobarFicheros: true,
    );

    if (problemas.isEmpty) {
      stdout.writeln('  ${_verde('correcto')}');
    }
    for (final problema in problemas) {
      if (problema.grave) {
        errores++;
        stdout.writeln('  ${_rojo('error')}  ${problema.ruta}: '
            '${problema.mensaje}');
      } else {
        avisos++;
        stdout.writeln('  ${_amarillo('aviso')}  ${problema.ruta}: '
            '${problema.mensaje}');
      }
    }

    final colores = (raiz['colores'] as Map?) ?? const {};
    final tira = StringBuffer();
    for (final clave in clavesDeColores) {
      final argb = parsearColor(colores[clave] as String?);
      if (argb != null) tira.write(_muestra(argb));
    }
    if (tira.isNotEmpty) stdout.writeln('  $tira');
  }

  stdout.writeln('\n$errores error(es), $avisos aviso(s).');
  return errores > 0 ? 1 : 0;
}
