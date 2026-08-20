#include "thumb_bar.h"

#include <commctrl.h>
#include <objbase.h>

#include <vector>

namespace {

constexpr int kBotonAnterior = 601;
constexpr int kBotonPlayPause = 602;
constexpr int kBotonSiguiente = 603;

struct Figura {
  const float* triangulo;
  const float* barra_a;
  const float* barra_b;
};

constexpr float kTriPlay[6] = {0.30f, 0.14f, 0.30f, 0.86f, 0.82f, 0.50f};
constexpr float kBarraPausaIzq[4] = {0.30f, 0.15f, 0.44f, 0.85f};
constexpr float kBarraPausaDer[4] = {0.56f, 0.15f, 0.70f, 0.85f};
constexpr float kTriSiguiente[6] = {0.20f, 0.17f, 0.20f, 0.83f, 0.63f, 0.50f};
constexpr float kBarraSiguiente[4] = {0.67f, 0.17f, 0.79f, 0.83f};
constexpr float kTriAnterior[6] = {0.80f, 0.17f, 0.80f, 0.83f, 0.37f, 0.50f};
constexpr float kBarraAnterior[4] = {0.21f, 0.17f, 0.33f, 0.83f};

constexpr Figura kFiguraPlay = {kTriPlay, nullptr, nullptr};
constexpr Figura kFiguraPausa = {nullptr, kBarraPausaIzq, kBarraPausaDer};
constexpr Figura kFiguraSiguiente = {kTriSiguiente, kBarraSiguiente, nullptr};
constexpr Figura kFiguraAnterior = {kTriAnterior, kBarraAnterior, nullptr};

constexpr int kMuestras = 4;

float Cruz(float ax, float ay, float bx, float by, float cx, float cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

bool EnTriangulo(float px, float py, const float* t) {
  const float d1 = Cruz(t[0], t[1], t[2], t[3], px, py);
  const float d2 = Cruz(t[2], t[3], t[4], t[5], px, py);
  const float d3 = Cruz(t[4], t[5], t[0], t[1], px, py);
  const bool negativo = d1 < 0.0f || d2 < 0.0f || d3 < 0.0f;
  const bool positivo = d1 > 0.0f || d2 > 0.0f || d3 > 0.0f;
  return !(negativo && positivo);
}

bool EnBarra(float px, float py, const float* r) {
  return px >= r[0] && px <= r[2] && py >= r[1] && py <= r[3];
}

bool EnFigura(float px, float py, const Figura& figura) {
  if (figura.triangulo != nullptr && EnTriangulo(px, py, figura.triangulo)) {
    return true;
  }
  if (figura.barra_a != nullptr && EnBarra(px, py, figura.barra_a)) {
    return true;
  }
  return figura.barra_b != nullptr && EnBarra(px, py, figura.barra_b);
}

bool TemaClaro() {
  DWORD valor = 0;
  DWORD tam = sizeof(valor);
  const LSTATUS r = ::RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &valor, &tam);
  if (r != ERROR_SUCCESS) {
    return false;
  }
  return valor != 0;
}

int LadoDelIcono() {
  const int lado = ::GetSystemMetrics(SM_CXSMICON);
  return lado < 16 ? 16 : lado;
}

HICON DibujarIcono(int lado, const Figura& figura, COLORREF tinta) {
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = lado;
  info.bmiHeader.biHeight = -lado;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  void* pixeles = nullptr;
  HBITMAP color =
      ::CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixeles, nullptr, 0);
  if (color == nullptr || pixeles == nullptr) {
    if (color != nullptr) {
      ::DeleteObject(color);
    }
    return nullptr;
  }

  const int rojo = GetRValue(tinta);
  const int verde = GetGValue(tinta);
  const int azul = GetBValue(tinta);
  const float lado_f = static_cast<float>(lado);
  const float muestras_f = static_cast<float>(kMuestras);

  auto* punto = static_cast<BYTE*>(pixeles);
  for (int y = 0; y < lado; ++y) {
    for (int x = 0; x < lado; ++x) {
      int dentro = 0;
      for (int sy = 0; sy < kMuestras; ++sy) {
        for (int sx = 0; sx < kMuestras; ++sx) {
          const float px =
              (static_cast<float>(x) + (static_cast<float>(sx) + 0.5f) / muestras_f) /
              lado_f;
          const float py =
              (static_cast<float>(y) + (static_cast<float>(sy) + 0.5f) / muestras_f) /
              lado_f;
          if (EnFigura(px, py, figura)) {
            ++dentro;
          }
        }
      }
      const int alfa = dentro * 255 / (kMuestras * kMuestras);
      punto[0] = static_cast<BYTE>(azul * alfa / 255);
      punto[1] = static_cast<BYTE>(verde * alfa / 255);
      punto[2] = static_cast<BYTE>(rojo * alfa / 255);
      punto[3] = static_cast<BYTE>(alfa);
      punto += 4;
    }
  }

  const size_t bytes_por_fila = ((static_cast<size_t>(lado) + 15) / 16) * 2;
  const std::vector<BYTE> ceros(bytes_por_fila * static_cast<size_t>(lado), 0);
  HBITMAP mascara = ::CreateBitmap(lado, lado, 1, 1, ceros.data());

  ICONINFO icono = {};
  icono.fIcon = TRUE;
  icono.hbmMask = mascara;
  icono.hbmColor = color;
  HICON resultado = ::CreateIconIndirect(&icono);

  if (mascara != nullptr) {
    ::DeleteObject(mascara);
  }
  ::DeleteObject(color);
  return resultado;
}

}

ThumbBar::~ThumbBar() {
  Stop();
}

