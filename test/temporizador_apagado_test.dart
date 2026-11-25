import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/app_config.dart';
import 'package:neofy/core/auth.dart';
import 'package:neofy/core/player_state.dart';
import 'package:neofy/core/spotify_api.dart';
import 'package:neofy/core/temporizador_apagado.dart';

class _ConfigPrueba extends AppConfig {
  @override
  Future<void> save() async {}
}

void main() {
  test('activarMinutos inicia cuenta atrás y cancelar la detiene', () {
    final config = _ConfigPrueba();
    final player = PlayerController(SpotifyApi(SpotifyAuth(config)), config);
    addTearDown(player.dispose);

    final timer = TemporizadorApagado(player, onPausar: () async {});
    addTearDown(timer.dispose);

    expect(timer.activo, isFalse);
    timer.activarMinutos(15);
    expect(timer.activo, isTrue);
    expect(timer.alFinalDeLaCancion, isFalse);
    expect(timer.etiquetaRestante, '15:00');

    timer.cancelar();
    expect(timer.activo, isFalse);
    expect(timer.etiquetaRestante, isEmpty);
  });

  test('activarFinDeCancion dispara onPausar cuando cambia la pista', () async {
    final config = _ConfigPrueba();
    final player = PlayerController(SpotifyApi(SpotifyAuth(config)), config);
    addTearDown(player.dispose);
    player.currentUri.value = 'spotify:track:uno';

    var pausas = 0;
    final timer = TemporizadorApagado(
      player,
      onPausar: () async {
        pausas++;
      },
    );
    addTearDown(timer.dispose);

    timer.activarFinDeCancion();
    expect(timer.activo, isTrue);
    expect(timer.alFinalDeLaCancion, isTrue);
    expect(timer.etiquetaRestante, 'Al final de la canción');

    player.currentUri.value = 'spotify:track:dos';
    await Future<void>.delayed(Duration.zero);

    expect(pausas, 1);
    expect(timer.activo, isFalse);
  });
}
