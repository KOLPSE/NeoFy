## Fixes

- **Portada vacía en Inicio.** Cuando Spotify devolvía vacío el rango corto (`short_term`), la portada se quedaba en «Todavía no hay historial que enseñar» aunque sí hubiera datos a medio y largo plazo. Ahora prueba esos rangos en cascada y vuelve a mostrar lo más escuchado, tus artistas y «Hecho para ti».
- **Tras reautorizar.** Si faltaban permisos de historial o top, al volver a iniciar sesión la pantalla no recargaba y el hueco vacío se quedaba para siempre. Tras concederlos, Inicio vuelve a pedir los datos solo.
- **Historial sin contenido.** Un `204` de recently-played ya no tumba toda la portada con un error ilegible: se trata como lista vacía y el resto de secciones sigue cargando.
