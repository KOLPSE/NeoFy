import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/resource_monitor.dart';

void main() {
  group('UsoDeRecursos', () {
    test('el total son los tres procesos, no solo la interfaz', () {
      const uso = UsoDeRecursos(app: 108 << 20, audio: 25 << 20, metadatos: 13 << 20);
      // Es el punto entero de la funcion: mirar solo `app` se deja fuera un
      // 26 % del gasto, que es lo que ensena el Administrador de tareas.
      expect(UsoDeRecursos.mb(uso.app), '108 MB');
      expect(UsoDeRecursos.mb(uso.total), '146 MB');
    });

    test('un sidecar caido cuenta como cero, no rompe la suma', () {
      const uso = UsoDeRecursos(app: 100 << 20);
      expect(uso.total, 100 << 20);
    });

    test('la CPU va normalizada a la maquina, no a un nucleo', () {
      const uso = UsoDeRecursos(app: 1, cpu: 12.5);
      // 12,5 % significa un octavo de la maquina entera. Sin normalizar por
      // nucleos, un solo hilo a tope daria 100 % y asustaria sin motivo.
      expect(uso.cpu, 12.5);
    });

    test('las oscilaciones de menos de un mega no repintan', () {
      const a = UsoDeRecursos(app: 100 << 20, audio: 25 << 20);
      // El working set baila constantemente; repintar por 300 KB seria ruido.
      final b = UsoDeRecursos(app: (100 << 20) + 300000, audio: 25 << 20);
      expect(b.pareceIgualQue(a), isTrue);

      final c = UsoDeRecursos(app: (100 << 20) + (3 << 20), audio: 25 << 20);
      expect(c.pareceIgualQue(a), isFalse);

      // Y lo mismo con la CPU: medio punto arriba o abajo es ruido.
      const igualDeCpu = UsoDeRecursos(app: 100 << 20, audio: 25 << 20, cpu: 0.3);
      expect(igualDeCpu.pareceIgualQue(a), isTrue);
      const saltoDeCpu = UsoDeRecursos(app: 100 << 20, audio: 25 << 20, cpu: 4);
      expect(saltoDeCpu.pareceIgualQue(a), isFalse);
    });
  });

  // Se prueba el parseo con cadenas fijas y no leyendo /proc de verdad, para
  // que estos tests valgan tambien en el runner de Windows del CI.
  group('/proc (Linux)', () {
    test('statm da el residente, no el espacio virtual', () {
      // size resident shared text lib data dt, en paginas de 4 KiB. El primero
      // es el espacio de direcciones, que con Skia son gigas y no mide nada.
      expect(ResourceMonitor.rssDeStatm('1035661 17890 9012 45 0 21033 0'),
          17890 * 4096);
    });

    test('un statm truncado no revienta', () {
      expect(ResourceMonitor.rssDeStatm(''), 0);
      expect(ResourceMonitor.rssDeStatm('1035661'), 0);
    });

    test('stat suma utime y stime en unidades de 100 ns', () {
      // Campos 14 y 15 (utime=120, stime=30): 150 ticks de 10 ms = 1,5 s.
      final stat = '4242 (librespot) S 1 4242 4242 0 -1 4194304 5000 0 0 0 '
          '120 30 0 0 20 0 12 0 987654 123456789 17890';
      expect(ResourceMonitor.ticksDeStat(stat), 150 * 100000);
    });

    test('un nombre de proceso con espacios y parentesis no desalinea', () {
      // El campo 2 va entre parentesis y puede llevar de todo dentro. Partir la
      // linea por espacios desde el principio correria todos los campos y daria
      // una CPU inventada, sin que saltara ningun error.
      final stat = '4242 (un proceso (raro)) S 1 4242 4242 0 -1 4194304 5000 '
          '0 0 0 120 30 0 0 20 0 12 0 987654 123456789 17890';
      expect(ResourceMonitor.ticksDeStat(stat), 150 * 100000);
    });

    test('un stat truncado no revienta', () {
      expect(ResourceMonitor.ticksDeStat(''), 0);
      expect(ResourceMonitor.ticksDeStat('4242 (librespot) S 1 2 3'), 0);
    });
  });
}
