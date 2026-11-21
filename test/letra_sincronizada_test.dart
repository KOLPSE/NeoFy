import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/ui/letra_sincronizada.dart';

void main() {
  test('el offset de LRC se aplica a la línea y a las palabras', () {
    final linea = LineaDeLetra.leer({
      'syncedLyrics':
          '[offset:+500]\n[00:01.50]<00:01.50>Ey <00:02.00>tú<00:02.50>',
    }, 6000).single;

    expect(linea.inicioMs, 1000);
    expect(linea.en(1499).anterior, 'E');
    expect(linea.en(1500).actual, 't');
  });

  test('un offset negativo retrasa las letras', () {
    final linea = LineaDeLetra.leer({
      'syncedLyrics': '[offset:-350]\n[00:01.00] Letra',
    }, 5000).single;
    expect(linea.inicioMs, 1350);
    expect(linea.en(1349).actual, isEmpty);
  });

  test('el avance por línea mantiene enteros los grafemas Unicode', () {
    final linea = LineaDeLetra.leer({
      'syncedLyrics': '[00:01.00] Ae\u0301 👩‍🎤\n[00:02.00] Otra línea',
    }, 3000).first;

    expect(linea.en(1000).actual, 'A');
    expect(linea.en(1250).actual, 'e\u0301');
    expect(linea.en(1750).actual, '👩‍🎤');
    expect(linea.en(2000).anterior, 'Ae\u0301 👩‍🎤');
  });

  test('respeta la pausa entre palabras con tiempos de Lyricsfile', () {
    final linea = LineaDeLetra.leer({
      'syncedLyrics': '[00:01.00] Vamos ya',
      'lyricsfile': '''
lines:
  - text: Vamos ya
    start_ms: 1000
    end_ms: 3000
    words:
      - text: 'Vamos '
        start_ms: 1000
        end_ms: 1500
      - text: ya
        start_ms: 2500
        end_ms: 3000
''',
    }, 6000).single;

    expect(linea.en(1500).anterior, 'Vamos');
    expect(linea.en(2200).actual, isEmpty);
    expect(linea.en(2500).actual, 'y');
    expect(linea.en(2890).actual, 'a');
    expect(linea.en(3000).anterior, 'Vamos ya');
  });

  test('LRC ampliado conserva los tiempos al repetir una línea', () {
    final lineas = LineaDeLetra.leer({
      'syncedLyrics': '[00:01.00][00:05.00]<00:01.00>Ey <00:02.00>tú<00:03.00>',
      'lyricsfile': '[YAML mal cerrado',
    }, 9000);

    expect(lineas.map((linea) => linea.inicioMs), [1000, 5000]);
    expect(lineas.last.texto, 'Ey tú');
    expect(lineas.last.en(6000).actual, 't');
    expect(lineas.last.en(7000).anterior, 'Ey tú');
  });
}
