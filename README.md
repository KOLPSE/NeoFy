<p align="center">
  <img src="assets/neofy.png" width="128" alt="NeoFy">
</p>

<h1 align="center">NeoFy</h1>

<p align="center">
  Un cliente de Spotify ligero y nativo para Windows.<br>
  <b>~150 MB</b> de memoria — o <b>menos de 100</b> en modo rendimiento — frente a los
  400-700 MB del cliente oficial.
</p>

---

> **Aviso.** NeoFy no está afiliado ni patrocinado por Spotify AB. Es un proyecto
> independiente que usa la Web API pública de Spotify. **Necesita una cuenta Spotify
> Premium**: es la propia API la que lo exige para controlar la reproducción.

## Qué es

Spotify no permite que una app de terceros reproduzca audio por su API oficial: solo lo
permite con un SDK que exige un navegador embebido, que es justo el peso que NeoFy existe
para evitar. De ahí que se parta en dos mitades:

- **El audio** lo lleva [`librespot`](https://github.com/librespot-org/librespot), que
  implementa el protocolo abierto de Spotify Connect y convierte el equipo en un dispositivo
  llamado `NeoFy`.
- **Todo lo demás** —biblioteca, búsqueda, playlists y el control de la reproducción— va por
  la Web API oficial con OAuth PKCE, apuntando a ese dispositivo.

Un efecto secundario aprovechado: como el control va por la Web API, **un Stream Deck que
use la API de Spotify controla NeoFy sin plugin ninguno**.

## Funciones

- Biblioteca, playlists, búsqueda y cola, con scroll infinito.
- Portada con tu historial reciente, lo que más escuchas y tus artistas.
- Botón de "me gusta" en cada canción.
- Crear y quitar playlists.
- **Teclas multimedia globales**: el botón de play/pausa de unos cascos funciona aunque
  NeoFy esté en la bandeja. Barra espaciadora dentro de la app.
- **Modo rendimiento**: sustituye las carátulas por mosaicos de color generados y baja el
  consumo por debajo de 100 MB, sin tocar el audio.
- Bandeja del sistema: cerrar la ventana no corta la música.
- **Se actualiza sola**: comprueba las releases de GitHub y se actualiza en un clic desde
  Ajustes, sin perder la sesión ni la configuración.

## Instalación

Descarga el instalador de la sección [Releases](../../releases). Trae los tres binarios
dentro (interfaz, audio y metadatos), no pide permisos de administrador y ocupa 14 MB.

### Configuración inicial (una sola vez)

Spotify solo deja que una app de terceros funcione para los usuarios que su creador da de
alta a mano — **25 como máximo** —, así que NeoFy no puede traer una configurada: necesitas
crear la tuya. Es gratis y **el instalador te lo pide en una casilla**, así que no hay que
editar ningún fichero.

1. Entra en [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) y
   crea una app. Marca **Web API**.
2. En **Redirect URI** pon exactamente esto:
   ```
   http://127.0.0.1:8898/callback
   ```
   Ojo: Spotify ya no acepta `localhost`, solo el `127.0.0.1` literal, y sin barra final.
3. Copia el **Client ID** y pégalo en la casilla del instalador. Si lo dejaste en blanco o
   compilaste desde el código, la propia app te lo pide al abrirla.

Para instalaciones desatendidas: `NeoFy-x.y.z-windows-x64.exe /SILENT /CLIENTID=tu-id`.

> **La primera vez se abrirá el navegador dos veces y es correcto.** Son dos flujos OAuth
> distintos: el de la Web API y el de librespot, que usa el client_id del cliente de
> escritorio de Spotify y no puede compartir token. Los dos quedan cacheados.

## Limitaciones conocidas

Vienen del Modo Desarrollo de la API de Spotify, no del código:

| Limitación | Detalle |
|---|---|
| Cuenta **Premium** obligatoria | La API la exige para todo el control de reproducción. |
| Playlists ajenas | La Web API devuelve 403 al leer sus canciones. NeoFy las lee por librespot con un sidecar; se pueden reproducir enteras igualmente. |
| Búsqueda capada a 10 resultados | Se pagina con "ver más". |
| Sin Daily Mix ni Radar de novedades | Spotify no expone por API las listas que genera para cada usuario. |
| Cuota diaria | Si se agota, la API responde 429 durante unas horas. NeoFy lo detecta, deja de insistir y te dice a qué hora vuelve. |

## Compilar desde el código

```powershell
# Los sidecars, una sola vez (necesita Rust; tarda un rato)
powershell -ExecutionPolicy Bypass -File tool\build_librespot.ps1

# La app
flutter build windows --release

# O todo junto y empaquetado (necesita Inno Setup 6)
powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
```

```powershell
flutter analyze
flutter test
```

La arquitectura y las trampas de la API están documentadas en
[`ARQUITECTURA.md`](ARQUITECTURA.md) — incluidos varios endpoints que cambiaron de nombre y cuyo
comportamiento real está verificado con las sondas de `tool/`.

## Licencia

MIT. Ver [LICENSE](LICENSE), que incluye además los avisos de terceros.
