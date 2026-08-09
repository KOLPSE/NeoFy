#ifndef RUNNER_MEDIA_STATUS_H_
#define RUNNER_MEDIA_STATUS_H_

#include <cstdint>
#include <string>

// Lo que hay que enseñar en los controles multimedia del sistema.
//
// Lo llenan los datos que manda Dart por `neofy/system_media` y lo consumen las
// dos integraciones de Windows, que enseñan lo mismo en dos sitios distintos:
// `SystemMediaControls` (el panel del centro de control, el que aparece al
// pulsar una tecla multimedia) y `ThumbBar` (los botones bajo la miniatura de
// la barra de tareas). Está aparte para que ninguna de las dos dependa de la
// otra.
struct EstadoMultimedia {
  // Sin canción no hay nada que enseñar, y no es lo mismo que estar en pausa:
  // el sistema quiere saber que el reproductor está parado para quitarlo del
  // panel en vez de dejarlo ahí con los botones muertos.
  bool hay_cancion = false;
  bool sonando = false;

  std::wstring titulo;
  std::wstring artista;
  std::wstring album;

  // Ruta absoluta de la carátula **ya descargada**, o vacía. Nunca una url: el
  // panel del sistema no debe salir a la red, y la app ya la tiene en disco.
  std::wstring caratula;

  bool puede_saltar = false;
  bool puede_volver = false;

  int64_t duracion_ms = 0;
  int64_t posicion_ms = 0;
};

// Lo que el usuario puede pedir desde fuera de la ventana.
//
// Se manda a Dart por el mismo canal; el reparto entre `Play`, `Pause` y
// `PlayPause` no es un capricho, es que el panel del sistema distingue las tres
// cosas y mapear su botón de reproducir a un toggle pausaría lo que ya suena.
enum class ComandoMultimedia {
  kPlayPause = 0,
  kPlay = 1,
  kPause = 2,
  kNext = 3,
  kPrevious = 4,
  kStop = 5,
  kSeek = 6,
};

#endif  // RUNNER_MEDIA_STATUS_H_
