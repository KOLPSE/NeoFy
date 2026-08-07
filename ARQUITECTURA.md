# Arquitectura de NeoFy

Cómo está montado el proyecto, y **por qué** está montado así. La mayor parte de este
documento son trampas de la API de Spotify verificadas contra la API real con las sondas de
`tool/`: si algo aquí parece una decisión rara, suele ser que la alternativa obvia no
funciona.

**neofy** es un cliente de Spotify ligero para Windows y Linux, parte del ecosistema Neo*.
Flutter + Material 3 (mismo stack que `NeoDrive`) con `librespot` como sidecar de audio.
La documentación del proyecto está en español; escribe en español.

## La restricción que explica toda la arquitectura

Spotify **no permite** que una app de terceros reproduzca audio por su API oficial: solo lo
permite con un SDK que exige un navegador embebido, que es justo el peso que esta app
existe para evitar. De ahí que se parta en dos mitades:

- **Audio** → `librespot` (Rust, protocolo Spotify Connect abierto) como proceso hijo.
  Convierte el equipo en un dispositivo Connect llamado `NeoFy`.
- **Todo lo demás** → Web API oficial con OAuth PKCE: biblioteca, búsqueda, playlists y el
  control de reproducción, apuntando al `device_id` de librespot.

Efecto secundario aprovechado: como el control va por la Web API, **un Stream Deck que use
la API de Spotify controla esta app sin plugin ninguno**. Por eso el sondeo del estado no
es opcional — es lo que mantiene la interfaz sincronizada cuando el mando actúa por fuera.

## Estructura

- **`lib/core/`** — Sin Flutter salvo `ChangeNotifier`:
  - `app_config.dart` — Client ID, puertos, scopes, `%APPDATA%\neofy`.
  - `auth.dart` — OAuth PKCE: verifier/challenge S256, `HttpServer` de loopback, refresco.
  - `spotify_api.dart` — Cliente HTTP. Punto único `_request()` con auth, reintento en 401
    y respeto de `Retry-After` en 429.
  - `player_state.dart` — Sondeo adaptativo + interpolación local del progreso.
  - `librespot.dart` — Arranque, vigilancia y muerte del sidecar; resolución del `device_id`.
  - `metadata_sidecar.dart` — Cliente y supervisor de `metadata-sidecar.exe`.
  - `liked_store.dart` — Qué canciones están en favoritos **y la biblioteca entera**, en un
    único sitio para toda la app. Agrupa las consultas de las filas visibles en lotes de 50
    cada 120 ms.
  - `home_store.dart` — Datos de la portada (historial y lo más escuchado).
  - `media_keys.dart` — Recibe las teclas multimedia que registra el runner.
  - `audio_device.dart` — Recibe del runner los cambios de la salida de audio de
    Windows. Ver "El audio que se queda mudo" más abajo.
  - `art_cache.dart` — Caché LRU de carátulas en disco (50 MB).
  - `models.dart` — Modelos mínimos. `pickImage()` es RAM-crítica.
- **`windows/runner/flutter_window.cpp`** — Además de hospedar Flutter, registra las teclas
  multimedia con `RegisterHotKey` y las manda a Dart por el canal
  `neofy/media_keys`. Ver "Teclas de los cascos" más abajo.
- **`windows/runner/audio_device_watcher.cpp`** — `IMMNotificationClient` que avisa por
  `neofy/audio_device` cuando Windows cambia el altavoz por defecto.
- **`lib/ui/`** — `shell.dart` (sidebar + contenido + barra), pantallas y `art_image.dart`.
  `tira_horizontal.dart` es la fila de tarjetas de la portada: con ratón, una lista
  horizontal dentro de una vertical no se puede mover (Flutter no permite arrastrar con el
  ratón y la rueda manda `dy`, que una lista horizontal ignora), así que lleva flechas, la
  rueda mapeada al eje y arrastre habilitado.
  `like_button.dart` es el corazón que se llena como un líquido: la ondulación **solo corre
  mientras dura el llenado** (~600 ms) y se para al acabar. Con una animación perpetua por
  fila, una lista de 3.000 canciones tendría decenas corriendo sin que nadie las mire.
- **`tool/build_librespot.ps1`** — Compila los dos sidecars. Se ejecuta una vez.
- **`tool/metadata-sidecar/`** — Binario Rust con sesión de librespot + servidor HTTP en
  `127.0.0.1:8900`. Sirve `GET /playlist/{id}?offset=&limit=` **con la forma de JSON de la
  Web API**, para que `Track.fromJson` valga sin tocar nada. Anuncia `READY <puerto>` por
  stdout cuando puede atender. Ojo al pin de `vergen 9.0.6` en su `Cargo.lock`: sin él,
  `vergen-gitcl` arrastra dos versiones de `vergen-lib` y el build script de
  `librespot-core` no compila.

## Tres procesos, no uno

`neofy.exe` (~105 MB) + `librespot.exe` (~27 MB, audio) + `metadata-sidecar.exe`
(~12 MB, playlists ajenas) ≈ **145 MB**. Los dos sidecars se lanzan y se matan desde la app;
ambos hacen `taskkill` de instancias huérfanas al arrancar, porque un cierre a lo bruto los
deja vivos. El de metadatos necesita que librespot haya cacheado credenciales antes.

## Nombre, marca e instalador

La app se llama **NeoFy**. El paquete Dart es `neofy`, el binario `neofy.exe` y el
dispositivo de Spotify Connect aparece como `NeoFy`. Los datos viven en `%APPDATA%\neofy`, y
`appDataDir()` **renombra la carpeta vieja** (`spotify-native`) la primera vez que arranca:
ahí están el refresh token y las credenciales de librespot, y perderlos por un cambio de
nombre significaría dos logins otra vez.

