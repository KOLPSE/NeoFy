#include "audio_device_watcher.h"

#include <objbase.h>

namespace {

// Implementación mínima de IMMNotificationClient: de los seis avisos que trae
// la interfaz solo interesa uno, pero hay que declararlos todos.
class Notificador : public IMMNotificationClient {
 public:
  Notificador(HWND window, UINT message) : window_(window), message_(message) {}

  // ------------------------------------------------------------- IUnknown
  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_);
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG restantes = InterlockedDecrement(&ref_);
    if (restantes == 0) {
      delete this;
    }
    return restantes;
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (ppv == nullptr) {
      return E_POINTER;
    }
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IMMNotificationClient)) {
      *ppv = static_cast<IMMNotificationClient*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }

  // -------------------------------------------------- IMMNotificationClient

  // El único que importa. eRender es la salida (lo contrario, eCapture, es el
  // micrófono) y eConsole es el rol que elige cpal —la capa que hay debajo del
  // backend rodio de librespot— cuando pide "el dispositivo por defecto". Los
  // otros roles cambian sin que la música se mueva de sitio, así que dejarlos
  // pasar evita reinicios de audio que no arreglarían nada.
  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                                   LPCWSTR) override {
    if (flow == eRender && role == eConsole) {
      ::PostMessage(window_, message_, 0, 0);
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR, DWORD) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR,
                                                   const PROPERTYKEY) override {
    return S_OK;
  }

 private:
  // Solo se destruye por Release(); el destructor va privado para que nadie lo
  // borre con delete.
  ~Notificador() = default;

  LONG ref_ = 1;
  HWND window_;
  UINT message_;
};

}  // namespace

AudioDeviceWatcher::~AudioDeviceWatcher() {
  Stop();
}

bool AudioDeviceWatcher::Start(HWND window, UINT message) {
  if (client_ != nullptr) {
    return true;
  }
  if (window == nullptr) {
    return false;
  }

  // Los GUID se sacan con __uuidof y no de las constantes CLSID_/IID_: esas
  // solo están declaradas en la cabecera y arrastrarían uuid.lib al enlazado.
  HRESULT hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&enumerator_));
  if (FAILED(hr) || enumerator_ == nullptr) {
    enumerator_ = nullptr;
    return false;
  }

  auto* notificador = new Notificador(window, message);
  hr = enumerator_->RegisterEndpointNotificationCallback(notificador);
  if (FAILED(hr)) {
    notificador->Release();
    enumerator_->Release();
    enumerator_ = nullptr;
    return false;
  }
  client_ = notificador;
  return true;
}

void AudioDeviceWatcher::Stop() {
  if (enumerator_ != nullptr && client_ != nullptr) {
    enumerator_->UnregisterEndpointNotificationCallback(client_);
  }
  if (client_ != nullptr) {
    client_->Release();
    client_ = nullptr;
  }
  if (enumerator_ != nullptr) {
    enumerator_->Release();
    enumerator_ = nullptr;
  }
}
