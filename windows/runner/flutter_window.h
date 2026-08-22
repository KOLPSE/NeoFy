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

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RegisterMediaKeys();
  void UnregisterMediaKeys();

  void StartAudioDeviceWatcher();

  void StartSystemMedia();

  void OnSystemMediaCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnVolumenSesionCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void EnviarComando(ComandoMultimedia comando, int64_t posicion_ms);

  flutter::DartProject project_;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      media_keys_channel_;

  bool media_keys_registered_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      audio_device_channel_;

  AudioDeviceWatcher audio_device_watcher_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_media_channel_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      volumen_sesion_channel_;

  SystemMediaControls system_media_;
  ThumbBar thumb_bar_;
};

#endif