⚠️ **El icono es una marca propia** (barras de sonido blancas sobre azul, en
`assets/neofy.png` y `windows/runner/resources/app_icon.ico`). **No es el logo de Spotify
recoloreado, y no debe serlo**: las Directrices de Marca de Spotify prohíben expresamente
alterar sus logos —cambiar el color incluido— y usarlos como icono de una app de terceros;
sus Términos para Desarrolladores prohíben además cualquier cosa que sugiera patrocinio.
Como el proyecto va a publicarse en GitHub, esto pasa de ser un detalle a ser un riesgo real
de retirada. Que el nombre no contenga "Spotify" es, por lo mismo, correcto.

`tool\build_installer.ps1` compila los sidecars (si falta alguno), compila la app, copia los
tres binarios juntos y llama a Inno Setup: sale un único `dist\NeoFy-x.y.z-windows-x64.exe`
de ~14 MB. Es **por usuario** (`PrivilegesRequired=lowest`), así que no pide administrador ni
firma: la app solo escribe en `%APPDATA%`. El instalador mata los tres procesos antes de
copiar —si no, el ejecutable en uso bloquea la instalación— y el desinstalador borra las
cachés pero **no** los tokens, para que reinstalar no obligue a volver a loguearse.

## Versión y actualizaciones

`kVersion` en `app_config.dart` es la **única fuente de la verdad**:
`build_installer.ps1` la lee de ahí y se la pasa a Inno Setup con `/DVersion=`, y
`core/updater.dart` la usa para decidir si una release es más nueva. Teniéndola en dos
sitios acabarían por no coincidir, y el síntoma sería una app ofreciéndose actualizarse a sí
misma en bucle. **Subir de versión es tocar esa línea y nada más.**

El actualizador consulta `releases/latest` de la API de GitHub, compara **por tramos
numéricos** (`0.10.0` es posterior a `0.9.0`, cosa que una comparación de cadenas diría al
revés — hay tests), descarga el `.exe` de la release y lo lanza con `/SILENT`. Dos detalles
que importan:

- **Se comprueba el host de la descarga antes de ejecutar nada.** Esto acaba lanzando un
  ejecutable: que la URL venga en una respuesta JSON no la hace fiable por sí sola.
- **La app se cierra en cuanto arranca el instalador**, porque no se puede sobrescribir un
  ejecutable en uso. De eso se encarga `onSalirParaActualizar`, que es el mismo cierre
  ordenado del menú de la bandeja: mata los sidecars antes de irse.

El instalador conserva `%APPDATA%\neofy` entera, así que actualizar **no** hace perder la
sesión ni los ajustes.

## Publicar una versión

Todo el ciclo está en `tool\release.ps1`; no hay que tocar la API de GitHub a mano.

```powershell
# 1. Subir la versión en el UNICO sitio donde vive
#    lib/core/app_config.dart  ->  const String kVersion = '0.1.2';

# 2. Confirmar y subir ese cambio (el script exige un árbol limpio)
git commit -am "0.1.2: ..."
git push

# 3. Publicar
powershell -ExecutionPolicy Bypass -File tool\release.ps1 -Notas notas.md
powershell -ExecutionPolicy Bypass -File tool\release.ps1 -Ensayo   # sin publicar
```

El script se niega a seguir si algo no cuadra, y cada negativa tiene su motivo:

- **Árbol sucio** → lo que se etiqueta tiene que ser exactamente lo que se compila.
- **No estás en `main`, o `main` no coincide con `origin/main`** → la etiqueta apuntaría a un
  commit que nadie más tiene.
- **`analyze` o los tests en rojo** → una release rota se actualiza sola en los equipos de
  todo el mundo; es el peor sitio donde meter la pata.
- **La etiqueta ya existe** → reetiquetar una versión publicada rompe a quien ya la tenga,
  porque el actualizador se fía del número y no del contenido.

Después compila el instalador, crea la etiqueta, publica la release, sube el `.exe` y
**comprueba que se descarga públicamente**. El token sale del gestor de credenciales de
Windows (el mismo que usa `git push`) o de `$env:GITHUB_TOKEN`; no hay credenciales en el
proyecto. Sin `-Notas`, las genera con los commits desde la etiqueta anterior.

⚠️ **No subas la versión sin publicar.** Si `kVersion` avanza y no hay release, el
actualizador de quien ya la tenga no ve nada nuevo — inofensivo — pero si publicas una
release con una `kVersion` **anterior** a la que ya corre la gente, sus apps se ofrecerán
"actualizar" hacia atrás en bucle.

## Comprobación automática

`.github/workflows/ci.yml` pasa `analyze` y los tests en cada push y cada pull request, sobre
**windows-latest y ubuntu-latest**. Los dos, porque la app ya es de los dos sitios: hay tests
que tocan disco de verdad y correrlos en una sola plataforma dejaría pasar justo lo que un
cambio de rutas puede romper. Además falla si `kDefaultClientId` deja de estar vacío, para que
un Client ID no acabe publicado por descuido.

El tarball de Linux va en un workflow aparte (`linux.yml`) porque son veinte minutos de
compilar Rust y no tienen por qué esperarlos todos los push.

**El CI no compila el instalador a propósito**: haría falta compilar los dos sidecars de
Rust (su `target/` pasa de 3 GB) e instalar Inno Setup, más de veinte minutos para algo que
solo hace falta al publicar. Las releases salen de `tool\release.ps1` en local.

## El Client ID se pide, no se edita a mano

Hay dos sitios donde ponerlo y los dos escriben el mismo `config.json`:

- **El instalador**, en una página propia (`InitializeWizard` en el `.iss`) con el botón al
  panel de Spotify y el Redirect URI en un campo de solo lectura para poder copiarlo. Acepta
  también `/CLIENTID=xxx` para instalaciones desatendidas.
- **La app**, en la pantalla de primeros pasos, para quien compile desde el código o se lo
  saltara en el instalador.

Los dos **validan la forma antes de guardar** (32 caracteres hexadecimales). Sin esa
comprobación, pegar el Client *Secret* por error —que mide lo mismo— se manifestaría como un
error incomprensible de Spotify a mitad del login.

