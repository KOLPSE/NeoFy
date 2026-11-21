## Features

- Nuevo tema **NeoFy Claro**, con la misma arquitectura visual que NeoFy Nocturno (paneles flotantes blancos sobre fondo piedra suave, acentos verdes, barra superior de búsqueda, cabecera de colecciones y panel de cola).
- El modo **Automático** del sistema alterna ahora entre NeoFy Claro y NeoFy Nocturno manteniendo la misma interfaz al cambiar el tema del escritorio.

## Fixes

- Corregido el orden de reproducción en «Canciones que te gustan» y listas: se usa el contexto nativo con `offsetUri` y, cuando Spotify rechaza una lista de URIs y cae al álbum de respaldo, los controles Siguiente/Anterior y el avance automático siguen recorriendo la lista original en orden.
- Mejorada la detección de voz en la sincronización adaptativa de letras mediante análisis estéreo Mid/Side (foco central), filtrado de banda vocal (280–2800 Hz frente a graves y agudos), periodicidad armónica por autocorrelación y piso adaptativo instrumental para evitar falsos positivos con instrumentos y percusión.
