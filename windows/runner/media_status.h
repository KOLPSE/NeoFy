#ifndef RUNNER_MEDIA_STATUS_H_
#define RUNNER_MEDIA_STATUS_H_

#include <cstdint>
#include <string>

struct EstadoMultimedia {
  bool hay_cancion = false;
  bool sonando = false;

  std::wstring titulo;
  std::wstring artista;
  std::wstring album;

  std::wstring caratula;

  bool puede_saltar = false;
  bool puede_volver = false;

  int64_t duracion_ms = 0;
  int64_t posicion_ms = 0;
};

enum class ComandoMultimedia {
  kPlayPause = 0,
  kPlay = 1,
  kPause = 2,
  kNext = 3,
  kPrevious = 4,
  kStop = 5,
  kSeek = 6,
};

#endif