⚠️ El instalador **mezcla** el valor en el `config.json` existente en vez de reescribirlo:
si el usuario ya tenía volumen o modo rendimiento guardados, reinstalar no debe borrárselos.
Está comprobado instalando con un Client ID distinto y viendo que el resto sobrevive.

## Comandos

```powershell
flutter analyze
flutter test
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool\build_librespot.ps1   # solo la 1ª vez
.\build\windows\x64\runner\Release\neofy.exe
```

## Cuenta y credenciales

Redirect URI **exacto**: `http://127.0.0.1:8898/callback`.

El Client ID **no va en el repositorio**: `kDefaultClientId` está vacío y cada usuario pone
el suyo en `%APPDATA%\neofy\config.json`. En PKCE un Client ID no es secreto, así que no es
una cuestión de seguridad sino de que **no sirve de nada compartirlo**: en Modo Desarrollo
una app solo funciona para los 25 usuarios que su dueño da de alta a mano, de modo que
publicarlo solo consigue que un extraño le agote la cuota a su dueño. Cuando no hay Client
ID, `LoginScreen` enseña los pasos para crear uno en vez de la pantalla de login.

El refresh token vive en `%APPDATA%\neofy\tokens.json`; las credenciales de librespot en
`%APPDATA%\neofy\librespot\credentials.json`. Ninguno de los dos sale nunca del equipo.

## Trampas importantes

- **Endpoints renombrados en febrero de 2026.** Es `/v1/playlists/{id}/items`, **no**
  `/tracks`, y `POST /v1/me/playlists`, **no** `/users/{id}/playlists`. Casi toda la
  documentación de terceros sigue con los nombres viejos, que ahora dan 404.
- **El renombrado llegó también al cuerpo, no solo a las rutas.** Verificado contra la API
  real: el objeto playlist trae el recuento en `items.total`, **no** en `tracks.total`
  (leerlo mal daba "0 canciones" en todas), y cada elemento de `/items` envuelve la pista
  en la clave `item`, **no** `track`. `Playlist.fromJson` y `playlistItems()` aceptan ambas.
- **Los comandos del reproductor responden 200 con un cuerpo que no es JSON y sin
  `content-type`** — un identificador opaco tipo `jv7Ra_vijxxyQa8yrwA2dkEaDUY`. Pasarlo por
  `jsonDecode` lanzaba un `FormatException` en cada seek. `_looksLikeJson()` lo descarta.
- **La Web API solo deja leer las canciones de playlists propias.** Las ajenas devuelven
  **403** en `/items` estando en Modo Desarrollo, aunque salgan en `GET /me/playlists` y se
  puedan reproducir enteras. Comprobado ademas: `GET /playlists/{id}` responde pero **omite
  la clave con las canciones**, `?fields=` no la recupera, las playlists editoriales de
  Spotify dan **404**, y `GET /v1/tracks?ids=` tambien da **403** (los albumes, en cambio,
  si traen sus pistas). No hay ninguna via oficial: de ahi el sidecar.
- **Las carátulas de playlist son WebP y vienen con `width`/`height` a `null`** (las de
  canción son JPEG con 640/300/64 bien puestos). Flutter decodifica WebP sin problema;
  lo que importa es que `pickImage` caiga en la única imagen disponible y no la descarte.
- **`limit` de `/search` capado a 10** en Modo Desarrollo (antes 50; por defecto 5). No se
  puede subir: para ver más hay que paginar con `offset`.
- **`localhost` no vale como redirect URI**, solo el loopback literal `127.0.0.1`. El grant
  implícito está eliminado, así que PKCE no es una preferencia sino la única opción.
- **Dos logins la primera vez, y es correcto.** librespot autentica con el client_id del
  cliente de escritorio de Spotify; nuestro token de la Web API no le sirve. Los dos quedan
  cacheados y no se repiten. No intentes unificarlos con `--access-token`.
- **La cuenta de desarrollador debe mantener Premium activo** (regla de febrero 2026) o la
  app entera deja de funcionar, no solo la reproducción.
- **Al compilar librespot hay que dejar `native-tls` explícitamente.** Con
  `--no-default-features` a secas, `librespot-oauth` no compila: exige una feature de TLS.
  En Windows `native-tls` va por schannel y no necesita nada más instalado.
- **El `device_id` de librespot cambia en cada reinicio del sidecar.** Por eso las acciones
  pasan por `_withDevice()`, que ante un 404 vuelve a resolverlo y reintenta una vez.
- **Cuidado con `whenComplete(() => mapa.remove(k))` sobre un mapa de futuros.** `remove`
  devuelve el valor borrado —el propio futuro—, y `whenComplete` espera al futuro que le
  devuelve el callback: se queda esperándose a sí mismo y no completa jamás. Pasó en
  `ArtCache.bytes` y dejaba todas las carátulas en blanco *aunque los ficheros se
  descargaban bien a disco*. El cuerpo con llaves (que devuelve `void`) es obligatorio.
- **`flutter test` no puede hacer red**: sustituye `HttpClient` por un mock que devuelve
  400. Para depurar descargas de verdad, `dart run tool/probe_art.dart`.
- **"Canciones que te gustan" no es una playlist.** No sale en `GET /me/playlists`: es la
  biblioteca guardada y se lee con `GET /v1/me/tracks` (comprobado: sigue vivo, solo pide el
  scope `user-library-read`). El `/v1/me/library` de la migración de 2026 **solo acepta PUT
  y DELETE** — un GET ahí devuelve 405. Para reproducirla, el contexto es
  `spotify:user:{userId}:collection`, que no lo devuelve ninguna respuesta de la API.
