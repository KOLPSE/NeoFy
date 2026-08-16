import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/yt_models.dart';
import 'package:neofy/core/yt_player.dart';

void main() {
  tearDown(() => YtPlayer.libmpvDisponible = true);

  YtPlayer sinLibmpv() {
    YtPlayer.libmpvDisponible = false;
    return YtPlayer(volumenInicial: 40);
  }

  test('sin libmpv el reproductor se construye, pero se declara no disponible', () {
    final p = sinLibmpv();
    addTearDown(p.dispose);

    expect(p.disponible, isFalse);
    expect(p.error, isNotEmpty);
    expect(p.volumen, 40);
  });

  test('sin libmpv nada de lo que hace la interfaz lanza', () async {
    final p = sinLibmpv();
    addTearDown(p.dispose);

    expect(p.sonando, isFalse);
    expect(p.posicion, Duration.zero);
    expect(p.duracion, Duration.zero);
    expect(p.cambiosDeSonando, isNotNull);
    expect(p.cambiosDePosicion, isNotNull);

    await p.alternar();
    await p.pause();
    await p.resume();
    await p.siguiente();
    await p.anterior();
    await p.seek(const Duration(seconds: 30));
    await p.setVolumen(75);
    await p.stop();

    await p.reproducirLista([
      const YtTrack(videoId: 'aaaaaaaaaaa', titulo: 'Una', artista: 'Alguien'),
    ]);
    expect(p.cola, isEmpty);
    expect(p.actual, isNull);
  });
}
