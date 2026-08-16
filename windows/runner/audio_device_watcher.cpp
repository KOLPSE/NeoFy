#include "audio_device_watcher.h"

#include <objbase.h>

namespace {

class Notificador : public IMMNotificationClient {
 public:
  Notificador(HWND window, UINT message) : window_(window), message_(message) {}

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
  ~Notificador() = default;

  LONG ref_ = 1;
  HWND window_;
  UINT message_;
};

}

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
