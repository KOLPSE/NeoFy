## Features

- Añadido sidebar derecho de **Reproducción Actual** en dos modos (compacto y expandido `↗↙`) y estado plegado minimalista (`<`) con extensión sutil al pasar el ratón.
- Cabecera contextual (`HEAD`) clicable con el nombre de la playlist actual o `Canciones que te gustan`, botón para plegar a la derecha y menú completo de acciones reales (`...`) con añadir a lista, favoritos, cola, temporizador de apagado real, radio de la canción, ir al artista/álbum, ver créditos y compartir.
- Tarjetas en tiempo real con arte de la canción (Canvas o animación sutil sobre portada), botón de compartir entre título y corazón, vista previa de letras desplegable inline (compartida con `LetrasService`), información del artista (verificado, oyentes mensuales, seguir y descripción), créditos en formato inclusivo (`Compositor/A`, `Productor/A`), próximos conciertos (`De gira`) y siguiente canción con acceso integrado a la cola.
- Ampliado `metadata-sidecar` (Rust) con los endpoints `/track/{id}/credits`, `/artist/{id}/insights` y `/track/{id}/canvas` con caché acotada en memoria.

## Fixes

- Unificado el panel de Cola dentro del sidebar derecho con retorno directo a Reproducción Actual.
- Compartida la descarga y caché de letras de LRCLIB entre la vista completa y la vista previa lateral mediante `LetrasService`.