- **Guardar y quitar favoritos va por `/v1/me/library`, y pide URIs.** Verificado con
  `dart run tool/probe_library.dart` contra la cuenta real: `GET /me/library/contains?uris=`
  responde `200 [true,false]`, `PUT`/`DELETE /me/library?uris=` guardan y quitan. Tres
  trampas juntas: (1) quiere **uris completas** `spotify:track:…`, y un id suelto da 400
  "Invalid Spotify URI"; (2) las uris van en la **query**, no en el cuerpo — un
  `{"uris":[…]}` en el body da 400 "Missing required field: uris"; (3) el
  `GET /me/tracks/contains` de toda la vida ahora contesta **403**, aunque `GET /me/tracks`
  (leer la biblioteca) siga funcionando. El 403 de scope se distingue del de ruta muerta por
  el mensaje: "Insufficient client scope" contra "Forbidden" a secas.
- **Crear playlist es `POST /me/playlists`; borrarla es dejar de seguirla.** Verificado con
  `tool/probe_home.dart` (crea una de prueba y la borra): `POST /me/playlists` → **201**,
  `DELETE /playlists/{id}/followers` → **200**. La ruta vieja `POST /users/{id}/playlists`
  da **403**. No existe ningún endpoint que destruya una playlist: para las propias, dejar
  de seguirlas es lo que hace también el cliente oficial.
- **Los mixes diarios y el radar de novedades no se pueden sacar.** Comprobado:
  `/browse/featured-playlists`, `/browse/new-releases` y `/browse/categories` dan **403
  Forbidden** en Modo Desarrollo, `/recommendations` está **retirado (404)**, y
  `/me/library/home` y `/me/home` no existen (404 y 410). Buscar "Daily Mix" devuelve
  imitaciones de otros usuarios, no las tuyas. Lo que **sí** funciona con su permiso:
  `/me/top/tracks`, `/me/top/artists` y `/me/player/recently-played` — daban 403
  "Insufficient client scope", que es la señal de ruta viva. De ahí que la portada sea
  historial y top propios, y no listas editoriales. Desbloquearlas exigiría salir del Modo
  Desarrollo (Extended Quota) o leerlas por el sidecar de librespot.
- **Añadir un scope obliga a reautorizar.** Renovar un refresh token **no** le añade
  permisos: el token viejo sigue con los que se concedieron. `SpotifyAuth` guarda los scopes
  concedidos junto al token y expone `needsReauth`, y la pantalla afectada ofrece rehacer el
  login. Sin esto, el síntoma es un 403 "Insufficient client scope" sin explicación.
  **Cada pantalla pregunta por su scope con `auth.hasScope`, no por `needsReauth`**, que es
  global: al estrenar `user-library-modify` para el corazón, mirar `needsReauth` habría
  bloqueado de golpe "Canciones que te gustan", que solo necesita `user-library-read` y lo
  tenía concedido desde siempre.
- **Paginar por el campo `next`, nunca contando elementos.** Descartamos las pistas no
  reproducibles, así que una página de 50 puede dejar 48 y `page.length == 50` daría la
  lista por terminada a mitad. Por eso los métodos devuelven `Page<T>` con `hasMore` (de
  `next`) y `rawCount` (para avanzar el offset **en elementos crudos**).
- **Los sliders mandan el cambio al soltar (`onChangeEnd`), nunca en `onChanged`.** Un
  `onChanged` que llame a la API dispara una petición por cada paso del arrastre: Spotify
  responde 429 y el valor acaba clavado en un punto intermedio al azar. `onChanged` solo
  toca el estado local del arrastre (`_dragMs`, `_dragVolume`).
- **Tras un cambio del usuario, el sondeo no debe pisarlo.** Spotify tarda un par de
  segundos en reflejar un salto o un volumen, y hasta entonces sigue informando del valor
  anterior. `PlayerController` guarda el cambio como "pendiente" y descarta el dato del
  servidor hasta que coincida o caduque la ventana (5 s). Sin esto, subes el volumen y
  vuelve solo al de antes, o saltas hacia delante y la barra retrocede primero.
- **`next` en la última canción no da la vuelta: mata la reproducción.** Con la repetición
  apagada, `POST /me/player/next` al final del contexto no vuelve a la primera — o contesta
  403 "Restriction violated", o para la reproducción y deja el dispositivo inactivo, con lo
  que a partir de ahí no suena nada y el botón de play tampoco arregla nada (un `play` sin
  cuerpo no tiene qué reanudar). `PlayerController.next()` lo detecta por las dos vías
  —`actions.disallows.skipping_next` antes de pedirlo, y el 403 después— y vuelve a arrancar
  el contexto con `offset: 0`. Ojo a que la clave de "anterior" es `skipping_prev`,
  abreviada. Como el 204 de `GET /me/player` deja el estado vacío y se lleva por delante el
  `contextUri`, el controlador guarda aparte el último contexto (`_lastContextUri`), que
  además es la única forma de recordar el de "Canciones que te gustan": ese no lo devuelve
  ninguna respuesta de la API.
- **Saltar de canción no reanuda: hay que mandar el `play` aparte.** `POST /me/player/next`
  conserva el estado de pausa, así que en pausa te deja la siguiente parada en el segundo 0.
  `_reanudarTrasSaltar()` lo arregla. Por eso `_withDevice` devuelve `bool`: encadenar el
  `play` solo tiene sentido si el salto se ejecutó de verdad.
- **Abrir la app reanudaba la música sola.** Spotify guarda el estado de la **sesión**, no
  el del dispositivo: si la app se cerró sonando, `transfer(play:false)` sobre el librespot
  recién arrancado la reanuda igualmente. `ensurePausedAtStartup()` lo corta.
- **El volumen no se puede dejar en un valor por defecto.** `GET /me/player` no informa de
  volumen cuando no hay reproducción activa, así que la barra caía a un 50 fijo aunque el
  usuario lo hubiera dejado en otro sitio. Se persiste en `config.json` (que es además el
  `--initial-volume` con el que arranca librespot) y se usa como respaldo del slider.
- **El título verde necesita su propio notificador.** Las listas leían
  `player.state.track.uri` en `build` sin escuchar nada, así que se quedaba clavado en la
  canción con la que se abrió la pantalla. Escuchar el `ChangeNotifier` general repintaría
  las listas en cada sondeo (cada 3 s); por eso hay un `ValueNotifier<String?> currentUri`
  que solo salta cuando cambia la canción de verdad.
