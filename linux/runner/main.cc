#include <stdlib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // La WebView del login de YouTube (WebKitGTK) intenta composición acelerada
  // al crearse. Donde no hay contexto OpenGL utilizable, eso falla con
  // "Failed to setup compositor shaders, unable to make OpenGL context
  // current" y la ventana sale **completamente en blanco**: WebKit arranca
  // bien -sus procesos WebKitWebProcess y WebKitNetworkProcess siguen vivos-,
  // solo que no pinta nada. Como no hay ningún error que llegue a la app, el
  // usuario ve un login vacío sin explicación y lo único que puede hacer es
  // cerrarlo.
  //
  // Verificado en Ubuntu 24.04 con GNOME: sin esto, la ventana sale en blanco;
  // con esto, el login entra y las cookies se capturan (18, con SAPISID entre
  // ellas, comprobadas contra la API real con tool/probe_yt.dart).
  //
  // Va aquí y no en Dart porque WebKit lee la variable **al inicializarse**,
  // que es antes de que exista ningún código nuestro de Flutter.
  //
  // El 0 final es un `overwrite` a falso: si el usuario ya la trae puesta en
  // su entorno, se respeta su valor. Renunciar a la composición acelerada no
  // cuesta nada aquí, porque la WebView existe **solo** para la pantalla de
  // login y no se vuelve a abrir en toda la sesión.
  setenv("WEBKIT_DISABLE_COMPOSITING_MODE", "1", 0);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
