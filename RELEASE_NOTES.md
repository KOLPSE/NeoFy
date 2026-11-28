## Features

- Simplificada la selección de temas a **Automático**, **NeoFy Claro** y **NeoFy Nocturno** directamente desde **Ajustes → Apariencia e idioma**, retirando los temas heredados y el selector complejo.
- Añadida navegación con los **botones laterales del ratón** (Atrás y Adelante), con el mismo comportamiento que los botones de la barra superior.
- Sustituido el botón de favorito en perfiles, búsqueda y panel derecho por un botón **Seguir / Siguiendo** sincronizado con tu cuenta de Spotify (`user-follow-read` / `user-follow-modify`) y renombrada la sección lateral a **Artistas seguidos**.
- Añadido redimensionamiento mediante arrastre en los bordes de ambos sidebars (izquierdo y derecho) cuando están expandidos, con persistencia en configuración y doble clic para restablecer el tamaño por defecto.

## Fixes

- Corregido el error al seguir o dejar de seguir artistas migrando la escritura a `/v1/me/library` con URIs completas de Spotify (`spotify:artist:...`) y el permiso `user-library-modify`.
- Revisadas y corregidas las traducciones de la interfaz para usar terminología natural de música y aplicación en lugar de traducciones literales.
- Reemplazado el botón de compartir enlace de canción en el panel de Reproducción Actual por un botón directo de copiar enlace con animación de confirmación y retorno automático al icono inicial, evitando recortes visuales.
- Corregida la carga del avatar de artistas al seguirlos desde cualquier vista para que aparezca al instante sin necesidad de reiniciar la aplicación.
