## Features

- Nueva interfaz **NeoFy Nocturno** con barra superior de búsqueda, cabecera de colecciones, panel de cola y vista de podcasts.
- Letras sincronizadas en directo con resaltado por letras o por palabras, ajuste manual de desfase por canción y sincronización adaptativa mediante detección de voz.
- Mejoras en la reproducción por contexto desde biblioteca, listas y perfiles.

## Fixes

- Eliminadas fugas de memoria nativa (COM y buffers en la detección de voz), clientes HTTP sin cerrar, animaciones recreadas en `build()` y crecimiento sin límite en las cachés de traducciones y coincidencias de YouTube.
- Reducido el consumo de RAM y CPU pausando el monitor de recursos al ocultar la ventana, descargando el actualizador en streaming a disco, cacheando temas y evitando reconstrucciones innecesarias en letras, barra de reproducción, onda de progreso y panel lateral.
- Corregida la persistencia del volumen en modo libre, el cierre del WebView al vencer el inicio de sesión de YouTube y la estabilidad de la caché de biografías entre sesiones.
