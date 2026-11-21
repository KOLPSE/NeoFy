## Features

- Nueva interfaz **NeoFy Nocturno** con barra superior de búsqueda, cabecera de colecciones, panel de cola y vista de podcasts.
- Nuevo tema **NeoFy Claro**, con la misma arquitectura visual que NeoFy Nocturno (paneles flotantes blancos sobre fondo piedra suave y acentos verdes de alto contraste).
- El modo **Automático** del sistema alterna entre **NeoFy Claro** y **NeoFy Nocturno** manteniendo la misma interfaz al cambiar el tema del escritorio.
- Letras sincronizadas en directo con resaltado por líneas o por palabras, ajuste manual de desfase por canción y sincronización adaptativa mediante detección de voz.
- Mejoras en la reproducción por contexto desde biblioteca, listas y perfiles.

## Fixes

- Corregido el orden de reproducción en «Canciones que te gustan» y listas: se usa el contexto nativo con `offsetUri` y, cuando Spotify rechaza una lista de URIs y cae al álbum de respaldo, los controles Siguiente/Anterior y el avance automático siguen recorriendo la lista original en orden.
- Mejorada la detección de voz en la sincronización adaptativa de letras mediante análisis estéreo Mid/Side (foco central), filtrado de banda vocal (280–2800 Hz frente a graves y agudos), periodicidad armónica por autocorrelación y piso adaptativo instrumental para evitar falsos positivos con instrumentos y percusión.
- Eliminadas fugas de memoria nativa, clientes HTTP sin cerrar, animaciones recreadas en `build()` y crecimiento sin límite en cachés de traducciones.
- Reducido el consumo de RAM y CPU pausando el monitor de recursos al ocultar la ventana, descargando el actualizador en streaming a disco, cacheando temas y evitando reconstrucciones innecesarias en la interfaz.
- Corregida la estabilidad de la caché de biografías entre sesiones y el pipeline de compilación y publicación automática.
