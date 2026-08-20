#ifndef RUNNER_THUMB_BAR_H_
#define RUNNER_THUMB_BAR_H_

#include <shobjidl.h>
#include <windows.h>

#include <functional>

#include "media_status.h"

class ThumbBar {
 public:
  using Callback = std::function<void(ComandoMultimedia)>;

  ThumbBar() = default;
  ~ThumbBar();

  ThumbBar(const ThumbBar&) = delete;
  ThumbBar& operator=(const ThumbBar&) = delete;

  void Start(HWND window, Callback al_pulsar);
  void Stop();

  void Update(const EstadoMultimedia& estado);

  bool MessageHandler(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void Colocar();

  void Refrescar();

  void RellenarBotones(THUMBBUTTON (&botones)[3]) const;

  void RehacerIconos();
  void SoltarIconos();

  HWND window_ = nullptr;
  Callback al_pulsar_;

  ITaskbarList3* taskbar_ = nullptr;

  UINT mensaje_creada_ = 0;
  bool colocados_ = false;

  int lado_ = 0;
  bool tema_claro_ = false;
  HICON anterior_ = nullptr;
  HICON reproducir_ = nullptr;
  HICON pausar_ = nullptr;
  HICON siguiente_ = nullptr;

  EstadoMultimedia estado_;
};

#endif
