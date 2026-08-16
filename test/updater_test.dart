import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/updater.dart';

void main() {
  group('comparar versiones', () {
    test('detecta una versión más nueva', () {
      expect(Updater.esMasNueva('0.2.0', '0.1.0'), isTrue);
      expect(Updater.esMasNueva('1.0.0', '0.9.9'), isTrue);
      expect(Updater.esMasNueva('0.1.1', '0.1.0'), isTrue);
    });

    test('la misma versión no es más nueva', () {
      expect(Updater.esMasNueva('0.1.0', '0.1.0'), isFalse);
    });

    test('una versión vieja no cuenta como nueva', () {
      expect(Updater.esMasNueva('0.1.0', '0.2.0'), isFalse);
    });

    test('compara por números, no como texto', () {
      expect(Updater.esMasNueva('0.10.0', '0.9.0'), isTrue);
      expect(Updater.esMasNueva('0.9.0', '0.10.0'), isFalse);
      expect(Updater.esMasNueva('1.0.0', '0.99.99'), isTrue);
    });

    test('tolera tramos de más o de menos', () {
      expect(Updater.esMasNueva('0.2', '0.1.9'), isTrue);
      expect(Updater.esMasNueva('0.1.0', '0.1'), isFalse);
      expect(Updater.esMasNueva('0.1.0+2', '0.1.0+1'), isTrue);
    });

    test('la basura no revienta: se lee como cero', () {
      expect(Updater.esMasNueva('', '0.1.0'), isFalse);
      expect(Updater.esMasNueva('vX.Y', '0.1.0'), isFalse);
    });
  });

  test('la versión que anuncia el updater es la constante del proyecto', () {
    expect(Updater().versionActual, kVersion);
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kVersion), isTrue,
        reason: 'kVersion debe ser x.y.z: el instalador la usa tal cual');
  });
}
