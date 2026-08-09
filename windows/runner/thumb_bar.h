#ifndef RUNNER_THUMB_BAR_H_
#define RUNNER_THUMB_BAR_H_

#include <shobjidl.h>
#include <windows.h>

#include <functional>

#include "media_status.h"

// Los botones que Windows enseña bajo la miniatura de la barra de tareas: el
// "minireproductor" que sale al dejar el ratón sobre el icono de la app.
//
// Va por `ITaskbarList3`, que es COM puro y solo existe en C++: desde Dart no
// hay forma de llegar ahí. Tres detalles que no son obvios y que están
// resueltos aquí:
//
//  - **Los botones solo se pueden añadir cuando existe el botón de la barra de
//    tareas**, y de eso avisa el mensaje registrado `TaskbarButtonCreated`.
//    Llamar antes no falla: no hace nada, que es peor, porque no hay síntoma.
//  - **`ThumbBarAddButtons` es de una sola vez por ventana.** A partir de ahí
//    los cambios (play↔pausa, habilitar o no el salto) van por
//    `ThumbBarUpdateButtons`. La excepción es que Explorer se reinicie: manda
//    otra vez `TaskbarButtonCreated` y hay que empezar de cero, porque el
//    objeto de la barra anterior murió con él.
//  - **Los iconos se dibujan a mano** en vez de venir de un `.ico`. Así salen a
//    la resolución que pida el sistema y del color que toque según el tema
//    claro u oscuro, que es la diferencia entre verlos y no verlos.
class ThumbBar {
 public:
  using Callback = std::function<void(ComandoMultimedia)>;

  ThumbBar() = default;
  ~ThumbBar();

  ThumbBar(const ThumbBar&) = delete;
  ThumbBar& operator=(const ThumbBar&) = delete;

  // Se queda esperando a que la barra de tareas cree el botón de la ventana.
  // No falla nunca de forma visible: sin miniatura, la app funciona igual.
  void Start(HWND window, Callback al_pulsar);
  void Stop();

  // Lo que hay que enseñar. Se puede llamar tantas veces como haga falta.
  void Update(const EstadoMultimedia& estado);

  // Devuelve true si el mensaje era suyo y no hay que seguir procesándolo.
  bool MessageHandler(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  // (Re)crea la barra y coloca los tres botones. Solo desde
  // `TaskbarButtonCreated`.
  void Colocar();

  // Vuelve a mandar el estado de los botones ya colocados.
  void Refrescar();

  void RellenarBotones(THUMBBUTTON (&botones)[3]) const;

  // Rehace los iconos si han cambiado el tamaño o el tema. Es barato dejarla
  // llamada de más: si no ha cambiado nada, no hace ninguna.
  void RehacerIconos();
  void SoltarIconos();

  HWND window_ = nullptr;
  Callback al_pulsar_;

  ITaskbarList3* taskbar_ = nullptr;

  // El mensaje que la barra de tareas difunde al crear el botón de la ventana.
  // Es un mensaje registrado: su número lo asigna el sistema en tiempo de
  // ejecución y no se puede comparar con una constante.
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

#endif  // RUNNER_THUMB_BAR_H_
