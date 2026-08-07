#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

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
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
