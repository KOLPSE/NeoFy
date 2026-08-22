#include "volumen_sesion.h"

#include <windows.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <string>

namespace {

bool EsLibrespot(DWORD pid) {
  HANDLE proceso =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (proceso == nullptr) {
    return false;
  }
  wchar_t ruta[MAX_PATH];
  DWORD tam = MAX_PATH;
  bool ok = false;
  if (::QueryFullProcessImageNameW(proceso, 0, ruta, &tam)) {
    std::wstring s(ruta, tam);
    for (auto& c : s) {
      if (c >= L'A' && c <= L'Z') {
        c = static_cast<wchar_t>(c - L'A' + L'a');
      }
    }
    ok = s.size() >= 13 && s.rfind(L"librespot.exe") == s.size() - 13;
  }
  ::CloseHandle(proceso);
  return ok;
}

bool AplicarEnDispositivo(IMMDevice* dispositivo, float nivel, bool* encontrado) {
  IAudioSessionManager2* manager = nullptr;
  HRESULT hr = dispositivo->Activate(__uuidof(IAudioSessionManager2),
                                     CLSCTX_ALL, nullptr,
                                     reinterpret_cast<void**>(&manager));
  if (FAILED(hr) || manager == nullptr) {
    return false;
  }

  IAudioSessionEnumerator* lista = nullptr;
  hr = manager->GetSessionEnumerator(&lista);
  if (FAILED(hr) || lista == nullptr) {
    manager->Release();
    return false;
  }

  int count = 0;
  lista->GetCount(&count);
  for (int i = 0; i < count; i++) {
    IAudioSessionControl* control = nullptr;
    if (FAILED(lista->GetSession(i, &control)) || control == nullptr) {
      continue;
    }
    IAudioSessionControl2* control2 = nullptr;
    hr = control->QueryInterface(__uuidof(IAudioSessionControl2),
                                 reinterpret_cast<void**>(&control2));
    control->Release();
    if (FAILED(hr) || control2 == nullptr) {
      continue;
    }
    DWORD pid = 0;
    control2->GetProcessId(&pid);
    if (pid != 0 && EsLibrespot(pid)) {
      ISimpleAudioVolume* volumen = nullptr;
      hr = control2->QueryInterface(__uuidof(ISimpleAudioVolume),
                                    reinterpret_cast<void**>(&volumen));
      if (SUCCEEDED(hr) && volumen != nullptr) {
        volumen->SetMasterVolume(nivel, nullptr);
        volumen->Release();
        *encontrado = true;
      }
    }
    control2->Release();
  }
  lista->Release();
  manager->Release();
  return true;
}

}

bool SetVolumenLibrespot(int percent) {
  const float nivel = percent < 0 ? 0.0f : (percent > 100 ? 1.0f : percent / 100.0f);

  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr) || enumerator == nullptr) {
    return false;
  }

  IMMDeviceCollection* coleccion = nullptr;
  hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &coleccion);
  bool encontrado = false;
  if (SUCCEEDED(hr) && coleccion != nullptr) {
    UINT n = 0;
    coleccion->GetCount(&n);
    for (UINT i = 0; i < n; i++) {
      IMMDevice* dispositivo = nullptr;
      if (SUCCEEDED(coleccion->Item(i, &dispositivo)) && dispositivo != nullptr) {
        AplicarEnDispositivo(dispositivo, nivel, &encontrado);
        dispositivo->Release();
      }
    }
    coleccion->Release();
  }
  enumerator->Release();
  return encontrado;
}
