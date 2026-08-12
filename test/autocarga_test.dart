import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/ui/shell.dart' show hayQuePedirMas;

void main() {
  group('hayQuePedirMas (la paginación sin scroll)', () {
    test('con la lista que no desborda y páginas que quedan, se pide más', () {
      // Es exactamente el fallo que se corrige: todo lo descargado vive dentro
      // de una carpeta plegada, la lista se queda en una fila y no hay scroll
      // que dispare la página siguiente.
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
      // La condición de `_loadMore` es `_hasMore && !_loading`; `_hasMore`
      // false es apagar la paginación. Que la lista quede corta no lo revierte.
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
      // Sin este guard, cada página que llega encadenaría la siguiente en el
      // mismo instante y el scroll infinito cargaría de golpe todo lo que
      // queda: el `_loadMore` se protege con `_loading`.
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
      // Plegada no hay lista, así que tampoco hay scroll y `desborda` se queda
      // en false para siempre. Sin este caso cubierto, plegar "TUS PLAYLISTS"
      // encadenaría página tras página hasta bajarse la biblioteca entera —
      // exactamente lo que la paginación evita.
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
      // Con la red caída, este aviso correría tras cada build: sin el guard, un
      // 429 o un timeout se re-pediría a cada frame para no enseñar nada.
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