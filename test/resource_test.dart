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
    test('smaps_rollup da el Pss, que es lo que la app le cuesta al equipo', () {
      // El RSS cuenta enteras las librerias compartidas (GTK, Mesa, Pango...),
      // que no son memoria de NeoFy. El Pss reparte cada pagina entre quienes
      // la usan: 61.234 kB frente a los 198.104 kB de Rss del mismo proceso.
      const rollup = 'Rss:              198104 kB\n'
          'Pss:               61234 kB\n'
          'Pss_Dirty:         44100 kB\n'
          'Shared_Clean:     130000 kB\n'
          'Private_Dirty:     40000 kB\n';
      expect(ResourceMonitor.pssDeSmapsRollup(rollup), 61234 * 1024);
    });

    test('no se confunde Pss con Pss_Dirty ni con Pss_Anon', () {
      // Quedarse con el primer campo que empiece por "Pss" daria un numero
      // plausible y equivocado, que es la peor clase de error para algo que
      // solo se mira de reojo. Aqui el Pss de verdad va el ultimo a proposito.
      const rollup = 'Pss_Dirty:          1000 kB\n'
          'Pss_Anon:            700 kB\n'
          'Pss_File:            200 kB\n'
          'Pss_Shmem:           100 kB\n'
          'Pss:               54321 kB\n';
      expect(ResourceMonitor.pssDeSmapsRollup(rollup), 54321 * 1024);
    });

    test('un smaps_rollup sin Pss vale cero, para poder caer al statm', () {
      // Devolver cero es lo que hace que _medirLinux use el RSS de plan B en
      // vez de ensenar una app que no gasta nada.
      expect(ResourceMonitor.pssDeSmapsRollup(''), 0);
      expect(ResourceMonitor.pssDeSmapsRollup('Rss: 198104 kB'), 0);
      expect(ResourceMonitor.pssDeSmapsRollup('Pss: no-es-un-numero kB'), 0);
    });

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
