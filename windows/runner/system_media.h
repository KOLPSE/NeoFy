#ifndef RUNNER_SYSTEM_MEDIA_H_
#define RUNNER_SYSTEM_MEDIA_H_

#include <windows.h>
#include <windows.media.h>
#include <wrl/client.h>

#include "media_status.h"

// Le cuenta a Windows que NeoFy es un reproductor de audio.
//
// Es la integración con los *System Media Transport Controls*: lo que hace que
// la app salga en el panel multimedia del centro de control, en el que aparece
// al pulsar una tecla multimedia y en la pantalla de bloqueo, con carátula,
// título, artista, barra de progreso y botones. Sin esto, para Windows NeoFy es
// una ventana cualquiera que resulta que hace ruido.
//
// Va por la ABI de WinRT (`ABI::Windows::Media`) con WRL y no por C++/WinRT a
// propósito: el runner se compila con `_HAS_EXCEPTIONS=0` y C++/WinRT informa
// de los errores lanzando. WRL es de la misma familia que el COM que ya usa el
// vigilante de audio y no lanza nada.
//
// ⚠️ **Los avisos llegan en un hilo del sistema**, no en el de la ventana. Por
// eso aquí no se toca ni Flutter ni la interfaz: se hace un `PostMessage` a la
// ventana con el comando en el `wParam` y la posición en el `lParam`, igual que
// el vigilante del dispositivo de audio.
class SystemMediaControls {
 public:
  SystemMediaControls() = default;
  ~SystemMediaControls();

  SystemMediaControls(const SystemMediaControls&) = delete;
  SystemMediaControls& operator=(const SystemMediaControls&) = delete;

  // Devuelve false si el sistema no ofrece los controles, que no es motivo para
  // nada: la app funciona igual y solo pierde el panel.
  bool Start(HWND window, UINT mensaje);
  void Stop();

  // Lo que hay que enseñar. Sin canción, limpia el panel entero.
  void Update(const EstadoMultimedia& estado);

 private:
  void ActualizarLinea(const EstadoMultimedia& estado);

  HWND window_ = nullptr;
  UINT mensaje_ = 0;

  Microsoft::WRL::ComPtr<ABI::Windows::Media::ISystemMediaTransportControls>
      smtc_;
  EventRegistrationToken token_boton_ = {};
  EventRegistrationToken token_salto_ = {};
};

#endif  // RUNNER_SYSTEM_MEDIA_H_
