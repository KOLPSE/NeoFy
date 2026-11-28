## Features

- Añadido el panel lateral derecho de **Reproducción Actual**, plegable y con acceso directo a la pista, letras, cola y detalles del artista.
- Optimizado el consumo de RAM y CPU en reposo, bandeja del sistema y procesos sidecar, mejorando el modo rendimiento.
- Simplificada la selección de temas a **Automático**, **NeoFy Claro** y **NeoFy Nocturno** directamente desde **Ajustes → Apariencia e idioma**, retirando los temas heredados y el selector complejo.
- Añadido redimensionamiento mediante arrastre en los bordes de ambos sidebars (izquierdo y derecho) cuando están expandidos, con persistencia en configuración y doble clic para restablecer el tamaño por defecto.
- Sustituido el botón de favorito en perfiles, búsqueda y panel derecho por un botón **Seguir / Siguiendo** sincronizado con tu cuenta de Spotify (`user-follow-read` / `user-follow-modify`) y renombrada la sección lateral a **Artistas seguidos**.
- Añadida navegación con los **botones laterales del ratón** (Atrás y Adelante), con el mismo comportamiento que los botones de la barra superior.

## Fixes

- Corregido el error al seguir o dejar de seguir artistas migrando la escritura a `/v1/me/library` con URIs completas de Spotify (`spotify:artist:...`) y el permiso `user-library-modify`.
- Corregida la carga del avatar de artistas al seguirlos desde cualquier vista para que aparezca al instante sin necesidad de reiniciar la aplicación.
- Corregido el plegado y desplegado del panel lateral derecho de Reproducción Actual.
- Reemplazado el botón de compartir enlace de canción en el panel de Reproducción Actual por un botón directo de copiar enlace con animación de confirmación y retorno automático al icono inicial.
- Revisadas y corregidas las traducciones de la interfaz para usar terminología natural de música y aplicación en lugar de traducciones literales.
- Eliminado el logotipo antiguo y actualizados los enlaces de Discord RPC para apuntar al repositorio público en GitLab (`git.neogex.xyz`).
