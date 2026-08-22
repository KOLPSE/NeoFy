import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/volumen_local.dart';

void main() {
  test('encuentra el sink-input de librespot y no el de otras apps', () {
    const listado = '''
Sink Input #12
	Volume: front-left: 65536
	application.name = "Firefox"
	application.process.binary = "firefox"
Sink Input #18
	Volume: front-left: 65536
	application.name = "librespot"
	application.process.binary = "librespot"
Sink Input #21
	application.process.binary = "pipewire"
''';

    expect(entradasDeLibrespot(listado), ['18']);
  });

  test('sin librespot no inventa ids', () {
    expect(entradasDeLibrespot('Sink Input #1\n\tapplication.name = "mpv"'), isEmpty);
    expect(entradasDeLibrespot(''), isEmpty);
  });
}
