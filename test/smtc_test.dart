import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/models.dart';
import 'package:neofy/core/reproductor_del_sistema.dart';
import 'package:neofy/core/smtc.dart';

Track _track({
  String id = '4cOdK2wGLETKBW3PvgPWqT',
  String name = 'Never Gonna Give You Up',
  int durationMs = 213573,
}) =>
    Track(
      id: id,
      uri: 'spotify:track:$id',
      name: name,
      artists: 'Rick Astley',
      album: 'Whenever You Need Somebody',
      artSmall: 'https://i.scdn.co/image/smtc-pequena',
      artMedium: 'https://i.scdn.co/image/smtc-mediana',
      durationMs: durationMs,
      isLocal: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('neofy/system_media');
  final llamadas = <MethodCall>[];

  Map<Object?, Object?> ultimoEstado() =>
      llamadas.last.arguments as Map<Object?, Object?>;

  EstadoDelSistema estado = EstadoDelSistema.vacio;

  late SmtcService smtc;

  setUp(() {
    llamadas.clear();
    estado = EstadoDelSistema.vacio;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      llamadas.add(call);
      return null;
    });
    smtc = SmtcService(
      onPlayPause: () async {},
      onPlay: () async {},
      onPause: () async {},
      onNext: () async {},
      onPrevious: () async {},
      onSeek: (_) async {},
      estado: () => estado,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  group('lo que se le manda a Windows', () {
    test('sin canción no se anuncia una en pausa', () async {
      estado = EstadoDelSistema.vacio;
      smtc.start();
      await Future<void>.delayed(Duration.zero);

      expect(ultimoEstado()['hayCancion'], isFalse);
      expect(ultimoEstado()['sonando'], isFalse);
      expect(ultimoEstado()['puedeSaltar'], isFalse);
    });

    test('la duración va en el estado, que es de donde sale la barra', () async {
      estado = EstadoDelSistema(
        track: _track(durationMs: 213573),
        sonando: true,
        posicionMs: 42000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.start();
      await Future<void>.delayed(Duration.zero);

      expect(ultimoEstado()['hayCancion'], isTrue);
      expect(ultimoEstado()['sonando'], isTrue);
      expect(ultimoEstado()['titulo'], 'Never Gonna Give You Up');
      expect(ultimoEstado()['artista'], 'Rick Astley');
      expect(ultimoEstado()['album'], 'Whenever You Need Somebody');
      expect(ultimoEstado()['duracionMs'], 213573);
      expect(ultimoEstado()['posicionMs'], 42000);
    });

    test('no se repite el anuncio si no ha cambiado nada', () async {
      estado = EstadoDelSistema(
        track: _track(),
        sonando: true,
        posicionMs: 1000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.start();
      await Future<void>.delayed(Duration.zero);
      final despuesDelPrimero = llamadas.length;

      estado = EstadoDelSistema(
        track: _track(),
        sonando: true,
        posicionMs: 4000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.notificarCambio();
      await Future<void>.delayed(Duration.zero);
      expect(llamadas.length, despuesDelPrimero);
    });

    test('pausar sí se anuncia, aunque no cambie la canción', () async {
      estado = EstadoDelSistema(
        track: _track(),
        sonando: true,
        posicionMs: 1000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.start();
      await Future<void>.delayed(Duration.zero);

      estado = EstadoDelSistema(
        track: _track(),
        sonando: false,
        posicionMs: 1000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.notificarCambio();
      await Future<void>.delayed(Duration.zero);
      expect(ultimoEstado()['sonando'], isFalse);
    });

    test('un salto se anuncia aunque la firma no haya cambiado', () async {
      estado = EstadoDelSistema(
        track: _track(),
        sonando: true,
        posicionMs: 1000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.start();
      await Future<void>.delayed(Duration.zero);

      smtc.notificarSalto(90000);
      await Future<void>.delayed(Duration.zero);
      expect(ultimoEstado()['posicionMs'], 90000);
    });

    test('cerrar sesión deja el panel vacío', () async {
      estado = EstadoDelSistema(
        track: _track(),
        sonando: true,
        posicionMs: 1000,
        puedeSaltar: true,
        puedeVolver: true,
        volumen: 70,
      );
      smtc.start();
      await Future<void>.delayed(Duration.zero);

      await smtc.stop();
      expect(ultimoEstado()['hayCancion'], isFalse);
      expect(smtc.activo, isFalse);
    });
  }, skip: !Platform.isWindows);

  group('carátula', () {
    final dir = Directory(p.join(cacheDir().path, 'art'));

    File ficheroDe(String url) =>
        File(p.join(dir.path, '${sha1.convert(url.codeUnits)}.img'));

    setUp(() => dir.createSync(recursive: true));

    test('a Windows se le da la ruta, no la url file://', () {
      final f = ficheroDe('https://i.scdn.co/image/smtc-mediana');
      f.writeAsBytesSync([1, 2, 3]);
      addTearDown(() => f.existsSync() ? f.deleteSync() : null);

      final ruta = ficheroDeCaratula(_track())!.path;
      expect(ruta, isNot(startsWith('file:')));
      expect(File(ruta).existsSync(), isTrue);
      expect(caratulaEnDisco(_track()), startsWith('file:'));
    });

    test('sin nada en disco no se inventa una ruta', () {
      final f = ficheroDe('https://i.scdn.co/image/smtc-mediana');
      if (f.existsSync()) f.deleteSync();
      final g = ficheroDe('https://i.scdn.co/image/smtc-pequena');
      if (g.existsSync()) g.deleteSync();

      expect(ficheroDeCaratula(_track()), isNull);
      expect(caratulaEnDisco(_track()), isNull);
    });
  });
}
