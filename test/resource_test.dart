import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/resource_monitor.dart';

void main() {
  group('UsoDeRecursos', () {
    test('el total son los tres procesos, no solo la interfaz', () {
      const uso = UsoDeRecursos(app: 108 << 20, audio: 25 << 20, metadatos: 13 << 20);
      expect(UsoDeRecursos.mb(uso.app), '108 MB');
      expect(UsoDeRecursos.mb(uso.total), '146 MB');
    });

    test('un sidecar caido cuenta como cero, no rompe la suma', () {
      const uso = UsoDeRecursos(app: 100 << 20);
      expect(uso.total, 100 << 20);
    });

    test('la CPU va normalizada a la maquina, no a un nucleo', () {
      const uso = UsoDeRecursos(app: 1, cpu: 12.5);
      expect(uso.cpu, 12.5);
    });

    test('las oscilaciones de menos de un mega no repintan', () {
      const a = UsoDeRecursos(app: 100 << 20, audio: 25 << 20);
      final b = UsoDeRecursos(app: (100 << 20) + 300000, audio: 25 << 20);
      expect(b.pareceIgualQue(a), isTrue);

      final c = UsoDeRecursos(app: (100 << 20) + (3 << 20), audio: 25 << 20);
      expect(c.pareceIgualQue(a), isFalse);

      const igualDeCpu = UsoDeRecursos(app: 100 << 20, audio: 25 << 20, cpu: 0.3);
      expect(igualDeCpu.pareceIgualQue(a), isTrue);
      const saltoDeCpu = UsoDeRecursos(app: 100 << 20, audio: 25 << 20, cpu: 4);
      expect(saltoDeCpu.pareceIgualQue(a), isFalse);
    });
  });

  group('/proc (Linux)', () {
    test('smaps_rollup da el Pss, que es lo que la app le cuesta al equipo', () {
      const rollup = 'Rss:              198104 kB\n'
          'Pss:               61234 kB\n'
          'Pss_Dirty:         44100 kB\n'
          'Shared_Clean:     130000 kB\n'
          'Private_Dirty:     40000 kB\n';
      expect(ResourceMonitor.pssDeSmapsRollup(rollup), 61234 * 1024);
    });

    test('no se confunde Pss con Pss_Dirty ni con Pss_Anon', () {
      const rollup = 'Pss_Dirty:          1000 kB\n'
          'Pss_Anon:            700 kB\n'
          'Pss_File:            200 kB\n'
          'Pss_Shmem:           100 kB\n'
          'Pss:               54321 kB\n';
      expect(ResourceMonitor.pssDeSmapsRollup(rollup), 54321 * 1024);
    });

    test('un smaps_rollup sin Pss vale cero, para poder caer al statm', () {
      expect(ResourceMonitor.pssDeSmapsRollup(''), 0);
      expect(ResourceMonitor.pssDeSmapsRollup('Rss: 198104 kB'), 0);
      expect(ResourceMonitor.pssDeSmapsRollup('Pss: no-es-un-numero kB'), 0);
    });

    test('statm da el residente, no el espacio virtual', () {
      expect(ResourceMonitor.rssDeStatm('1035661 17890 9012 45 0 21033 0'),
          17890 * 4096);
    });

    test('un statm truncado no revienta', () {
      expect(ResourceMonitor.rssDeStatm(''), 0);
      expect(ResourceMonitor.rssDeStatm('1035661'), 0);
    });

    test('stat suma utime y stime en unidades de 100 ns', () {
      final stat = '4242 (librespot) S 1 4242 4242 0 -1 4194304 5000 0 0 0 '
          '120 30 0 0 20 0 12 0 987654 123456789 17890';
      expect(ResourceMonitor.ticksDeStat(stat), 150 * 100000);
    });

    test('un nombre de proceso con espacios y parentesis no desalinea', () {
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
