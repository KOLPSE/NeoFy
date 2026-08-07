#ifndef RUNNER_AUDIO_DEVICE_WATCHER_H_
#define RUNNER_AUDIO_DEVICE_WATCHER_H_

#include <mmdeviceapi.h>
#include <windows.h>

// Avisa cuando Windows cambia el dispositivo de salida de audio por defecto.
//
// Hace falta porque librespot abre el dispositivo **una vez**, al arrancar, y
// se queda con ese: si mientras suena la música el usuario se pone unos cascos
// o cambia la salida en la barra de tareas, el flujo se queda hablando con un
// dispositivo que ya no reproduce nada. Ni librespot se entera ni Spotify
// tampoco — sigue diciendo que la canción avanza — así que el único síntoma es
// el silencio, y la única salida era matar el proceso y volver a abrir la app.
//
// Windows solo lo cuenta por COM, con IMMNotificationClient, y la llamada llega
// en un hilo cualquiera del servicio de audio. Por eso no se toca aquí ni el
// canal de Flutter ni nada de la interfaz: se hace un PostMessage a la ventana
// y quien decide qué hacer es el hilo de siempre.
class AudioDeviceWatcher {
 public:
  AudioDeviceWatcher() = default;
  ~AudioDeviceWatcher();

  AudioDeviceWatcher(const AudioDeviceWatcher&) = delete;
  AudioDeviceWatcher& operator=(const AudioDeviceWatcher&) = delete;

  // Empieza a vigilar. Cada cambio del dispositivo de salida por defecto manda
  // |message| a |window|. Devuelve false si el servicio de audio no está
  // disponible, que no es motivo para nada: la app funciona igual, solo pierde
  // el arreglo automático.
  bool Start(HWND window, UINT message);
  void Stop();

 private:
  IMMDeviceEnumerator* enumerator_ = nullptr;
  IMMNotificationClient* client_ = nullptr;
};

#endif  // RUNNER_AUDIO_DEVICE_WATCHER_H_
