import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/temas.dart';
import 'package:neofy/core/temas_incluidos.dart';
import 'package:path/path.dart' as p;

import '../tool/tema.dart' as herramienta;

void main() {
  group('parsearColor', () {
    test('acepta los formatos que documenta TEMAS.md', () {
      expect(parsearColor('#1DB954'), const Color(0xFF1DB954));
      expect(parsearColor('1DB954'), const Color(0xFF1DB954));
      expect(parsearColor('0x1DB954'), const Color(0xFF1DB954));
      expect(parsearColor('#F55'), const Color(0xFFFF5555));
      expect(parsearColor('#801DB954'), const Color(0x801DB954));
      expect(parsearColor('29,185,84'), const Color(0xFF1DB954));
      expect(parsearColor('29, 185, 84, 128'), const Color(0x801DB954));
    });

    test('rechaza lo que no es un color en vez de inventarse uno', () {
      expect(parsearColor(null), isNull);
      expect(parsearColor(''), isNull);
      expect(parsearColor('rojo'), isNull);
      expect(parsearColor('#12345'), isNull);
      expect(parsearColor('300,0,0'), isNull);
      expect(parsearColor('29,185'), isNull);
    });

    test('la app y la herramienta entienden lo mismo', () {
      const corpus = [
        '#1DB954',
        '1db954',
        '#F55',
        '#801DB954',
        '29,185,84',
        '29,185,84,128',
        'rojo',
        '#12345',
        '300,0,0',
        '',
      ];
      for (final crudo in corpus) {
        final enLaApp = parsearColor(crudo);
        final enLaHerramienta = herramienta.parsearColor(crudo);
        expect(
          enLaApp?.toARGB32(),
          enLaHerramienta,
          reason: 'discrepan con "$crudo"',
        );
      }
    });
  });

  group('Tema.desdeJson', () {
    test('un tema mínimo se completa solo', () {
      final cargado = leerTemaDeTexto('''
        {"nombre": "Mínimo", "brillo": "oscuro",
         "colores": {"primario": "#1DB954"}}
      ''');
      final tema = cargado.tema;

      expect(cargado.avisos, isEmpty);
      expect(tema.id, 'minimo');
      expect(tema.nombre, 'Mínimo');
      expect(tema.esOscuro, isTrue);
      expect(tema.colores.primario, const Color(0xFF1DB954));
      expect(tema.colores.fondo, const Color(0xFF121212));
      expect(tema.colores.panel, isNot(tema.colores.fondo));
      expect(tema.cristal.activo, isFalse);
      expect(tema.fondo.hayAlgoQuePintar, isFalse);
    });

    test('sin nombre o sin primario se niega a cargar', () {
      expect(
        () => leerTemaDeTexto('{"brillo": "oscuro", '
            '"colores": {"primario": "#FFF"}}'),
        throwsA(isA<ErrorDeTema>()),
      );
      expect(
        () => leerTemaDeTexto('{"nombre": "X", "colores": {}}'),
        throwsA(isA<ErrorDeTema>()),
      );
      expect(
        () => leerTemaDeTexto('{"nombre": "X"}'),
        throwsA(isA<ErrorDeTema>()),
      );
    });

    test('el JSON roto da un error legible, no un stack trace', () {
      expect(
        () => leerTemaDeTexto('{"nombre": "X",}'),
        throwsA(isA<ErrorDeTema>()
            .having((e) => e.mensaje, 'mensaje', contains('JSON'))),
      );
    });

    test('un color ilegible avisa y sigue, no tumba el tema', () {
      final cargado = leerTemaDeTexto('''
        {"nombre": "Torcido", "brillo": "claro",
         "colores": {"primario": "#1DB954", "texto": "azulito"}}
      ''');
      expect(cargado.avisos, isNotEmpty);
      expect(cargado.avisos.first, contains('texto'));
      expect(cargado.tema.colores.texto, isNotNull);
    });

    test('un brillo inventado avisa y cae en oscuro', () {
      final cargado = leerTemaDeTexto('''
        {"nombre": "Raro", "brillo": "morado",
         "colores": {"primario": "#1DB954"}}
      ''');
      expect(cargado.avisos.single, contains('brillo'));
      expect(cargado.tema.esOscuro, isTrue);
    });

    test('un degradado de un solo color se descarta con aviso', () {
      final cargado = leerTemaDeTexto('''
        {"nombre": "Medio", "colores": {"primario": "#1DB954"},
         "fondo": {"degradado": ["#000000"]}}
      ''');
      expect(cargado.avisos, isNotEmpty);
      expect(cargado.tema.fondo.degradado, isEmpty);
    });

    test('los números fuera de rango se recortan en vez de romper', () {
      final tema = leerTemaDeTexto('''
        {"nombre": "Bestia", "colores": {"primario": "#1DB954"},
         "cristal": {"desenfoque": 9000, "opacidad": -3}}
      ''').tema;
      expect(tema.cristal.desenfoque, 80);
      expect(tema.cristal.opacidad, 0);
    });
  });

  group('recursos del tema', () {
    test('no deja salir de la carpeta del tema', () {
      final carpeta = p.join(p.separator, 'temas', 'mio');
      final tema = leerTemaDeTexto(
        '{"nombre": "X", "colores": {"primario": "#1DB954"}}',
        carpeta: carpeta,
      ).tema;

      expect(tema.rutaDeRecurso('fondo.jpg'), isNotNull);
      expect(tema.rutaDeRecurso('sub/fondo.jpg'), isNotNull);
      expect(tema.rutaDeRecurso('../../otro.jpg'), isNull);
      expect(tema.rutaDeRecurso(r'..\..\otro.jpg'), isNull);
    });

    test('un tema sin carpeta no resuelve nada', () {
      final tema = leerTemaDeTexto(
        '{"nombre": "X", "colores": {"primario": "#1DB954"}}',
      ).tema;
      expect(tema.rutaDeRecurso('fondo.jpg'), isNull);
    });
  });

  group('ThemeData', () {
    test('las claves del tema llegan al ColorScheme que usa la UI', () {
      final tema = leerTemaDeTexto('''
        {"nombre": "Prueba", "brillo": "oscuro", "radio": 20,
         "colores": {"primario": "#1DB954", "fondo": "#101010",
                     "panel": "#050505", "superficie": "#1A1A1A",
                     "texto": "#EEEEEE", "textoTenue": "#999999",
                     "borde": "#333333"}}
      ''').tema;
      final datos = construirThemeData(tema);
      final esquema = datos.colorScheme;

      expect(esquema.brightness, Brightness.dark);
      expect(esquema.primary, const Color(0xFF1DB954));
      expect(esquema.surface, const Color(0xFF101010));
      expect(esquema.surfaceContainer, const Color(0xFF050505));
      expect(esquema.surfaceContainerHigh, const Color(0xFF1A1A1A));
      expect(esquema.onSurface, const Color(0xFFEEEEEE));
      expect(esquema.onSurfaceVariant, const Color(0xFF999999));
      expect(esquema.outline, const Color(0xFF333333));

      final estilo = datos.extension<EstiloNeoFy>();
      expect(estilo, isNotNull);
      expect(estilo!.radio, 20);
      expect(estilo.idDelTema, 'prueba');
    });

    test('sin cristal ni fondo, el Scaffold sigue siendo opaco', () {
      final datos = construirThemeData(temaOscuro);
      expect(datos.scaffoldBackgroundColor, temaOscuro.colores.fondo);
    });

    test('con cristal el Scaffold se vuelve transparente para que se vea', () {
      final datos = construirThemeData(temaLiquidGlass);
      expect(datos.scaffoldBackgroundColor, Colors.transparent);
      expect(datos.extension<EstiloNeoFy>()!.cristal.activo, isTrue);
    });

    test('el texto sobre el primario contrasta en los dos sentidos', () {
      expect(contrasteSobre(const Color(0xFF000000)), Colors.white);
      expect(contrasteSobre(const Color(0xFFFFFFFF)), Colors.black);
    });
  });

  group('temas incluidos', () {
    test('los ids son únicos y no chocan con el de "sigue al sistema"', () {
      final ids = temasIncluidos.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, isNot(contains(kIdTemaDelSistema)));
    });

    test('están los que se prometieron: claro, oscuro, los tres colores y '
        'el cristal', () {
      final ids = temasIncluidos.map((t) => t.id).toSet();
      expect(
        ids,
        containsAll([
          'claro',
          'oscuro',
          'verde-claro',
          'verde-oscuro',
          'azul-claro',
          'azul-oscuro',
          'rojo-claro',
          'rojo-oscuro',
          'material-claro',
          'material-oscuro',
          'liquid-glass',
        ]),
      );
    });

    test('los de Material mezclan radios: contenedor redondeado y botón '
        'completamente redondo', () {
      for (final tema in [temaMaterialClaro, temaMaterialOscuro]) {
        expect(tema.radio, 26);
        expect(tema.radioBoton, 999);
        expect(tema.radioCaratula, 16);
        expect(tema.navegacion, EstiloDeNavegacion.pildora);
        expect(tema.movimiento.esquema, EsquemaDeMovimiento.expresivo);
        expect(tema.cristal.activo, isFalse);
        expect(tema.fondo.hayAlgoQuePintar, isFalse);
      }
    });

    test('solo el movimiento expresivo rebasa; el sobrio no', () {
      const expresivo = Movimiento(esquema: EsquemaDeMovimiento.expresivo);
      const sobrio = Movimiento();
      const ninguno = Movimiento(esquema: EsquemaDeMovimiento.ninguno);

      expect(expresivo.rebota, isTrue);
      expect(sobrio.rebota, isFalse);
      expect(ninguno.seMueve, isFalse);

      expect(
        expresivo.espacialRapido.damping,
        lessThan(sobrio.espacialRapido.damping),
        reason: 'menos amortiguación es lo que produce el rebote',
      );
      expect(expresivo.efecto.damping, sobrio.efecto.damping,
          reason: 'los muelles de efecto nunca rebasan, en ningún esquema');
    });

    test('la velocidad acorta la duración, y por tanto sube la rigidez', () {
      const normal = Movimiento(esquema: EsquemaDeMovimiento.expresivo);
      const rapido =
          Movimiento(esquema: EsquemaDeMovimiento.expresivo, velocidad: 2);
      expect(rapido.espacialNormal.stiffness,
          greaterThan(normal.espacialNormal.stiffness));
    });

    test('con radio 12, la escala derivada es exactamente la de Material 3',
        () {
      final escala = Formas.desdeRadio(12);
      expect(escala.extraPequeno, 4);
      expect(escala.pequeno, 8);
      expect(escala.medio, 12);
      expect(escala.grande, 16);
      expect(escala.extraGrande, 24);
    });

    test('la escala llega a los sitios que dice Compose', () {
      final datos = construirThemeData(temaMaterialOscuro);
      final formas = temaMaterialOscuro.escalaDeFormas;

      BorderRadius radioDe(ShapeBorder? forma) =>
          ((forma! as RoundedRectangleBorder).borderRadius as BorderRadius);

      expect(radioDe(datos.cardTheme.shape).topLeft.x, formas.medio);
      expect(radioDe(datos.dialogTheme.shape).topLeft.x, formas.extraGrande);
      expect(radioDe(datos.popupMenuTheme.shape).topLeft.x, formas.pequeno);
      expect(radioDe(datos.snackBarTheme.shape).topLeft.x,
          formas.extraPequeno);
    });

    test('los de Material engordan title y label, como manda la tabla del '
        'type scale', () {
      final datos = construirThemeData(temaMaterialOscuro);
      expect(datos.textTheme.titleLarge?.fontWeight, FontWeight.w600);
      expect(datos.textTheme.labelLarge?.fontWeight, FontWeight.w600);
      expect(datos.textTheme.bodyLarge?.fontWeight,
          isNot(FontWeight.w600),
          reason: 'el cuerpo se queda en normal; solo title y label suben');
    });

    test('los clásicos conservan la forma de siempre', () {
      for (final tema in [temaOscuro, temaClaro, temaVerdeOscuro]) {
        expect(tema.radioCaratula, kRadioDeCaratulaPorDefecto);
        expect(tema.navegacion, EstiloDeNavegacion.lista);
        expect(tema.radioBoton, isNull);
        expect(tema.movimiento.esquema, EsquemaDeMovimiento.sobrio);
        expect(tema.formas, isNull);
        expect(tema.tipografia.pesoTitulos, isNull);
      }
    });

    test('en Material oscuro el panel es más claro que el fondo, al revés que '
        'en el resto', () {
      expect(
        temaMaterialOscuro.colores.panel.computeLuminance(),
        greaterThan(temaMaterialOscuro.colores.fondo.computeLuminance()),
      );
      expect(
        temaOscuro.colores.panel.computeLuminance(),
        lessThan(temaOscuro.colores.fondo.computeLuminance()),
      );
    });

    test('cada uno construye su ThemeData sin reventar', () {
      for (final tema in temasIncluidos) {
        final datos = construirThemeData(tema);
        expect(datos.colorScheme.brightness,
            tema.esOscuro ? Brightness.dark : Brightness.light);
        expect(datos.extension<EstiloNeoFy>()!.idDelTema, tema.id);
      }
    });

    test('solo Liquid Glass trae el cristal encendido', () {
      for (final tema in temasIncluidos) {
        expect(tema.cristal.activo, tema.id == 'liquid-glass',
            reason: 'en ${tema.id}');
      }
    });

    test('el texto se lee sobre el fondo en todos', () {
      for (final tema in temasIncluidos) {
        final fondo = tema.colores.fondo.computeLuminance();
        final texto = tema.colores.texto.computeLuminance();
        final claro = fondo > texto ? fondo : texto;
        final oscuro = fondo > texto ? texto : fondo;
        final contraste = (claro + 0.05) / (oscuro + 0.05);
        expect(contraste, greaterThan(7),
            reason: '${tema.id} no llega ni a AAA de texto normal');
      }
    });

    test('serializar y volver a leer da el mismo tema', () {
      for (final tema in temasIncluidos) {
        final vuelta = Tema.desdeJson(tema.aJson());
        expect(vuelta.id, tema.id);
        expect(vuelta.nombre, tema.nombre);
        expect(vuelta.brillo, tema.brillo);
        expect(vuelta.colores.primario, tema.colores.primario);
        expect(vuelta.colores.fondo, tema.colores.fondo);
        expect(vuelta.colores.panel, tema.colores.panel);
        expect(vuelta.cristal.activo, tema.cristal.activo);
        expect(vuelta.fondo.usarCaratula, tema.fondo.usarCaratula);
        expect(vuelta.fondo.degradado, tema.fondo.degradado);
        expect(vuelta.radio, tema.radio);
        expect(vuelta.radioBoton, tema.radioBoton);
        expect(vuelta.radioCaratula, tema.radioCaratula);
        expect(vuelta.navegacion, tema.navegacion);
        expect(vuelta.movimiento.esquema, tema.movimiento.esquema);
      }
    });
  });

  group('la herramienta y la app no se separan', () {
    test('todo tema incluido pasa el validador de tool/tema.dart sin un solo '
        'aviso', () {
      for (final tema in temasIncluidos) {
        final problemas = herramienta.validarManifiesto(tema.aJson());
        expect(problemas, isEmpty, reason: '${tema.id}: $problemas');
      }
    });

    test('lo que serializa la app no lleva bloques inertes', () {
      final plano = temaOscuro.aJson();
      expect(plano.containsKey('cristal'), isFalse);
      expect(plano.containsKey('fondo'), isFalse);
      expect(plano.containsKey('tipografia'), isFalse);

      final conCristal = temaLiquidGlass.aJson();
      expect(conCristal.containsKey('cristal'), isTrue);
      expect(conCristal.containsKey('fondo'), isTrue);
    });

    test('las plantillas que reparte la herramienta son válidas', () {
      for (final plantilla
          in [herramienta.plantilla, herramienta.plantillaCristal]) {
        final texto = plantilla.replaceAll('__NOMBRE__', 'Prueba');
        final cargado = leerTemaDeTexto(texto);
        expect(cargado.avisos, isEmpty);
        expect(cargado.tema.nombre, 'Prueba');

        final problemas = herramienta.validarManifiesto(
          Tema.desdeJson(cargado.tema.aJson()).aJson(),
        );
        expect(problemas.where((p) => p.grave), isEmpty);
      }
    });

    test('la herramienta conoce todas las claves que la app serializa', () {
      final serializado = temaLiquidGlass.aJson();
      expect(serializado.keys, everyElement(isIn(herramienta.clavesDeRaiz)));

      final colores = serializado['colores'] as Map<String, dynamic>;
      expect(colores.keys, everyElement(isIn(herramienta.clavesDeColores)));
    });

    test('la herramienta y la app dan el mismo id para un nombre', () {
      for (final nombre in ['Mi Tema', 'Añoranza  Azul', '¡¿?!', 'ÁÉÍÓÚñ']) {
        expect(herramienta.aId(nombre), idDesdeNombre(nombre),
            reason: 'con "$nombre"');
      }
    });
  });

  group('validador de la herramienta', () {
    test('caza el error típico: una clave mal escrita', () {
      final problemas = herramienta.validarManifiesto({
        'nombre': 'X',
        'brillo': 'oscuro',
        'colores': {'primario': '#1DB954', 'primarioo': '#000000'},
      });
      expect(problemas.map((p) => p.ruta), contains('colores.primarioo'));
    });

    test('caza un color inválido como error, no como aviso', () {
      final problemas = herramienta.validarManifiesto({
        'nombre': 'X',
        'colores': {'primario': 'verde lima'},
      });
      final grave = problemas.firstWhere((p) => p.grave);
      expect(grave.ruta, 'colores.primario');
    });

    test('impide que un tema lea ficheros de fuera de su carpeta', () {
      final problemas = herramienta.validarManifiesto({
        'nombre': 'X',
        'colores': {'primario': '#1DB954'},
        'fondo': {'imagen': '../../../etc/passwd'},
      });
      expect(problemas.any((p) => p.grave && p.ruta == 'fondo.imagen'), isTrue);
    });

    test('avisa de un bloque fondo que no pinta nada', () {
      final problemas = herramienta.validarManifiesto({
        'nombre': 'X',
        'colores': {'primario': '#1DB954'},
        'fondo': {'opacidad': 0.5},
      });
      expect(problemas.any((p) => !p.grave && p.ruta == 'fondo'), isTrue);
    });

    test('un tema correcto no da ni un problema', () {
      final problemas = herramienta.validarManifiesto({
        'formato': 1,
        'nombre': 'Limpio',
        'autor': 'alguien',
        'version': '1.0.0',
        'descripcion': 'sin peros',
        'brillo': 'claro',
        'radio': 12,
        'colores': {'primario': '#1DB954', 'fondo': '#FFFFFF'},
      });
      expect(problemas, isEmpty);
    });
  });
}
