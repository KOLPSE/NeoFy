#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "audio_device_watcher.h"
#include "media_status.h"
#include "system_media.h"
#include "thumb_bar.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Registra las teclas multimedia (play/pausa, siguiente, anterior) a nivel de
  // sistema. Se hace aquí, en C++, porque RegisterHotKey necesita un HWND y una
  // cola de mensajes: desde Dart no hay forma de ver un WM_HOTKEY.
  void RegisterMediaKeys();
  void UnregisterMediaKeys();

  // Vigila el dispositivo de salida por defecto. Cambiarlo con la música
  // sonando deja mudo a librespot, que abrió el suyo al arrancar y no se
  // entera del cambio; avisando a Dart, la app puede reiniciarlo sola.
  void StartAudioDeviceWatcher();

  // Los controles multimedia del sistema (panel del centro de control) y los
  // botones bajo la miniatura de la barra de tareas. Los dos enseñan lo mismo,
  // así que los alimenta un único canal desde Dart.
  void StartSystemMedia();

  // Traduce lo que llega por el canal al estado que quieren los dos.
  void OnSystemMediaCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Le cuenta a Dart que alguien ha pulsado algo fuera de la ventana.
  void EnviarComando(ComandoMultimedia comando, int64_t posicion_ms);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Por donde se le cuenta a Dart que se ha pulsado una tecla multimedia.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      media_keys_channel_;

  // Si ninguna llegó a registrarse (otra app se las quedó antes), no hay nada
  // que soltar al cerrar.
  bool media_keys_registered_ = false;

  // Por donde se le cuenta a Dart que la salida de audio ha cambiado.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      audio_device_channel_;

  AudioDeviceWatcher audio_device_watcher_;

  // Por donde Dart manda qué está sonando y por donde vuelven los botones del
  // panel del sistema y de la miniatura de la barra de tareas.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_media_channel_;

  SystemMediaControls system_media_;
  ThumbBar thumb_bar_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
