#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

// Identificadores locales de cada atajo global. Solo tienen que ser únicos
// dentro de esta ventana.
constexpr int kHotKeyPlayPause = 1;
constexpr int kHotKeyNext = 2;
constexpr int kHotKeyPrevious = 3;
constexpr int kHotKeyStop = 4;

constexpr const char kMediaKeysChannel[] = "neofy/media_keys";
constexpr const char kAudioDeviceChannel[] = "neofy/audio_device";
constexpr const char kSystemMediaChannel[] = "neofy/system_media";

// Mensaje propio con el que el vigilante de audio —que corre en un hilo del
// servicio de audio de Windows— le pasa el aviso al hilo de la ventana. WM_APP
// es el rango reservado justo para esto; WM_USER se lo reparten los controles.
constexpr UINT kAudioDeviceChangedMessage = WM_APP + 1;

// Lo mismo para los botones del panel multimedia del sistema, que también
// llegan en un hilo ajeno. El comando va en el wParam y, si es un salto, la
// posición en milisegundos en el lParam.
constexpr UINT kSystemMediaCommandMessage = WM_APP + 2;

// Lectores del mapa que manda Dart. Todo es opcional a propósito: un campo que
// falte tiene que dejar el resto en pie, no tirar la llamada entera.
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

// Los enteros de Dart llegan como int32 o int64 según su tamaño, y una duración
// en milisegundos cabe en los dos: hay que aceptar ambos o las canciones cortas
// se leerían y las largas no.
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

// El vigilante no es imprescindible: si el servicio de audio no contesta, la
// app sigue funcionando exactamente igual y lo único que se pierde es el
// reinicio automático al cambiar de altavoces. No es motivo para fallar el
// arranque.
void FlutterWindow::StartAudioDeviceWatcher() {
  audio_device_watcher_.Start(GetHandle(), kAudioDeviceChangedMessage);
}

// Las dos caras de lo mismo: que Windows sepa que NeoFy es un reproductor. El
// panel del sistema y la miniatura de la barra de tareas son integraciones
// distintas —una es WinRT y la otra COM de toda la vida— pero enseñan el mismo
// estado y devuelven los mismos comandos, así que se arrancan juntas y las
// alimenta un solo canal.
//
// Ninguna de las dos es imprescindible: si el sistema no las ofrece, la app
// funciona exactamente igual y lo que se pierde son los controles de fuera.
void FlutterWindow::StartSystemMedia() {
  system_media_.Start(GetHandle(), kSystemMediaCommandMessage);
  thumb_bar_.Start(GetHandle(), [this](ComandoMultimedia comando) {
    // Los botones de la miniatura ya llegan por la cola de mensajes de la
    // ventana, así que no hace falta rebotarlos como los del panel.
    EnviarComando(comando, 0);
  });
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
  // Antes que el canal: al pararse dejan de anunciarse, y el panel del sistema
  // no se queda con NeoFy y su última canción después de cerrar.
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

  // El aviso llega desde un hilo del servicio de audio con un PostMessage, así
  // que aquí ya estamos en el hilo de la ventana y se puede hablar con Flutter.
  if (message == kAudioDeviceChangedMessage && audio_device_channel_) {
    audio_device_channel_->InvokeMethod(
        "defaultDeviceChanged", std::make_unique<flutter::EncodableValue>());
    return 0;
  }

  // Lo mismo para los botones del panel multimedia del sistema: los manda un
  // hilo de WinRT y aquí ya estamos en el de la ventana.
  if (message == kSystemMediaCommandMessage) {
    EnviarComando(static_cast<ComandoMultimedia>(wparam),
                  static_cast<int64_t>(lparam));
    return 0;
  }

  // La barra de miniatura mira sus propios mensajes: el aviso de que la barra
  // de tareas ya tiene botón, los clics de sus tres botones y los cambios de
  // tema. Solo se queda con los que son suyos del todo.
  if (thumb_bar_.MessageHandler(message, wparam, lparam)) {
    return 0;
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
