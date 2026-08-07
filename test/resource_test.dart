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
}
