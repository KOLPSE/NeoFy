## Features

- Añadido selector de rama de actualizaciones (**Estable** y **Preview**) en Ajustes para alternar en cualquier momento entre versiones estables (`apps/neofy`) y versiones de prueba (`apps/neofy-preview`).
- Identificación dinámica de ventana y bandeja como **NeoFy (PREVIEW)** cuando la aplicación usa la rama Preview o una compilación preview (`X.Y.Z.1XX`).
- Soporte en el actualizador y en el pipeline de GitLab para versiones preview con sufijo de 3 cifras (`vX.Y.Z.1XX`) y regreso controlado a Estable.

## Fixes

- Evitadas condiciones de carrera al cambiar de rama durante una búsqueda de actualizaciones en curso.
- Corregida la sincronización dinámica del título de la ventana en Linux con barra de cabecera GTK (`GtkHeaderBar`).
- Endurecida la creación de temporales en la publicación de releases de GitLab usando `mktemp`.