- **El audio arranca antes que ninguna llamada a la Web API.** `_startSession()` tenía el
  `await _api.me()` **delante** de `_librespot.start()`, así que una petición lenta dejaba la
  app sin librespot y sin sidecar: muda, sin más síntoma que el silencio (ni error, porque el
  `catch` no llega a ejecutarse si la llamada nunca vuelve). Nada de lo que da `/me` hace
  falta para reproducir, así que va suelto con `unawaited`.
- **La cuota diaria del Modo Desarrollo se agota, y cuando lo hace se cae todo.** Visto en
  producción: `429` con `"reason": "QUOTA_EXCEEDED"` y **`Retry-After: 30819`** (8 h 34 min)
  en *todos* los endpoints a la vez. Como el control de reproducción también va por la Web
  API, la app entera queda inservible hasta que se levante. Dos consecuencias en el código:
  (1) `Retry-After` no son "unos segundos" — dormirlos dentro de `_request` congelaba la app
  sin decir por qué; ahora se espera 10 s como mucho y, si pide más, se anota la hora en
  `_cuotaHasta` y las peticiones siguientes **fallan en el acto sin salir a la red**, porque
  cada una de más mantiene viva la penalización; (2) el sondeo se espacia a 1 min mientras
  dure, en vez de seguir a 3 s. La barra de reproducción lo enseña con la hora a la que
  vuelve. Toda petición tiene además un plazo de 20 s: una llamada colgada no puede volver a
  bloquear el arranque.
- **Cuidado con el gasto de cuota al sondear.** 3 s sonando son **1.200 peticiones a la
  hora**; ocho horas de uso pueden agotar la cuota diaria por sí solas, y a eso hay que
  sumarle las consultas de favoritos y la portada. Si esto se repite, el primer sitio donde
  mirar es `_pollInterval`.
- **Las sondas de `tool/` rotan el refresh token.** Spotify lo cambia en cada renovación y el
  viejo deja de valer, así que un script que renueve y no guarde el nuevo **deja a la app sin
  sesión**. `probe_top.dart` lo devuelve a `tokens.json`; hay que hacer lo mismo en cualquier
  sonda nueva, y ejecutarlas con la app cerrada.
- **librespot sobrevive si la app muere de golpe.** El cierre ordenado lo mata, pero un
  cuelgue o un kill deja el proceso sonando y ocupando el nombre del dispositivo. Por eso
  `start()` hace `taskkill /F /IM librespot.exe` antes de lanzar el suyo. Es seguro porque
  la app es de instancia única.

## RAM: cómo se mide

**El Administrador de tareas engaña.** Agrupa por ventanas de nivel superior, y los dos
sidecars son procesos de consola sin ventana: aparecen sueltos entre los de segundo plano,
no bajo `neofy.exe`. Mirar solo esa fila se deja fuera cerca de un 25 % del gasto,
y no hay forma de cambiar cómo agrupa Windows (los Job Objects no alteran esa vista).

Por eso `core/ram_monitor.dart` suma los tres cada 5 s y `ui/ram_badge.dart` lo enseña al pie
del panel lateral, con el desglose en el tooltip y en rojo si pasa del objetivo. El propio
proceso se lee con `ProcessInfo.currentRss`; los hijos, con `GetProcessMemoryInfo` por FFI
(`dart:ffi` viene con el SDK; `package:ffi` solo aporta el allocator) en vez de lanzar
`tasklist`, que costaría más que lo que mide. Los pids se piden al vuelo con una función:
los sidecars se reinician solos y cambian de pid.

## RAM: lo que se hizo para bajarla

Medido antes/después en la misma máquina, con la app recién arrancada:
`neofy` pasó de **162 MB de working set (100 MB privados)** a **~127 MB (70 MB
privados)**; el total de los tres procesos, de 205 a ~166 MB. Tres cambios:

1. **`Image.file` en vez de `Image.memory`.** Era el gordo. `MemoryImage` es la **clave** de
   la entrada en el `imageCache` de Flutter, y una clave viva mantiene vivo su `Uint8List`:
   por cada carátula cacheada se guardaban las dos cosas, el bitmap decodificado *y* el JPEG
   entero. Encima, cada `ArtImage` sujetaba su propio futuro con los bytes mientras su fila
   existiera. Con `FileImage` la clave es una ruta y los bytes se sueltan al decodificar. Por
   eso `ArtCache.file()` devuelve el fichero y `bytes()` queda solo para `probe_art.dart`.
   Hay un test (`test/art_image_test.dart`) que lo fija, porque volver a `MemoryImage` sin
   querer no se nota mirando la pantalla.
2. **`imageCache` de 16 a 8 MB / 150 a 120 entradas.** Sobra: una miniatura de fila
   decodificada a 40 px ocupa ~14 KB (caben quinientas) y las tarjetas de la portada, que son
   las caras, ~150 KB.
3. **Soltar la caché de imágenes al esconderse en la bandeja.** Un reproductor se pasa la
   vida ahí, y ahí no hay ni una imagen que mirar. No se pierde nada: las carátulas siguen
   en disco y al volver se redecodifican sin tocar la red.

**Cuidado al leer los números**: de los ~127 MB de working set, unos 55 son DLLs compartidas
(`flutter_windows.dll` son 21 MB él solo, más ANGLE y las del sistema). Lo exclusivo de la
app son los ~70 MB privados, y ahí el suelo de un Flutter vacío en Windows anda por 55-65 MB:
queda poco margen sin cambiar de stack.

## Modo rendimiento

Interruptor en Ajustes (pie del panel lateral). Objetivo: 100 MB entre los tres procesos.
Medido con la ventana en segundo plano, que es donde vive un reproductor: **58 MB frente a
89 MB** del modo normal; con la ventana delante y navegando, el modo normal se va a ~150 y
el de rendimiento se mantiene pegado al techo. Qué hace:

