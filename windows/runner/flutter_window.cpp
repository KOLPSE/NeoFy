#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Identificadores locales de cada atajo global. Solo tienen que ser únicos
// dentro de esta ventana.
constexpr int kHotKeyPlayPause = 1;
constexpr int kHotKeyNext = 2;
constexpr int kHotKeyPrevious = 3;
constexpr int kHotKeyStop = 4;

constexpr const char kMediaKeysChannel[] = "neofy/media_keys";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  media_keys_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaKeysChannel,
          &flutter::StandardMethodCodec::GetInstance());
  RegisterMediaKeys();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

// El botón de play/pausa de unos cascos manda VK_MEDIA_PLAY_PAUSE, la misma
// tecla que el teclado multimedia. Windows la entrega a quien la haya
// registrado con RegisterHotKey, y llega aunque la app esté en segundo plano o
// escondida en la bandeja — que es justo cuando hace falta.
//
// MOD_NOREPEAT evita que dejar el dedo puesto dispare una ráfaga de pausas.
void FlutterWindow::RegisterMediaKeys() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  struct {
    int id;
    UINT vk;
  } keys[] = {
      {kHotKeyPlayPause, VK_MEDIA_PLAY_PAUSE},
      {kHotKeyNext, VK_MEDIA_NEXT_TRACK},
      {kHotKeyPrevious, VK_MEDIA_PREV_TRACK},
      {kHotKeyStop, VK_MEDIA_STOP},
  };
  for (const auto& key : keys) {
    // Si otra app se adelantó (el Spotify oficial, por ejemplo), RegisterHotKey
    // falla para esa tecla. No es motivo para nada: simplemente no la tenemos.
    if (::RegisterHotKey(hwnd, key.id, MOD_NOREPEAT, key.vk)) {
      media_keys_registered_ = true;
    }
  }
}

void FlutterWindow::UnregisterMediaKeys() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || !media_keys_registered_) {
    return;
  }
  for (int id : {kHotKeyPlayPause, kHotKeyNext, kHotKeyPrevious, kHotKeyStop}) {
    ::UnregisterHotKey(hwnd, id);
  }
  media_keys_registered_ = false;
}

void FlutterWindow::OnDestroy() {
  UnregisterMediaKeys();
  media_keys_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // WM_HOTKEY se atiende antes de dárselo a Flutter: es un mensaje de la
  // ventana, no de la vista, y ningún plugin lo espera.
  if (message == WM_HOTKEY && media_keys_channel_) {
    const char* action = nullptr;
    switch (static_cast<int>(wparam)) {
      case kHotKeyPlayPause:
        action = "playPause";
        break;
      case kHotKeyNext:
        action = "next";
        break;
      case kHotKeyPrevious:
        action = "previous";
        break;
      case kHotKeyStop:
        action = "pause";
        break;
      default:
        break;
    }
    if (action != nullptr) {
      media_keys_channel_->InvokeMethod(
          action, std::make_unique<flutter::EncodableValue>());
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
