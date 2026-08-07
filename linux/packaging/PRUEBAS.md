# Comprobación de NeoFy en Arch

Lista para quien pruebe el port en una máquina Arch de verdad. **Pásala entera y
responde de una vez**: quien desarrolla está en Windows y no puede reproducir
nada de esto, así que cada ida y vuelta cuesta un día. Con que anotes al lado de
cada punto un ✅ o qué pasó exactamente, sobra.

## De dónde sacar el binario

No hace falta instalar Flutter ni Rust. En la pestaña **Actions** del
repositorio, workflow **Linux** → *Run workflow*; al terminar deja un
`NeoFy-<version>-linux-x86_64.tar.gz` descargable como artefacto.

```bash
tar -xzf NeoFy-*-linux-x86_64.tar.gz
cd NeoFy-*-linux-x86_64
./neofy
```

Dependencias que tienen que estar (las declara el PKGBUILD, pero para probar el
tarball suelto conviene comprobarlas):

```bash
sudo pacman -S --needed gtk3 libayatana-appindicator libpulse openssl
```

Di también **qué escritorio usas** (KDE, GNOME, Hyprland…) y si es Wayland o
X11: la mitad de los puntos de abajo dependen de eso.

---

## 1. Primer arranque sin Client ID

En Linux no hay instalador que lo pida, así que la pantalla de primeros pasos de
la app es **la única vía** que tiene un usuario nuevo.

- [ ] Al abrir sin configurar nada, ¿sale una pantalla explicando cómo crear un
      Client ID en el panel de Spotify, en vez de un login que no puede funcionar?
- [ ] ¿Se entienden los pasos sin conocer el proyecto? Si algo no se entiende,
      **dilo con tus palabras**: es lo que va a leer todo el mundo.
- [ ] El Redirect URI tiene que ser exactamente `http://127.0.0.1:8898/callback`.

## 2. Los dos logins

Son dos a propósito: uno de la Web API y otro de librespot, que usa el client_id
del cliente de escritorio de Spotify y no acepta nuestro token.

- [ ] ¿Se abre el navegador las dos veces y las dos vuelven bien a la app?
- [ ] Cierra NeoFy y vuelve a abrirlo: **no debería pedir ningún login otra vez**.

## 3. Que suene, y dónde deja sus cosas

- [ ] Reproduce algo. ¿Suena?
- [ ] `ls ~/.config/neofy` → `config.json`, `tokens.json`, `librespot/`.
- [ ] `ls ~/.cache/neofy` → `art/`, `audio/`.
- [ ] **Que no haya aparecido `~/.config/neofy/art`**: las carátulas van a la
      caché, y si están en config es que la separación no funcionó.

## 4. Cambiar de salida con la música sonando

Este es **el punto más importante de la lista**. En Windows este fallo obligó a
escribir un vigilante en C++; en Linux la apuesta es que PipeWire mueve el flujo
solo y no hace falta nada. Si esto falla, el port necesita otra solución.

- [ ] Con música sonando, cambia la salida por defecto (`pavucontrol` o el menú
      del sistema): de altavoces a cascos, a HDMI, a Bluetooth.
- [ ] ¿Sigue sonando por la salida nueva, sin cortes de más de un segundo?
- [ ] Enchufa y desenchufa unos cascos Bluetooth mientras suena.
- [ ] Si en algún momento **se queda mudo pero la barra sigue avanzando**, es
      exactamente el fallo que buscamos: dilo y pega la salida de
      `journalctl --user -n 50` o lo que haya escrito la terminal.
- [ ] Ajustes → botón de reiniciar el audio: ¿lo recupera?

## 5. Teclas multimedia y widget del escritorio

Esto va por MPRIS, que sustituye al `RegisterHotKey` de Windows.

- [ ] Con la ventana **escondida o minimizada**, las teclas de play/pausa,
      siguiente y anterior del teclado, ¿funcionan?
