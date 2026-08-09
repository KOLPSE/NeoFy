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

  // Lo que le llega al runner de C++. Es lo único que se puede comprobar desde
  // aquí: el panel del sistema en sí es COM y no existe en los tests.
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

  // El canal es del runner de Windows; en Linux esto no se arranca siquiera,
  // que allí el trabajo lo hace MPRIS.
  group('lo que se le manda a Windows', () {
    test('sin canción no se anuncia una en pausa', () async {
      estado = EstadoDelSistema.vacio;
      smtc.start();
      await Future<void>.delayed(Duration.zero);

      // ⚠️ Distinguir "sin canción" de "en pausa" es lo que decide si Windows
      // quita el reproductor del panel o lo deja ahí con los botones muertos.
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
      // El runner cuenta en milisegundos y convierte él a las unidades de
      // 100 ns de WinRT; mandarlo ya convertido lo multiplicaría dos veces.
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

      // El sondeo salta cada 3 s aunque no haya cambiado nada, y la posición
      // avanza sola: Windows la extrapola, así que no es motivo para anunciar.
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
      // Sin esto el panel del sistema se quedaría diciendo "reproduciendo" con
      // la música parada.
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
      // Windows lleva la posición por su cuenta desde la última que le dieron:
      // sin este aviso, arrastrar la barra dentro de NeoFy deja el panel del
      // sistema en el minuto de antes hasta que cambie la canción.
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
      // Si no, Windows se queda enseñando la última canción de una sesión que
      // ya no existe, con botones que no hacen nada.
      expect(ultimoEstado()['hayCancion'], isFalse);
      expect(smtc.activo, isFalse);
    });
  }, skip: !Platform.isWindows);

  // La carátula la comparten MPRIS y Windows, pero **no en el mismo formato**:
  // el escritorio de Linux quiere una url file:// y Windows la ruta a secas.
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
      // Y la de MPRIS sigue siendo la url, que es lo que pide su especificación.
      expect(caratulaEnDisco(_track()), startsWith('file:'));
    });

    test('sin nada en disco no se inventa una ruta', () {
      // Dar la url http haría que el sistema se la bajara por su cuenta, y
      // esperar a la descarga bloquearía la respuesta. La cache está vacía, así
      // que lo correcto es no dar nada.
      final f = ficheroDe('https://i.scdn.co/image/smtc-mediana');
      if (f.existsSync()) f.deleteSync();
      final g = ficheroDe('https://i.scdn.co/image/smtc-pequena');
      if (g.existsSync()) g.deleteSync();

      expect(ficheroDeCaratula(_track()), isNull);
      expect(caratulaEnDisco(_track()), isNull);
    });
  });
}
