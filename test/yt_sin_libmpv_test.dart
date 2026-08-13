import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/yt_models.dart';
import 'package:neofy/core/yt_player.dart';

/// La regresión que se cobró la serie 0.2 en Arch.
///
/// `media_kit` no empaqueta libmpv en Linux: la abre del sistema con `dlopen`
/// al inicializarse. Como esa inicialización va en `main()` **antes** de
/// `runApp()`, en un Arch sin `mpv` instalado la app abría y se cerraba sin
/// ventana y sin un mensaje que mirar. El arreglo de verdad es que los paquetes
/// declaren la dependencia; esto es la red de seguridad para quien instala el
/// tarball, que no puede exigir nada: la via libre se apaga y NeoFy sigue entera.
///
/// Lo que se fija aquí es que **construir el reproductor sin libmpv no lanza**.
/// Antes ni se podía llegar a intentar: el objeto se creaba en el constructor
/// de la pantalla raíz, así que una excepción aquí se lleva por delante la app
/// completa, NeoFy incluido.
void main() {
  // Se restaura al terminar: es estado global y dejarlo tocado apagaría
  // la via libre en cualquier test que corra después en este mismo proceso.
  tearDown(() => YtPlayer.libmpvDisponible = true);

  YtPlayer sinLibmpv() {
    YtPlayer.libmpvDisponible = false;
    return YtPlayer(volumenInicial: 40);
  }

  test('sin libmpv el reproductor se construye, pero se declara no disponible', () {
    final p = sinLibmpv();
    addTearDown(p.dispose);

    expect(p.disponible, isFalse);
    // Con algo que enseñar: la interfaz lo pinta tal cual, y un
    // hueco en blanco no le dice a nadie que le falta un paquete.
    expect(p.error, isNotEmpty);
    // El volumen guardado se conserva aunque no haya nada a lo que aplicarlo:
    // así vuelve a estar donde estaba en cuanto se instale libmpv.
    expect(p.volumen, 40);
  });

  test('sin libmpv nada de lo que hace la interfaz lanza', () async {
    final p = sinLibmpv();
    addTearDown(p.dispose);

    // Los accesores que consume la barra inferior. Sin reproductor detrás
    // tienen que dar valores neutros, no reventar.
    expect(p.sonando, isFalse);
    expect(p.posicion, Duration.zero);
    expect(p.duracion, Duration.zero);
    expect(p.cambiosDeSonando, isNotNull);
    expect(p.cambiosDePosicion, isNotNull);

    // Y los mandos, que siguen estando en pantalla mientras el shell se pinta.
    await p.alternar();
    await p.pause();
    await p.resume();
    await p.siguiente();
    await p.anterior();
    await p.seek(const Duration(seconds: 30));
    await p.setVolumen(75);
    await p.stop();

    // Pedir que suene algo no hace nada y, sobre todo, no deja media cola
    // puesta fingiendo que va a sonar.
    await p.reproducirLista([
      const YtTrack(videoId: 'aaaaaaaaaaa', titulo: 'Una', artista: 'Alguien'),
    ]);
    expect(p.cola, isEmpty);
    expect(p.actual, isNull);
  });
}