void ThumbBar::Start(HWND window, Callback al_pulsar) {
  window_ = window;
  al_pulsar_ = std::move(al_pulsar);
  if (window_ == nullptr) {
    return;
  }
  mensaje_creada_ = ::RegisterWindowMessageW(L"TaskbarButtonCreated");
  if (mensaje_creada_ != 0) {
    ::ChangeWindowMessageFilterEx(window_, mensaje_creada_, MSGFLT_ALLOW,
                                  nullptr);
  }
}

void ThumbBar::Stop() {
  if (taskbar_ != nullptr) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  colocados_ = false;
  al_pulsar_ = nullptr;
  window_ = nullptr;
  SoltarIconos();
}

void ThumbBar::Update(const EstadoMultimedia& estado) {
  estado_ = estado;
  Refrescar();
}

bool ThumbBar::MessageHandler(UINT message, WPARAM wparam, LPARAM lparam) {
  if (mensaje_creada_ != 0 && message == mensaje_creada_) {
    Colocar();
    return true;
  }

  if (message == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED) {
    if (!al_pulsar_) {
      return true;
    }
    switch (LOWORD(wparam)) {
      case kBotonAnterior:
        al_pulsar_(ComandoMultimedia::kPrevious);
        return true;
      case kBotonPlayPause:
        al_pulsar_(ComandoMultimedia::kPlayPause);
        return true;
      case kBotonSiguiente:
        al_pulsar_(ComandoMultimedia::kNext);
        return true;
      default:
        return false;
    }
  }

  if (message == WM_SETTINGCHANGE && lparam != 0 &&
      ::CompareStringOrdinal(reinterpret_cast<LPCWSTR>(lparam), -1,
                             L"ImmersiveColorSet", -1, TRUE) == CSTR_EQUAL) {
    RehacerIconos();
    return false;
  }

  if (message == WM_DPICHANGED) {
    RehacerIconos();
    return false;
  }

  return false;
}

void ThumbBar::Colocar() {
  if (window_ == nullptr) {
    return;
  }
  if (taskbar_ != nullptr) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  colocados_ = false;

  HRESULT hr = ::CoCreateInstance(__uuidof(TaskbarList), nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar_));
  if (FAILED(hr) || taskbar_ == nullptr) {
    taskbar_ = nullptr;
    return;
  }
  if (FAILED(taskbar_->HrInit())) {
    taskbar_->Release();
    taskbar_ = nullptr;
    return;
  }

  RehacerIconos();

  THUMBBUTTON botones[3] = {};
  RellenarBotones(botones);
  if (SUCCEEDED(taskbar_->ThumbBarAddButtons(window_, 3, botones)) ||
      SUCCEEDED(taskbar_->ThumbBarUpdateButtons(window_, 3, botones))) {
    colocados_ = true;
  }
}

void ThumbBar::Refrescar() {
  if (taskbar_ == nullptr || !colocados_) {
    return;
  }
  THUMBBUTTON botones[3] = {};
  RellenarBotones(botones);
  taskbar_->ThumbBarUpdateButtons(window_, 3, botones);

  if (estado_.hay_cancion) {
    std::wstring texto = estado_.titulo;
    if (!estado_.artista.empty()) {
      texto += L" — ";
      texto += estado_.artista;
    }
    taskbar_->SetThumbnailTooltip(window_, texto.c_str());
  } else {
    taskbar_->SetThumbnailTooltip(window_, nullptr);
  }
}

void ThumbBar::RellenarBotones(THUMBBUTTON (&botones)[3]) const {
  const bool sonando = estado_.hay_cancion && estado_.sonando;

  botones[0].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  botones[0].iId = kBotonAnterior;
  botones[0].hIcon = anterior_;
  ::wcscpy_s(botones[0].szTip, L"Anterior");
  botones[0].dwFlags = estado_.puede_volver ? THBF_ENABLED : THBF_DISABLED;

  botones[1].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  botones[1].iId = kBotonPlayPause;
  botones[1].hIcon = sonando ? pausar_ : reproducir_;
  ::wcscpy_s(botones[1].szTip, sonando ? L"Pausar" : L"Reproducir");
  botones[1].dwFlags = estado_.hay_cancion ? THBF_ENABLED : THBF_DISABLED;

  botones[2].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
  botones[2].iId = kBotonSiguiente;
  botones[2].hIcon = siguiente_;
  ::wcscpy_s(botones[2].szTip, L"Siguiente");
  botones[2].dwFlags = estado_.puede_saltar ? THBF_ENABLED : THBF_DISABLED;
}

void ThumbBar::RehacerIconos() {
  const int lado = LadoDelIcono();
  const bool claro = TemaClaro();
  if (lado == lado_ && claro == tema_claro_ && anterior_ != nullptr) {
    return;
  }

  HICON viejos[4] = {anterior_, reproducir_, pausar_, siguiente_};

  lado_ = lado;
  tema_claro_ = claro;
  const COLORREF tinta = claro ? RGB(32, 32, 32) : RGB(255, 255, 255);
  anterior_ = DibujarIcono(lado, kFiguraAnterior, tinta);
  reproducir_ = DibujarIcono(lado, kFiguraPlay, tinta);
  pausar_ = DibujarIcono(lado, kFiguraPausa, tinta);
  siguiente_ = DibujarIcono(lado, kFiguraSiguiente, tinta);

  Refrescar();

  for (HICON icono : viejos) {
    if (icono != nullptr) {
      ::DestroyIcon(icono);
    }
  }
}

void ThumbBar::SoltarIconos() {
  for (HICON* icono : {&anterior_, &reproducir_, &pausar_, &siguiente_}) {
    if (*icono != nullptr) {
      ::DestroyIcon(*icono);
      *icono = nullptr;
    }
  }
  lado_ = 0;
}
