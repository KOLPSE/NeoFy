## Features

- Migrado el sistema de actualizaciones y descargas a [git.neogex.xyz/apps/neofy](https://git.neogex.xyz/apps/neofy). Esta versión **1.5.10 es la última publicada en GitHub**: al actualizar a `v1.5.10`, NeoFy comprobará y descargará las próximas versiones directamente desde GitLab.
- Nuevo logotipo e icono oficial aplicado en el icono de aplicación y ventana de Windows (`app_icon.ico`), bandeja del sistema (`tray.ico` y `tray.png`), iconos y ventana GTK en Linux (`neofy.png` y `AppImage`), pantalla de inicio, cabecera y barra lateral expandida o contraída.

## Fixes

- Actualizador adaptado a la API de Releases y paquetes genéricos de GitLab (`apps%2Fneofy/releases/permalink/latest`), con validación estricta de host HTTPS (`git.neogex.xyz`) y rechazo de respuestas `text/html`.
- Actualizados `PKGBUILD`, `tool/probe_update.dart`, el texto de actualización de Linux y la documentación del proyecto para apuntar a `git.neogex.xyz/apps/neofy`.
- Añadidos tests unitarios para la consulta de última versión, validación de descargas y rechazo de respuestas HTML.