- **No baja ni una imagen.** `ArtImage` pinta un degradado cuyo tono sale del `hashCode` de
  la propia URL, así que **cada disco tiene siempre el mismo color** y las listas se siguen
  leyendo de un vistazo. Cuesta cero bytes.
- **La caché de bitmaps baja a 1 MB** y se vacía al entrar.
- **Se apaga el sidecar de metadatos** (~12 MB). Se pierde poder leer playlists ajenas.
- **Se le pide a Windows que recoja las páginas** (`EmptyWorkingSet`) al entrar, al esconder
  la app en la bandeja, y cada 30 s mientras el total pase del techo. No se pierde nada: las
  páginas vuelven solas con un fallo blando.
- **El audio no se toca**: mismo bitrate, misma caché, mismo librespot.

⚠️ **El working set depende de si la ventana está en primer plano**: Windows poda por su
cuenta las de fondo. Comparar dos medidas tomadas en distinta situación no dice nada.

## RAM: las tres cosas que de verdad importan

El objetivo es <130 MB sumando app y sidecar (el Spotify oficial anda por 400-700 MB).
Si sube, mira en este orden:

1. **Tamaño de carátula.** Spotify sirve cada imagen en 640/300/64 px, y en **JPEG** las de
   canción/álbum y **WebP** las de playlist (comprobado sobre la caché real: 2.988 JPEG de
   4,4 KB de media). El formato da igual para la RAM —los dos decodifican al mismo bitmap—;
   lo que importa es el escalón que se pide. `ArtImage` recibe las dos variantes y **elige
   por píxeles reales** (`size * devicePixelRatio`), no por el tamaño lógico: los 56 px de
   la barra de reproducción caben en la de 64 en una pantalla al 100 %, pero necesitan la de
   300 en una HiDPI al 200 %. Fijarlo a ojo obligaba a acertar para todas las pantallas a la
   vez, y con la de 300 clavada se bajaban hasta 78 KB por canción para pintar 56 px.
2. **`cacheWidth`/`cacheHeight` en cada `Image`** (`ArtImage` ya lo hace). Sin ellos Flutter
   guarda el bitmap a resolución completa aunque se pinte a 40 px.
3. **Virtualizar y paginar.** `ListView.builder` en todo, y las playlists de 50 en 50 con
   scroll infinito. Nunca materializar una playlist entera.

Además: `imageCache` limitado a 16 MB / 150 entradas en `main.dart` (Flutter permite 100 MB
por defecto).

### Caso aparte: "Canciones que te gustan"

Es la única lista que se carga **entera** (~60 peticiones secuenciales para 3.000 canciones)
en vez de por scroll infinito, porque el usuario la quiere completa. Lo que la mantiene
barata no es cargar menos, sino **una ventana deslizante de carátulas**: solo las 25 filas
por encima y 25 por debajo del centro de la pantalla piden imagen (`TrackTile.showArt`), así
que da igual que haya 3.000 filas — nunca hay más de ~50 imágenes vivas, ni una avalancha de
descargas al pasar el scroll rápido. Las 3.000 pistas en memoria cuestan poco más de 1 MB.

El centro visible se deduce por aritmética del scroll, lo que obliga a que la lista tenga
`itemExtent` fijo. **Vale 64 y no es arbitrario**: es el alto de un `ListTile` `dense` de dos
líneas. Si `TrackTile` cambia de alto, la lista desborda o la ventana se desalinea — hay
tests en `test/track_tile_test.dart` que fijan ese número.

## Los stores existen por la navegación, no por capricho

`_content()` en `shell.dart` construye **solo la vista activa** (a propósito: mantener las
cinco vivas mantendría vivas sus listas y sus imágenes). El efecto secundario es que al
salir de una pantalla y volver, su `State` se ha destruido. Cualquier dato que costara
peticiones tiene que vivir **fuera** de la pantalla o se vuelve a bajar cada vez — le pasó a
"Canciones que te gustan", que rebajaba sus ~60 páginas en cada visita. Por eso
`LikedStore` y `HomeStore` cuelgan de `main.dart` y sobreviven a la navegación, y las
pantallas solo guardan lo suyo (el scroll, la ventana de carátulas).

## El audio que se queda mudo

**Síntoma:** al cabo de un rato, o justo al cambiar de altavoces, deja de sonar. La app
sigue como si nada —la barra avanza, Spotify dice que la canción se está reproduciendo— y la
única cura era matar el proceso y volver a abrir NeoFy.

**Causa:** librespot abre el dispositivo de salida **una vez, al arrancar**, y no lo suelta.
Si el usuario se pone unos cascos, los quita, o Windows cambia el altavoz por defecto, el
flujo se queda escribiendo en un sitio que ya no reproduce. Y como el proceso **no se
muere**, el reinicio automático de `LibrespotManager` —que solo entra cuando cae— no se
activa nunca. Nadie da error por ningún lado: el único síntoma es el silencio.

Se ataca por tres vías, porque ninguna las cubre todas:

1. **El aviso del sistema.** `windows/runner/audio_device_watcher.cpp` registra un
   `IMMNotificationClient` y avisa a Dart cuando cambia el dispositivo de salida por defecto
   (`eRender` + `eConsole`, que es el que elige cpal, la capa de debajo de rodio; los otros
   roles cambian sin que la música se mueva de sitio). La llamada llega en un hilo del
   servicio de audio, así que se hace un `PostMessage` a la ventana y el canal se toca desde
   el hilo de siempre.
2. **El log de librespot.** `esFalloDeAudio()` reconoce los `ERROR` del backend de audio, que
   es lo único que queda escrito cuando la salida se rompe sin que Windows cambie de
   dispositivo. Se busca por el nombre del backend (rodio, cpal, "audio sink") y no por el
   texto del error: los mensajes cambian de versión en versión, el backend no.
3. **El botón de Ajustes**, para lo que no se detecta: un driver atascado, otra aplicación
   que se queda el dispositivo en modo exclusivo.

Las tres acaban en `_reiniciarAudio()` de `main.dart`, y ahí importan cuatro detalles:

