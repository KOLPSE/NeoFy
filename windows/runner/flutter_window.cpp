#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"
#include "volumen_sesion.h"

namespace {

constexpr int kHotKeyPlayPause = 1;
constexpr int kHotKeyNext = 2;
constexpr int kHotKeyPrevious = 3;
constexpr int kHotKeyStop = 4;

constexpr const char kMediaKeysChannel[] = "neofy/media_keys";
constexpr const char kAudioDeviceChannel[] = "neofy/audio_device";
constexpr const char kSystemMediaChannel[] = "neofy/system_media";
constexpr const char kVolumenSesionChannel[] = "neofy/volumen_sesion";

constexpr UINT kAudioDeviceChangedMessage = WM_APP + 1;

constexpr UINT kSystemMediaCommandMessage = WM_APP + 2;

const flutter::EncodableValue* Buscar(const flutter::EncodableMap& mapa,
                                      const char* clave) {
  const auto it = mapa.find(flutter::EncodableValue(clave));
  return it == mapa.end() ? nullptr : &it->second;
}

bool LeerBool(const flutter::EncodableMap& mapa, const char* clave) {
  const auto* valor = Buscar(mapa, clave);
  const auto* b = valor == nullptr ? nullptr : std::get_if<bool>(valor);
  return b != nullptr && *b;
}

std::wstring LeerTexto(const flutter::EncodableMap& mapa, const char* clave) {
  const auto* valor = Buscar(mapa, clave);
  const auto* s = valor == nullptr ? nullptr : std::get_if<std::string>(valor);
  return s == nullptr ? std::wstring() : Utf16FromUtf8(*s);
}

int64_t LeerEntero(const flutter::EncodableMap& mapa, const char* clave) {
  const auto* valor = Buscar(mapa, clave);
  if (valor == nullptr) {
    return 0;
  }
  if (const auto* pequeno = std::get_if<int32_t>(valor)) {
    return *pequeno;
  }
  if (const auto* grande = std::get_if<int64_t>(valor)) {
    return *grande;
  }
  return 0;
}

}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
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

  audio_device_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kAudioDeviceChannel,
          &flutter::StandardMethodCodec::GetInstance());
  StartAudioDeviceWatcher();

  system_media_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kSystemMediaChannel,
          &flutter::StandardMethodCodec::GetInstance());
  system_media_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { OnSystemMediaCall(call, std::move(result)); });
  StartSystemMedia();

  volumen_sesion_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kVolumenSesionChannel,
          &flutter::StandardMethodCodec::GetInstance());
  volumen_sesion_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { OnVolumenSesionCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

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

void FlutterWindow::StartAudioDeviceWatcher() {
  audio_device_watcher_.Start(GetHandle(), kAudioDeviceChangedMessage);
}

void FlutterWindow::StartSystemMedia() {
  system_media_.Start(GetHandle(), kSystemMediaCommandMessage);
  thumb_bar_.Start(GetHandle(), [this](ComandoMultimedia comando) {
    EnviarComando(comando, 0);
  });
}

void FlutterWindow::OnVolumenSesionCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "set") {
    result->NotImplemented();
    return;
  }
  const auto* argumentos = call.arguments();
  const auto* mapa =
      argumentos == nullptr ? nullptr
                            : std::get_if<flutter::EncodableMap>(argumentos);
  if (mapa == nullptr) {
    result->Error("argumentos", "se esperaba un mapa");
    return;
  }
  result->Success(flutter::EncodableValue(
      SetVolumenLibrespot(static_cast<int>(LeerEntero(*mapa, "percent")))));
}

void FlutterWindow::OnSystemMediaCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "update") {
    result->NotImplemented();
    return;
  }
  const auto* argumentos = call.arguments();
  const auto* mapa =
      argumentos == nullptr ? nullptr
                            : std::get_if<flutter::EncodableMap>(argumentos);
  if (mapa == nullptr) {
    result->Error("argumentos", "se esperaba un mapa");
    return;
  }

  EstadoMultimedia estado;
  estado.hay_cancion = LeerBool(*mapa, "hayCancion");
  estado.sonando = LeerBool(*mapa, "sonando");
  estado.titulo = LeerTexto(*mapa, "titulo");
  estado.artista = LeerTexto(*mapa, "artista");
  estado.album = LeerTexto(*mapa, "album");
  estado.caratula = LeerTexto(*mapa, "caratula");
  estado.puede_saltar = LeerBool(*mapa, "puedeSaltar");
  estado.puede_volver = LeerBool(*mapa, "puedeVolver");
  estado.duracion_ms = LeerEntero(*mapa, "duracionMs");
  estado.posicion_ms = LeerEntero(*mapa, "posicionMs");

  system_media_.Update(estado);
  thumb_bar_.Update(estado);
  result->Success();
}

void FlutterWindow::EnviarComando(ComandoMultimedia comando,
                                  int64_t posicion_ms) {
  if (!system_media_channel_) {
    return;
  }
  if (comando == ComandoMultimedia::kSeek) {
    system_media_channel_->InvokeMethod(
        "seek", std::make_unique<flutter::EncodableValue>(posicion_ms));
    return;
  }
  const char* nombre = nullptr;
  switch (comando) {
    case ComandoMultimedia::kPlayPause:
      nombre = "playPause";
      break;
    case ComandoMultimedia::kPlay:
      nombre = "play";
      break;
    case ComandoMultimedia::kPause:
      nombre = "pause";
      break;
    case ComandoMultimedia::kNext:
      nombre = "next";
      break;
    case ComandoMultimedia::kPrevious:
      nombre = "previous";
      break;
    case ComandoMultimedia::kStop:
      nombre = "stop";
      break;
    default:
      return;
  }
  system_media_channel_->InvokeMethod(
      nombre, std::make_unique<flutter::EncodableValue>());
}

void FlutterWindow::OnDestroy() {
  audio_device_watcher_.Stop();
  audio_device_channel_ = nullptr;
  system_media_.Stop();
  thumb_bar_.Stop();
  system_media_channel_ = nullptr;
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

  if (message == kAudioDeviceChangedMessage && audio_device_channel_) {
    audio_device_channel_->InvokeMethod(
        "defaultDeviceChanged", std::make_unique<flutter::EncodableValue>());
    return 0;
  }

  if (message == kSystemMediaCommandMessage) {
    EnviarComando(static_cast<ComandoMultimedia>(wparam),
                  static_cast<int64_t>(lparam));
    return 0;
  }

  if (thumb_bar_.MessageHandler(message, wparam, lparam)) {
    return 0;
  }

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
