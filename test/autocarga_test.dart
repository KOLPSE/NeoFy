import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/ui/shell.dart' show hayQuePedirMas;

void main() {
  group('hayQuePedirMas (la paginación sin scroll)', () {
    test('con la lista que no desborda y páginas que quedan, se pide más', () {
      expect(
        hayQuePedirMas(
          quedanPaginas: true,
          cargando: false,
          hayError: false,
          desborda: false,
          seccionAbierta: true,
        ),
        isTrue,
      );
    });

    test('si la lista desborda, lo pide el scroll: aquí no se suma', () {
      expect(
        hayQuePedirMas(
          quedanPaginas: true,
          cargando: false,
          hayError: false,
          desborda: true,
          seccionAbierta: true,
        ),
        isFalse,
      );
    });

    test('sin páginas que queden no se pide más, nunca', () {
      expect(
        hayQuePedirMas(
          quedanPaginas: false,
          cargando: false,
          hayError: false,
          desborda: false,
          seccionAbierta: true,
        ),
        isFalse,
      );
    });

    test('mientras una petición vuela no se solapan otras', () {
      expect(
        hayQuePedirMas(
          quedanPaginas: true,
          cargando: true,
          hayError: false,
          desborda: false,
          seccionAbierta: true,
        ),
        isFalse,
      );
    });

    test('con la sección plegada no se descarga nada por detrás', () {
      expect(
        hayQuePedirMas(
          quedanPaginas: true,
          cargando: false,
          hayError: false,
          desborda: false,
          seccionAbierta: false,
        ),
        isFalse,
      );
    });

    test('un error no se reintenta en bucle', () {
      expect(
        hayQuePedirMas(
          quedanPaginas: true,
          cargando: false,
          hayError: true,
          desborda: false,
          seccionAbierta: true,
        ),
        isFalse,
      );
    });
  });
}