- [ ] El botón de unos auriculares, ¿también?
- [ ] ¿Sale NeoFy en el widget de reproducción del sistema (KDE: el applet de
      medios; GNOME: el menú de la esquina) con **título, artista y carátula**?
- [ ] `playerctl metadata` debería contestar. Pega la salida.
- [ ] Pausa desde el widget del escritorio: ¿la app se entera?
- [ ] Pausa desde **la app**: ¿el widget del escritorio se entera? (Este es el
      que más fácil se queda desincronizado.)

## 6. Bandeja — y el plan B

- [ ] ¿Aparece el icono en la bandeja? En KDE debería; **en GNOME sin la
      extensión de AppIndicator es normal que no**.
- [ ] Si **sí** hay icono: la X esconde la app, el icono la trae de vuelta, y el
      menú del botón derecho (reproducir, siguiente, anterior, salir) funciona.
- [ ] Si **no** hay icono: la X tiene que **cerrar la app del todo**. Comprueba
      con `pgrep -a neofy` que no queda nada vivo. Que se escondiera sin icono
      dejaría la app inalcanzable, que es el fallo que esto previene.

## 7. Matar la app a lo bruto

- [ ] Con música sonando: `pkill -9 neofy`.
- [ ] `pgrep -a librespot` → habrá quedado uno huérfano sonando. Normal.
- [ ] Vuelve a abrir NeoFy. ¿Mató al huérfano y suena solo el suyo?
- [ ] **Y lo más importante**: si tenías otro `librespot` o un `spotifyd`
      corriendo por tu cuenta, **tiene que seguir vivo**. La app solo puede matar
      el proceso que ella misma anotó. Si te mata algo tuyo, es un fallo grave.

## 8. La insignia de memoria

- [ ] Al pie del panel lateral hay una insignia con la RAM. ¿Enseña un número
      real y no ceros?
- [ ] Pasa el ratón por encima: el desglose debería dar tres cifras (app, audio,
      metadatos), no una.
- [ ] ¿El total se parece a lo que dice `ps -o rss= -p $(pgrep -d, -f 'neofy|librespot|metadata-sidecar')`?

## 9. Modo rendimiento

- [ ] Ajustes → modo rendimiento. Las carátulas se sustituyen por degradados de
      color (cada disco siempre del mismo tono).
- [ ] ¿Baja la memoria de la insignia?
- [ ] **La música no debe cortarse ni cambiar de calidad** al encenderlo.
- [ ] Ojo: en Linux la parte de "devolver páginas al sistema" no existe, así que
      la bajada será menor que en Windows. Eso es esperado; lo que importa es
      que las carátulas desaparezcan y el sidecar de metadatos se apague.

## 10. El paquete

```bash
# Con el PKGBUILD de este directorio, en una carpeta vacía:
makepkg -si
```

- [ ] ¿Instala sin quejarse?
- [ ] ¿Sale NeoFy en el menú de aplicaciones, **con su icono** y no con uno
      genérico?
- [ ] Ánclalo a la barra de tareas y ábrelo: ¿la ventana se asocia al lanzador
      (mismo icono, no una entrada duplicada)?
- [ ] `sudo pacman -Rns neofy-bin` → ¿desinstala limpio?
- [ ] Tras desinstalar, `~/.config/neofy` **debe seguir ahí**: los tokens no se
      borran, para que reinstalar no obligue a loguearse otra vez.

---

## Si algo va mal

Lo más útil que puedes mandar, por orden:

1. Qué escritorio, sesión (Wayland/X11) y versión de Arch.
2. La salida de la terminal al lanzar `./neofy` desde ella.
3. `pgrep -a 'neofy|librespot|metadata-sidecar'`.
4. Para fallos de audio: `pactl info` y `systemctl --user status pipewire`.
5. Para fallos de MPRIS: `busctl --user list | grep mpris` y `playerctl -l`.