- **Se agrupan los avisos.** Un solo cambio de salida dispara varios (aparece el dispositivo,
  pasa a ser el de por defecto…) y un fallo de audio deja varias líneas de log seguidas.
  `AudioDeviceWatcher` espera 1,2 s y hay además una ventana de 20 s entre reinicios
  automáticos. Reiniciar corta el sonido un par de segundos: hacerlo tres veces seguidas
  sería peor que el fallo.
- **El `device_id` nuevo no es el viejo, y Spotify sigue listando el viejo** unos segundos
  después de matarlo. Por eso `resolveDevice(distintoDe:)`: quedarse con ese id significaría
  mandar la música a un proceso muerto.
- **Retomar es traspasar, no volver a arrancar.** El estado vive en la sesión de Spotify, no
  en el dispositivo (la misma razón por la que abrir la app reanudaba la música sola). Lo
  único que no se recupera solo es la posición, que se manda aparte. El plan B —arrancar el
  contexto con `offset: {uri}`— solo hace falta si la sesión se dio por terminada.
- **Un proceso que ya no es el actual no manda.** Si el librespot viejo tarda más de dos
  segundos en morir se le mata a lo bruto y `stop()` no espera; su aviso de salida puede
  llegar con el nuevo ya arrancado, y darlo por caído reiniciaría otra vez el audio que
  acabábamos de recuperar. `_onExit` compara el proceso antes de hacer nada.

## Teclas de los cascos

El botón de play/pausa de unos auriculares manda `VK_MEDIA_PLAY_PAUSE`, la misma tecla que
el teclado multimedia. Para recibirla **con la app en segundo plano** hace falta
`RegisterHotKey`, que necesita un HWND y una cola de mensajes de Windows: desde Dart no hay
forma de ver un `WM_HOTKEY`. Está en `windows/runner/flutter_window.cpp` (~60 líneas) y
llega a Dart por un `MethodChannel`.

No se usó ningún paquete: el candidato obvio (`hotkey_manager`) le pasa a `RegisterHotKey`
el **código HID de Flutter** (`PhysicalKeyboardKey.keyCode`, del orden de `0x00070004`) en
vez del virtual-key de Windows, así que no registraría nada — y traía ocho dependencias
transitivas.

Aparte, `shell.dart` atiende la barra espaciadora y las teclas multimedia por el árbol de
foco, para cuando la ventana está delante. **Ojo con el espacio**: en escritorio una tecla
llega por dos vías a la vez (evento de teclado al árbol de foco *y* texto al campo por el
canal del motor), así que sin comprobar si hay un `EditableText` enfocado, escribir un
espacio en el buscador metería el espacio y además pausaría la música.

## Linux

El port a Arch fue barato porque casi nada de la app es de Windows: `spotify_api.dart`,
`auth.dart`, `player_state.dart`, los stores, los modelos y las trece pantallas de `lib/ui/`
no tienen una sola llamada al sistema. Lo que hubo que rehacer es la capa que sí lo toca, y
en tres de los cuatro casos **la solución de Linux es mejor que la de Windows**.

- **Las teclas multimedia son MPRIS** (`core/mpris.dart`), no `RegisterHotKey`. En Windows
  hizo falta C++ porque desde Dart no hay forma de ver un `WM_HOTKEY`; en Linux el escritorio
  ya escucha esas teclas y lo que busca es un reproductor que hable D-Bus. De regalo, NeoFy
  sale en el widget de reproducción de KDE y GNOME con carátula, y `playerctl` lo controla —
  la misma propiedad que hace que un Stream Deck funcione en Windows sin plugin. Va con
  `package:dbus`, que es Dart puro: **no hay una línea de código nativo en `linux/runner/`**.
- **El vigilante de la salida de audio no existe, y no hace falta.** `audio_device_watcher.cpp`
  resuelve en Windows que librespot abre el altavoz una vez y no lo suelta. En Linux se compila
  librespot con el backend de **PulseAudio** y PipeWire mueve el flujo solo al cambiar de
  dispositivo. Se conservan las otras dos vías por si acaso: el log (`esFalloDeAudio()`
  reconoce también `pulseaudio` y `alsa`) y el botón de Ajustes.
- **Matar sidecars huérfanos va por fichero de PID** (`core/procesos.dart`), no por nombre.
  ⚠️ La traducción obvia de `taskkill /F /IM` sería `pkill librespot`, y **sería un error
  grave**: mataría el `spotifyd` del usuario o cualquier otro librespot del sistema. Se anota
  el pid que lanzamos nosotros en `$XDG_RUNTIME_DIR/neofy/` y antes de matarlo se comprueba en
  `/proc/<pid>/cmdline` que sigue siendo el mismo proceso — un pid se recicla, y matar a ciegas
  el número apuntado sería tan malo como el `pkill`.
- **La memoria se mide por `/proc`**, que sale más simple que el FFI a `psapi`. El parseo está
  en `rssDeStatm()` y `ticksDeStat()`, aparte y probadas con cadenas fijas para que valgan
  también en el runner de Windows del CI. Dos trampas: el segundo campo de `/proc/<pid>/stat`
  es el nombre del proceso **entre paréntesis y puede llevar espacios y paréntesis dentro**,
  así que hay que contar desde el último `)` o se desalinean todos los campos sin dar error; y
  los ticks se devuelven en unidades de 100 ns para que el cálculo del porcentaje sea el mismo
  en las dos plataformas.

### Rutas

`appDataDir()` guarda lo que no se puede perder (`config.json`, `tokens.json`, credenciales de
librespot) y `cacheDir()` lo que sí (carátulas, caché de audio). **En Windows las dos devuelven
la misma carpeta a propósito**: separarlas obligaría a migrar la caché de quien ya tiene la app
instalada, y a cambio de nada. En Linux salen de XDG (`~/.config/neofy` y `~/.cache/neofy`),
donde sí importa: hay herramientas que dan por hecho que `~/.cache` se puede borrar entero.

### La bandeja puede no existir

