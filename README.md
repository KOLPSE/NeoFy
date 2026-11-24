<p align="center">
  <img src="assets/neofy.png" width="128" alt="NeoFy">
</p>

<h1 align="center">NeoFy</h1>

<p align="center">
  Cliente de Spotify nativo para Windows y Linux hecho con Flutter y <code>librespot</code>.<br>
  En torno a <b>150 MB</b> de RAM en uso normal, o por debajo de <b>100 MB</b> en modo rendimiento.
</p>

---

> Proyecto independiente sin afiliación con Spotify AB. Usa la Web API pública de Spotify.
>
> Con **Spotify Premium** reproduce mediante Spotify Connect. **Sin Premium** también funciona:
> como la Web API exige Premium para controlar la reproducción, el audio se obtiene desde
> YouTube Music mientras la biblioteca, listas, búsquedas y carátulas siguen viniendo de tu
> cuenta de Spotify.

## Cómo funciona

Spotify solo permite reproducir audio en aplicaciones de terceros mediante un SDK basado en
navegador embebido. Para evitar ese consumo de memoria, NeoFy separa el audio del control:

- **Audio (Premium)**: [`librespot`](https://github.com/librespot-org/librespot) implementa
  el protocolo abierto de Spotify Connect y registra el equipo como un dispositivo llamado
  `NeoFy`.
- **Interfaz y control**: la Web API oficial con OAuth PKCE gestiona biblioteca, búsqueda,
  playlists y reproducción sobre ese dispositivo (compatible también con Stream Deck o
  cualquier cliente que use la API de Spotify).
- **Audio alternativo (sin Premium)**: `yt-dlp` y `libmpv` (`media_kit`) reproducen el audio
  equivalente desde YouTube Music manteniendo tu catálogo de Spotify.

## Funciones

- **Portada y catálogo**: inicio con historial reciente, temas más escuchados y artistas,
  biblioteca, «Canciones que te gustan», búsqueda paginada, álbumes, pódcasts y cola de
  reproducción.
- **Playlists y carpetas**: creación, edición, seguimiento y organización en carpetas.
- **Reproducción**: aleatorio inteligente y reanudación de la última pista al abrir la app.
- **Letras sincronizadas**: resaltado por líneas o por palabras, ajuste manual de desfase por
  canción y sincronización adaptativa mediante detección de voz.
- **Temas**: cinco temas integrados (`NeoFy Nocturno`, `NeoFy Claro`, `Liquid Glass`,
  `Material claro` y `Material oscuro`), modo **Automático** según el tema del sistema,
  personalización de paleta en los temas Material y soporte para temas de usuario en texto
  que se recargan al guardar ([`TEMAS.md`](TEMAS.md)).
- **Modo rendimiento**: sustituye las carátulas por mosaicos de color generados y reduce el
  uso de RAM por debajo de 100 MB sin afectar al audio.
- **Integración con el escritorio**: teclas multimedia globales, bandeja del sistema, SMTC en
  Windows, MPRIS en Linux y Discord Rich Presence opcional.
- **Idioma y reportes**: traducción de la interfaz al idioma configurado y envío opcional de
  incidencias desde Ajustes con [NeoReport](https://report.neogex.xyz).
- **Actualizaciones**: en Windows comprueba y descarga las nuevas versiones desde
  [`git.neogex.xyz/apps/neofy`](https://git.neogex.xyz/apps/neofy/-/releases) en un clic
  desde Ajustes, conservando sesión y ajustes, y permite cambiar en cualquier momento al
  canal **Preview** ([`git.neogex.xyz/apps/neofy-preview`](https://git.neogex.xyz/apps/neofy-preview/-/releases)).
  En Linux avisa de la nueva versión para actualizar el paquete.

## Instalación

### Windows

Descarga el instalador (`NeoFy-x.y.z-windows-x64.exe`) desde la sección
[Releases](https://git.neogex.xyz/apps/neofy/-/releases). Incluye la aplicación,
`librespot`, `metadata-sidecar` y `yt-dlp`, y se instala por usuario sin permisos de
administrador.

### Linux

La distribución soportada oficialmente en Linux es **Arch** (y derivadas como Manjaro o
EndeavourOS). Para otras distribuciones se puede [compilar desde el código](#compilar-desde-el-código).

El paquete instala NeoFy en `/opt/neofy`, la entrada del menú de aplicaciones y el comando
`neofy` en el `PATH`.

- **Paquete Arch (`.pkg.tar.zst`)**: descarga la última versión en
  [Releases](https://git.neogex.xyz/apps/neofy/-/releases) e instálala con:
  ```bash
  sudo pacman -U NeoFy-*.pkg.tar.zst   # sustituye por neofy-bin-x.y.z-1-x86_64.pkg.tar.zst
  ```
- **AppImage y binario portable (`.AppImage` / `.tar.gz`)**: disponibles en cada release para
  ejecutar sin instalar paquete.
- **Compilando el paquete con `PKGBUILD`**:
  ```bash
  git clone https://git.neogex.xyz/apps/neofy && cd neofy/linux/packaging
  makepkg -si
  ```

> En **GNOME** hace falta la extensión de AppIndicator para ver el icono en la bandeja. Sin
> bandeja disponible, cerrar la ventana cierra la aplicación.

### Configuración inicial (una sola vez)

El Modo Desarrollo de Spotify limita cada aplicación a 25 usuarios autorizados por su creador,
por lo que cada usuario crea su propio Client ID gratuito (en Windows se pide en el instalador
y en Linux al iniciar la aplicación por primera vez):

1. Entra en [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard), crea
   una aplicación y marca **Web API**.
2. Añade exactamente este **Redirect URI** (Spotify exige `127.0.0.1` literal, sin `localhost`
   ni barra final):
   ```
   http://127.0.0.1:8898/callback
   ```
3. Copia el **Client ID** en el instalador o en la pantalla inicial de NeoFy.

Para instalaciones desatendidas en Windows:
`NeoFy-x.y.z-windows-x64.exe /SILENT /CLIENTID=tu-id`.

La primera conexión abre el navegador dos veces (una para OAuth de la Web API y otra para el
inicio de sesión de `librespot`) y ambos tokens quedan guardados localmente.

## Limitaciones de la API de Spotify

| Limitación | Detalle |
|---|---|
| Cuenta **Premium** para Spotify Connect | La API exige Premium para el control nativo. Sin Premium se reproduce el audio mediante YouTube Music iniciando sesión con Google. |
| Playlists ajenas | La Web API devuelve 403 al leer sus pistas; NeoFy las resuelve mediante `metadata-sidecar` sobre `librespot`. |
| Búsqueda paginada de 10 en 10 | Se amplía con «Ver más». |
| Sin Daily Mix ni Radar de novedades | Spotify no expone las listas personalizadas por usuario en la Web API. |
| Cuota diaria | Si se alcanza el límite de peticiones (`429`), NeoFy detiene los reintentos y muestra la hora de recuperación. |

## Compilar desde el código

### Windows

Requiere Flutter, Rust/Cargo, Inno Setup 6 y Visual Studio con el componente ATL de C++ (para
`flutter_secure_storage_windows`):

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_librespot.ps1   # sidecars, primera vez
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
```

### Linux

Dependencias en Arch:

```bash
sudo pacman -S --needed base-devel clang cmake ninja pkgconf \
                        gtk3 libayatana-appindicator libpulse openssl rust \
                        webkit2gtk-4.1 mpv libsecret
```

En Debian/Ubuntu usa los equivalentes `-dev` (`clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev libpulse-dev libssl-dev libwebkit2gtk-4.1-dev libsecret-1-dev libmpv-dev`).

```bash
./tool/build_sidecars.sh        # sidecars, primera vez
flutter build linux --release
./tool/build_linux_bundle.sh    # genera dist/NeoFy-x.y.z-linux-x86_64.tar.gz
```

`libayatana-appindicator` y `webkit2gtk-4.1` son necesarios al compilar. `libmpv` se carga en
tiempo de ejecución con `dlopen` y es imprescindible para la reproducción vía YouTube Music.

Si compilas un instalador con soporte de NeoReport, define `NEOREPORT_APP_KEY` mediante
`--dart-define` o `.neoreport-key.json` (archivo local ignorado en Git).

```bash
flutter analyze
flutter test
```

Los detalles técnicos y trampas verificadas de la API están documentados en
[`ARQUITECTURA.md`](ARQUITECTURA.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
