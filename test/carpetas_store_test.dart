import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/carpetas_store.dart';

void main() {
  // Un directorio temporal único: el CI corre los tests en paralelo y dos
  // stores sobre el mismo `carpetas.json` pisarían sus ficheros.
  String dirTemporal() {
    final raiz = Directory('${Directory.systemTemp.path}'
        '/neofy_carpetas_${DateTime.now().microsecondsSinceEpoch}');
    if (!raiz.existsSync()) raiz.createSync(recursive: true);
    return raiz.path;
  }

  test('crear, mover y recargar conserva la estructura', () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();

    await store.crearCarpeta('Favoritas');
    await store.crearCarpeta('Para el gimnasio');
    // El orden dentro de la carpeta importa: se conserva tal cual se movió.
    await store.moverPlaylist('pl-1', store.carpetas[0].id);
    await store.moverPlaylist('pl-2', store.carpetas[0].id);
    await store.moverPlaylist('pl-3', store.carpetas[1].id);

    expect(store.carpetas, hasLength(2));
    expect(store.carpetas[0].playlistIds, ['pl-1', 'pl-2']);
    expect(store.carpetaDe('pl-1')?.id, store.carpetas[0].id);
    expect(store.carpetaDe('pl-9'), isNull);

    // Un store nuevo sobre el mismo directorio tiene que ver lo mismo:
    // es la única garantía de que no se pierde nada al cerrar la app.
    final recargado = CarpetasStore(directorio: dir);
    await recargado.cargar();
    expect(recargado.carpetas, hasLength(2));
    expect(recargado.carpetas[0].nombre, 'Favoritas');
    expect(recargado.carpetas[0].playlistIds, ['pl-1', 'pl-2']);
    expect(recargado.carpetas[1].nombre, 'Para el gimnasio');
    expect(recargado.carpetas[1].playlistIds, ['pl-3']);
    expect(recargado.carpetas[0].id, isNot(store.carpetas[1].id));
  });

  test('mover a una id que no existe deja la playlist suelta, sin romper nada',
      () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    await store.crearCarpeta('Algo');
    await store.moverPlaylist('pl-x', 'carpeta-que-no-existe');

    expect(store.carpetas[0].playlistIds, isEmpty);

    // Sacarla de la carpeta la deja suelta: la id desaparece del fichero y el
    // siguiente arranque no la vuelve a meter.
    await store.moverPlaylist('pl-y', store.carpetas[0].id);
    await store.moverPlaylist('pl-y', null);
    final recargado = CarpetasStore(directorio: dir);
    await recargado.cargar();
    expect(recargado.carpetas[0].playlistIds, isEmpty);
  });

  test('una playlist no se repite si se mueve dos veces a la misma carpeta',
      () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    await store.crearCarpeta('Algo');
    await store.moverPlaylist('pl-1', store.carpetas[0].id);
    await store.moverPlaylist('pl-1', store.carpetas[0].id);

    expect(store.carpetas[0].playlistIds, ['pl-1']);
  });

  test('borrar la carpeta no borra las playlists, solo la estructura',
      () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    await store.crearCarpeta('Algo');
    await store.moverPlaylist('pl-1', store.carpetas[0].id);
    await store.borrarCarpeta(store.carpetas[0].id);

    expect(store.carpetas, isEmpty);
    final recargado = CarpetasStore(directorio: dir);
    await recargado.cargar();
    expect(recargado.carpetas, isEmpty);
  });

  test('renombrar se guarda y sobrevive a la recarga', () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    await store.crearCarpeta('Algo');
    await store.renombrarCarpeta(store.carpetas[0].id, 'Otro nombre');

    final recargado = CarpetasStore(directorio: dir);
    await recargado.cargar();
    expect(recargado.carpetas[0].nombre, 'Otro nombre');
  });

  test('quitarPlaylist quita la id de todas las carpetas', () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    await store.crearCarpeta('A');
    await store.moverPlaylist('pl-1', store.carpetas[0].id);
    await store.quitarPlaylist('pl-1');
    expect(store.carpetas[0].playlistIds, isEmpty);
  });

  test('un JSON corrupto no impide arrancar: se cae a sin carpetas', () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/carpetas.json').writeAsStringSync('esto no es json {');

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    expect(store.carpetas, isEmpty);

    // Y sigue sirviendo para crear carpetas después del lío.
    await store.crearCarpeta('Nueva');
    expect(store.carpetas, hasLength(1));
  });

  test('sin fichero no hay carpetas y no revienta', () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    expect(store.carpetas, isEmpty);
  });

  test('una entrada mal formada del JSON se descarta sin tirar las demás',
      () async {
    final dir = Directory(dirTemporal());
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/carpetas.json').writeAsStringSync(jsonEncode({
      'carpetas': [
        {'id': 'ok', 'nombre': 'Válida', 'playlistIds': ['a']},
        {'id': 123, 'nombre': 'Rota'},
        {'id': null, 'nombre': null},
      ],
    }));

    final store = CarpetasStore(directorio: dir);
    await store.cargar();
    expect(store.carpetas, hasLength(1));
    expect(store.carpetas[0].nombre, 'Válida');
    expect(store.carpetas[0].playlistIds, ['a']);
  });
}