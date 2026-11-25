## Features

- Actualizado el enlace y el texto del botón de Discord Rich Presence para apuntar al repositorio oficial en GitLab (`git.neogex.xyz/apps/neofy`).
- Menos trabajo en segundo plano al minimizar NeoFy o dejarlo en la bandeja. Se suspenden animaciones y se reduce la actividad de los temporizadores de reproducción.
- El proceso auxiliar de metadatos arranca bajo demanda y se cierra tras un periodo de inactividad. Las cachés de listas y portadas tienen límites.
- Favoritos carga al inicio solo los identificadores y recupera las pistas cuando hacen falta.

- Añadido selector de rama de actualizaciones (**Estable** y **Preview**) en Ajustes para alternar en cualquier momento entre versiones estables (`apps/neofy`) y versiones de prueba (`apps/neofy-preview`).
- Identificación dinámica de ventana y bandeja como **NeoFy (PREVIEW)** cuando la aplicación usa la rama Preview o una compilación preview (`X.Y.Z.1XX`).
- Soporte en el actualizador y en el pipeline de GitLab para versiones preview con sufijo de 3 cifras (`vX.Y.Z.1XX`) y regreso controlado a Estable.

## Fixes

- Eliminado el archivo residual del logo antiguo (`assets/neofy-original.png`) y asegurado el icono actualizado en el acceso directo del desinstalador de Windows.
- Favoritos vuelve a mostrar sus pistas al restaurar la ventana y conserva su caché si se minimiza durante un guardado.
- Discord vuelve a conectar tras una caída y espacia los reintentos cuando está cerrado.
- NeoTube muestra el aviso de instalación de libmpv cuando falta la biblioteca.

- Evitadas condiciones de carrera al cambiar de rama durante una búsqueda de actualizaciones en curso.
- Corregida la sincronización dinámica del título de la ventana en Linux con barra de cabecera GTK (`GtkHeaderBar`).
- Endurecida la creación de temporales en la publicación de releases de GitLab usando `mktemp`.