`tray_manager` necesita `libayatana-appindicator`, y **en GNOME sin la extensión de
AppIndicator no aparece ningún icono**. Antes `_setupTray()` se tragaba el fallo y la X
escondía la ventana igualmente: la app se quedaba viva, sonando y fuera del alcance del
usuario, que solo podía matarla desde un monitor de sistema. Ahora se guarda si la bandeja
llegó a montarse y, si no, **la X cierra de verdad**. MPRIS compensa: aunque no haya icono, el
widget del escritorio sigue controlando la reproducción.

El icono de bandeja es `.png` en Linux y `.ico` en Windows — un `.ico` allí no lo pinta ni GTK
ni el indicador. Los dos salen del mismo dibujo: `tray.ico` ya traía los siete tamaños como PNG
dentro, así que el árbol hicolor de `linux/packaging/icons/` se extrajo de ahí sin reescalar
nada.

### Lo que se pierde

**`EmptyWorkingSet` no tiene equivalente.** El modo rendimiento conserva sus otros tres efectos
—no bajar imágenes, caché de bitmaps a 1 MB y apagar el sidecar de metadatos—, que son los que
de verdad pesan, pero la parte de devolverle páginas al sistema es un no-op documentado en
`vaciarWorkingSet()`. `malloc_trim` no serviría de mucho: la memoria de Flutter está en el heap
de Dart y en Skia, no en las arenas de glibc.

### El actualizador avisa pero no instala

En Linux NeoFy se distribuye como paquete (`neofy-bin` en el AUR) y es pacman quien lleva la
cuenta de qué ficheros son de quién. Una app que se sobrescribe a sí misma deja la base de
datos del gestor mintiendo. `Updater.buscar()` sigue funcionando igual —la comparación por
tramos numéricos no cambia—, pero al detectar novedad se para y Ajustes enseña
`yay -Syu neofy-bin` en vez del botón de instalar.

### Cómo se compila y se publica

```bash
./tool/build_sidecars.sh        # solo la 1ª vez
flutter build linux --release
./tool/build_linux_bundle.sh    # saca dist/NeoFy-x.y.z-linux-x86_64.tar.gz
```

`build_sidecars.sh` compila librespot con **rustls** y no con `native-tls`: en Windows
`native-tls` va por schannel y no arrastra nada, pero en Linux iría por OpenSSL y ataría el
binario a la versión exacta de `libssl` de la máquina donde se compiló, que es justo lo que no
queremos en un paquete `-bin`. (El sidecar de metadatos sí arrastra OpenSSL, porque
`librespot-core` trae `native-tls` en sus features por defecto; por eso el PKGBUILD lleva
`openssl` en `depends`.)

Nada de esto **se compila en local**: lo genera `.github/workflows/linux.yml` sobre
**ubuntu-latest a propósito**, porque su glibc es más antigua que la de Arch y un binario
compilado contra una glibc vieja corre en una nueva, nunca al revés. Tiene dos disparadores:
`workflow_dispatch` deja los artefactos descargables —así alguien puede probar sin instalar
Flutter ni Rust— y `release: published` los sube a la release.

⚠️ **El disparador es `release: published` y no `push: tags`.** `release.ps1` sube la etiqueta
*antes* de crear la release, así que un workflow colgado del tag arrancaría cuando la release
todavía no existe y la subida fallaría.

### Qué lleva cada release

Un instalador por plataforma, y los tres instalan **exactamente el mismo árbol de ficheros**
(`/opt/neofy` entero, enlace en `/usr/bin`, `.desktop` e iconos hicolor):

| Fichero | Quién lo hace | Para quién |
|---|---|---|
| `NeoFy-x.y.z-windows-x64.exe` | `release.ps1` → Inno Setup | Windows |
| `neofy_x.y.z_amd64.deb` | `build_linux_packages.sh` → `dpkg-deb` | Debian, Ubuntu |
| `neofy-x.y.z-1.x86_64.rpm` | `build_linux_packages.sh` → `rpmbuild` | Fedora, openSUSE |
| `NeoFy-x.y.z-linux-x86_64.tar.gz` | `build_linux_bundle.sh` | **No es una descarga**: es lo que se baja el PKGBUILD del AUR |

El bundle de Flutter **no se puede repartir por `/usr`**: el ejecutable busca `data/` y `lib/`
a su lado, de ahí que todo vaya a `/opt/neofy` con un enlace en `/usr/bin`. El enlace es
seguro porque Dart resuelve `Platform.resolvedExecutable` al destino real, así que
`findBinary()` sigue encontrando los sidecars.

Dos detalles del `.rpm` que costaría descubrir a base de intentos: **`AutoReqProv` va
desactivado**, porque si no `rpmbuild` lee los ELF del bundle y genera `Requires` de las
librerías que el propio paquete trae dentro (`libflutter_linux_gtk.so` y las de los plugins),
que no existen como paquete en ninguna distribución y dejarían el rpm imposible de instalar; y
**se anula `__os_install_post`** para que no pase un `strip` a unos binarios que ya vienen
compilados.

Los nombres de las dependencias no se parecen entre familias y hay que darlos a mano en cada
formato: `gtk3` en Arch y Fedora es `libgtk-3-0` en Debian, `libpulse` es `libpulse0` allí y
`pulseaudio-libs` en Fedora.

`linux/packaging/PRUEBAS.md` tiene la lista de comprobación manual: el audio, la bandeja y
MPRIS no los cubre ningún test y no se pueden validar desde Windows.

## Sondeo: por qué es como es

`player_state.dart` sondea `GET /me/player` cada 3 s con la ventana visible y sonando; 15 s
en pausa; 30 s oculto en la bandeja. Entre sondeos, un timer de 250 ms **interpola la
posición en local** y actualiza un `ValueNotifier` que solo repinta la barra de progreso.
Así se mueve suave sin gastar ni una petición y sin repintar la pantalla entera.
No lo cambies a sondear más rápido: la cuota de la API es limitada y no hace falta.
