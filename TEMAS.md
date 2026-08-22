# Temas de NeoFy

Guía para hacer temas. Un tema es **una carpeta con un `tema.json` dentro**. No hace falta
compilar nada, no hace falta saber Dart y no hace falta reiniciar NeoFy: se guarda el fichero
y la ventana cambia sola.

Si vienes de [Spicetify](https://spicetify.app/docs/development/themes), la idea es la misma
—colores declarados en un fichero suelto que la app lee al arrancar— pero **no hay CSS**.
NeoFy no es Electron: es Flutter compilado a nativo, así que no existe un DOM al que meterle
reglas. Lo que se declara son los colores y los materiales, y la app los reparte por toda la
interfaz. A cambio de perder el `user.css`, ningún tema se rompe cuando cambia la interfaz.

---

## Empezar en un minuto

```powershell
dart run tool/tema.dart nuevo "Mi tema"
```

Eso crea la carpeta con el `tema.json` ya relleno, **dentro de la carpeta de temas de
NeoFy**, así que aparece en la lista al momento. Ábrelo, cambia un color, guarda, y mira la
ventana: ya está cambiada.

Si no tienes el repositorio clonado, hazlo a mano: crea una carpeta en el sitio de la tabla
de abajo y mete dentro un `tema.json` con esto:

```json
{
  "nombre": "Mi tema",
  "brillo": "oscuro",
  "colores": { "primario": "#1DB954" }
}
```

Eso ya es un tema válido. **Solo `nombre` y `colores.primario` son obligatorios**; todo lo
demás se deduce, y se deduce a algo razonable. Añade claves solo cuando no te guste lo
deducido.

También puedes crear la plantilla desde la propia app, sin tocar la terminal:
**Ajustes → Tema → Cambiar → Crear una plantilla**.

---

## Dónde van los temas

| Sistema | Carpeta |
|---|---|
| Windows | `%APPDATA%\neofy\temas` |
| Linux | `~/.config/neofy/temas` (o `$XDG_CONFIG_HOME/neofy/temas`) |

Una carpeta por tema. El **nombre de la carpeta es el id** del tema salvo que pongas `id` en
el `tema.json`, y el id es lo que se guarda en los ajustes: si renombras la carpeta de un
tema que alguien tiene puesto, a esa persona se le queda en "Automático".

```
%APPDATA%\neofy\temas\
└── mi-tema\
    ├── tema.json        ← lo único obligatorio
    ├── fondo.jpg        ← opcional
    └── Inter.ttf        ← opcional
```

NeoFy vigila esa carpeta mientras está abierto. Guardar el `tema.json` basta: no hay que
cerrar la app ni volver a elegir el tema.

---

## El fichero entero

Este es un `tema.json` con **todo** lo que se puede poner. Repito: casi nada es obligatorio.

```json
{
  "formato": 1,
  "id": "mi-tema",
  "nombre": "Mi tema",
  "autor": "tu nombre",
  "version": "1.0.0",
  "descripcion": "Una línea que se lee en el selector.",

  "brillo": "oscuro",
  "radio": 12,
  "radioBoton": 20,

  "colores": {
    "primario":      "#1DB954",
    "sobrePrimario": "#06210F",
    "fondo":         "#121212",
    "superficie":    "#1C1C1C",
    "panel":         "#0A0A0A",
    "texto":         "#F2F2F2",
    "textoTenue":    "#A8A8A8",
    "borde":         "#2A2A2A",
    "error":         "#FF6B6B"
  },

  "cristal": {
    "activo": false,
    "desenfoque": 24,
    "opacidad": 0.16,
    "saturacion": 1.6,
    "brillo": 0.28,
    "borde": 0.26,
    "radio": 18
  },

  "fondo": {
    "imagen": "fondo.jpg",
    "ajuste": "cubrir",
    "opacidad": 1.0,
    "desenfoque": 0,
    "oscurecer": 0,
    "usarCaratula": false,
    "degradado": ["#0B1026", "#05070E"],
    "anguloDegradado": 135
  },

  "navegacion": "lista",

  "movimiento": {
    "esquema": "sobrio",
    "rebote": 0.3,
    "velocidad": 1.0
  },

  "tipografia": {
    "familia": "Inter",
    "ficheros": ["Inter.ttf"],
    "escala": 1.0
  }
}
```

### Identidad

| Clave | Tipo | Por defecto | Para qué |
|---|---|---|---|
| `nombre` | texto | — | **Obligatorio.** Lo que se lee en el selector. |
| `id` | texto | el nombre de la carpeta | Identificador estable. Cámbialo lo menos posible. |
| `autor` | texto | vacío | Se enseña en el selector. |
| `version` | texto | vacío | Para ti y para quien lo instale. |
| `descripcion` | texto | vacío | Una línea. Dos como mucho: se corta. |
| `formato` | entero | `1` | Versión del formato. Hoy solo existe el `1`. |

### Forma y tono

| Clave | Tipo | Por defecto | Para qué |
|---|---|---|---|
| `brillo` | `"claro"` \| `"oscuro"` | `"oscuro"` | Decide los iconos, las sombras y los valores deducidos. Si te equivocas aquí, el resto sale mal. |
| `radio` | 0–40 | `12` | Redondeo general: tarjetas, diálogos, carátulas. `0` deja todo en esquina viva. |
| `radioBoton` | 0–999 | `radio + 8` | Redondeo solo de los botones. Ponlo muy alto (`999`) para píldoras completas. Mezclar un `radio` moderado con botones redondos es lo que hace Material 3 Expressive, y es la forma barata de que un tema tenga carácter. |
| `radioCaratula` | 0–40 | `6` | Redondeo de las carátulas. Se limita solo a `lado × 0.28`, para que una miniatura de 32 px no acabe siendo un círculo. |
| `navegacion` | `lista`, `pildora` | `lista` | `pildora` mete el elemento seleccionado del menú en una cápsula rellena, al estilo de Material You. `lista` es la fila sobria de siempre. |

### La escala de formas

Material no usa un radio, usa **cinco**, y reparte cada paso a un tipo de componente. NeoFy
hace lo mismo: los deriva de `radio` con los factores ⅓, ⅔, 1, 4/3 y 2.

Eso significa que con el `radio: 12` por defecto sale **4, 8, 12, 16, 24**, que es
exactamente la escala que documenta Compose. No hay que tocar nada para tenerla.

| Paso | Con `radio: 12` | Dónde se aplica |
|---|---|---|
| `extraPequeno` | 4 | Tooltips y avisos emergentes |
| `pequeno` | 8 | Menús contextuales y chips |
| `medio` | 12 | Tarjetas |
| `grande` | 16 | *(reservado)* |
| `extraGrande` | 24 | Diálogos |

Si la proporción no te sirve, el bloque `formas` pisa los pasos que quieras, y los que no
menciones siguen derivándose:

```json
"formas": { "medio": 20, "extraGrande": 36 }
```

La herramienta avisa si la escala no va de menor a mayor: con los pasos desordenados acabas
con diálogos más cuadrados que las tarjetas, que es justo lo contrario de lo que busca
Material.

### La barra de reproducción

| Clave | Valores | Por defecto | Qué hace |
|---|---|---|---|
| `progreso` | `linea`, `onda` | `linea` | `onda` sustituye la barra por el indicador ondulado de Material 3 Expressive. |

Con `onda`, la parte ya reproducida se dibuja como una onda que viaja, y el resto sigue
siendo una línea recta separada por un hueco, con un punto al final. Es como lo define
`LinearWavyProgressIndicator`: **la onda solo existe en lo reproducido**.

Tres comportamientos que van de serie:

- **La onda no recorre todo lo reproducido**, solo los ~150 px anteriores al cabezal. Lo de
  más atrás va liso. Si ondulase entera, en una barra ancha de escritorio quedaría un
  garabato de quince ciclos siempre igual.
- **Se apaga justo en el cabezal.** Es lo que hace que empalme con la parte que aún no has
  escuchado: si llegase al final con amplitud, cortaría a media altura y se vería suelta.
- **En pausa se aplana** hasta quedar recta, y la animación se para del todo. No se queda
  nada girando de fondo.

El modo rendimiento la deja plana también.

### Movimiento

Bloque `movimiento`. Controla **cómo responde la interfaz cuando la tocas**: el rebote al
pulsar una tarjeta, el crecimiento al pasar el ratón por encima, cómo entra la cápsula del
menú.

No son duraciones ni curvas: son **muelles**, que es como lo hace Material 3 Expressive
desde que sustituyó su sistema de *easing* por uno de física. Un muelle se define por lo que
tarda en asentarse y por cuánto rebasa el destino antes de volver.

| Clave | Valores | Por defecto | Qué hace |
|---|---|---|---|
| `esquema` | `sobrio`, `expresivo`, `ninguno` | `sobrio` | `sobrio` se asienta sin rebasar. `expresivo` rebasa y vuelve, que es el "toque" de Material. `ninguno` lo apaga todo: los cambios son instantáneos. |
| `rebote` | 0–1 | `0.3` | Cuánto rebasa. Solo cuenta con `expresivo`. Por encima de `0.5` se vuelve caricaturesco. |
| `velocidad` | 0.5–2 | `1.0` | Multiplica la rapidez. `2` es el doble de rápido, `0.5` la mitad. |

Dos cosas que **no** se pueden tocar, a propósito:

- **Los muelles de color y opacidad nunca rebasan**, aunque pongas `expresivo`. Es la
  distinción que hace Material entre *spatial* y *effects*: una cosa que se mueve puede
  pasarse de largo y volver, pero un color que se pasa de largo es un parpadeo feo.
- **Nada se anima solo.** Todo el movimiento nace de que tú toques algo, y se para al
  asentarse. En una lista de 3.000 canciones no puede haber animaciones perpetuas — es la
  misma regla por la que el corazón de "me gusta" solo ondula mientras se llena.

El **modo rendimiento** apaga el movimiento entero, igual que apaga el cristal.

### Colores

Solo `primario` es obligatorio. Cada uno que quites se deduce de `fondo`, `texto` y `brillo`.

| Clave | Dónde se ve | Si no lo pones |
|---|---|---|
| `primario` | Botón de reproducir, barra de progreso, lo que está seleccionado, los enlaces. **Obligatorio.** | — |
| `sobrePrimario` | El texto y el icono que van **encima** del primario. | Blanco o negro, el que contraste. |
| `fondo` | El lienzo de la ventana. | `#121212` en oscuro, `#FAFAFA` en claro. |
| `superficie` | Tarjetas, diálogos, cosas elevadas sobre el fondo. | `fondo` aclarado (u oscurecido) un 6 %. |
| `panel` | La barra lateral y la barra del reproductor. | `fondo` oscurecido un 40 % en oscuro, un 6 % en claro. |
| `texto` | Todo el texto normal y los iconos. | Casi blanco o casi negro, según `brillo`. |
| `textoTenue` | Texto secundario: artistas, duraciones, ayudas. | `texto` mezclado con `fondo` al 38 %. |
| `borde` | Separadores, marcos de los campos. | `fondo` mezclado con `texto` al 16 %. |
| `error` | Fallos y avisos rojos. | Rojo según `brillo`. |

**Ojo con `panel`.** Es el único color deducido que se aleja mucho de `fondo`: por defecto la
barra lateral queda bastante más oscura que el resto, como en Spotify. Si no quieres ese
contraste, pon `panel` igual a `fondo` y punto.

#### Formatos de color aceptados

| Forma | Ejemplo |
|---|---|
| Hex de 6 | `"#1DB954"` |
| Hex de 3 | `"#F55"` → `#FF5555` |
| Hex con alfa | `"#801DB954"` (el alfa va **delante**) |
| Sin almohadilla | `"1DB954"`, `"0x1DB954"` |
| Decimal | `"29,185,84"` o `"29,185,84,128"` |

Vale mayúsculas o minúsculas. Lo que no se entienda **no tumba el tema**: se avisa en el
selector y esa clave concreta pasa a usar el valor deducido.

---

## Cristal

El bloque `cristal` convierte la barra lateral y la del reproductor en paneles translúcidos,
al estilo del [Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) que Apple
presentó en la WWDC25. Está apagado salvo que pongas `"activo": true`.

Un panel de cristal se pinta en cuatro capas, que es más o menos lo que Apple describe como
*highlight*, *shadow* e *illumination*:

1. **Desenfoque** de lo que hay detrás, con un empujón de saturación para que el color del
   fondo se note a través.
2. **Tinte**: el color `panel` a la opacidad que digas.
3. **Reflejo especular**: una banda blanca que se apaga hacia abajo, pegada al borde
   superior. Mide **72 px siempre**, mida lo que mida el panel — si fuese proporcional, en
   la barra lateral (alta y estrecha) se estiraría hasta parecer un manchón.
4. **Filo**: una línea fina y clara que recorre el borde, más brillante en las esquinas.

| Clave | Rango | Por defecto | Qué hace |
|---|---|---|---|
| `activo` | true/false | `false` | Enciende todo el bloque. |
| `desenfoque` | 0–80 | `24` | Sigma del desenfoque. **Por encima de 40 se nota en equipos sin GPU dedicada.** |
| `opacidad` | 0–1 | `0.16` | Cuánto tinte de `panel` lleva. Por encima de `0.5` deja de parecer cristal. |
| `saturacion` | 0–3 | `1.6` | `1` no toca el color; `1.6`–`2` es lo que hace que "brille". |
| `brillo` | 0–1 | `0.28` | Fuerza del reflejo especular. Con paneles grandes conviene bajarlo: el tema Liquid Glass usa `0.14`. |
| `borde` | 0–1 | `0.26` | Fuerza del filo. `0` lo quita. |
| `radio` | 0–48 | `18` | Redondeo de los paneles de cristal (independiente de `radio`). |

**El cristal necesita algo detrás que desenfocar.** Un `cristal` sin `fondo` se ve como un
panel gris translúcido sobre el color liso: correcto pero soso. Lo que le da vida es
combinarlo con `"fondo": { "usarCaratula": true }`, y entonces los paneles refractan la
portada de lo que suene.

**Cuesta GPU.** El desenfoque se recalcula en cada fotograma. NeoFy lo apaga solo cuando está
activo el **modo rendimiento** de los ajustes: en ese caso los paneles vuelven a ser opacos y
el fondo, liso. No es un fallo, es la salida de emergencia.

---

## Fondo

El bloque `fondo` pinta detrás de toda la ventana. Se pintan por capas y en este orden:
color `fondo` → `degradado` → `imagen` → `usarCaratula` → `oscurecer`.

| Clave | Rango | Por defecto | Qué hace |
|---|---|---|---|
| `imagen` | nombre de fichero | — | Relativo **a la carpeta del tema**. Ver la nota de abajo. |
| `ajuste` | `cubrir`, `contener`, `repetir`, `estirar`, `centrar` | `cubrir` | Cómo se encaja la imagen. |
| `opacidad` | 0–1 | `1` | De la imagen o la carátula, no del color. |
| `desenfoque` | 0–80 | `0` | Desenfoque del fondo. Con carátula, quieres mucho: `50`–`70`. |
| `oscurecer` | 0–1 | `0` | Un velo negro (o blanco, si el tema es claro) por encima de todo. Sube esto si el texto no se lee. |
| `usarCaratula` | true/false | `false` | Usa la portada de lo que está sonando. Cambia con cada canción, con un fundido. |
| `degradado` | lista de colores | — | Dos colores o más. Con uno solo se ignora. |
| `anguloDegradado` | -360–360 | `135` | Grados. `0` es de izquierda a derecha; `90`, de arriba abajo. |

**`imagen` no puede salir de la carpeta del tema.** Nada de `../`, ni rutas absolutas, ni
unidades. Un tema que se descarga de internet no tiene por qué poder leer tu disco, así que
NeoFy resuelve la ruta y, si acaba fuera, no la carga. La herramienta te lo marca como error.

Con `usarCaratula` puesto y sin nada sonando, el fondo se queda en el `degradado` (o en el
color liso). Deja siempre un degradado de respaldo decente: es lo que se ve al abrir la app.

---

## Tipografía

| Clave | Por defecto | Qué hace |
|---|---|---|
| `familia` | la del sistema | Nombre de la familia. |
| `ficheros` | vacío | Los `.ttf`/`.otf` de la carpeta del tema que la componen. |
| `escala` | `1.0` | Multiplica todo el texto. Se recorta a 0.7–1.6. |
| `pesoTitulos` | — | Engorda **solo** los estilos `title` y `label`, dejando el cuerpo en normal. Es lo que hace la tabla del *type scale* de Material, que les asigna Medium: los temas Material usan `600`. |

Si pones `familia` **y** adjuntas los `ficheros`, NeoFy carga la fuente al vuelo y funciona en
cualquier equipo. Si pones `familia` a secas, solo se verá bien en equipos que ya la tengan
instalada — la herramienta te avisa de eso.

Con `escala` ten cuidado: por encima de `1.2` empiezan a cortarse cosas en la barra lateral,
que tiene ancho fijo.

---

## La herramienta

```
dart run tool/tema.dart <orden>
```

| Orden | Qué hace |
|---|---|
| `nuevo <nombre>` | Crea la carpeta con el `tema.json` relleno. `--cristal` parte de la plantilla translúcida; `--en <ruta>` lo saca de la carpeta de NeoFy. |
| `validar [ruta ...]` | Repasa temas. Sin argumentos, repasa los instalados. **Sale con código 1 si hay errores**, así que sirve en un CI. |
| `listar` | Los instalados, con su paleta en la terminal. |
| `instalar <ruta>` | Copia una carpeta a la carpeta de temas. |
| `donde` | Dice dónde está la carpeta de temas. |

`validar` distingue **errores** de **avisos**. Un error es algo que no se va a cargar; un
aviso es algo que se va a cargar de otra manera de la que quizá esperabas:

```
── mi-tema
  aviso  tipogrfia: no la entiendo; se ignorará. ¿Un typo?
  error  brillo: tiene que ser "claro" u "oscuro".
  error  colores.primario: no es un color válido ("verde lima").
  aviso  cristal.desenfoque: por encima de 40 se nota en equipos sin GPU dedicada.
  error  fondo.imagen: tiene que ser una ruta relativa dentro de la carpeta del tema.

3 error(es), 2 aviso(s).
```

Caza también las claves mal escritas, que es el fallo más común y el más difícil de ver a
ojo: un `"primarioo"` no da error en ningún sitio, simplemente no hace nada.

---

## Publicar un tema

No hay tienda ni instalador: se comparte la carpeta.

1. Repasa con `dart run tool/tema.dart validar ./mi-tema` hasta que salga limpio.
2. Pruébalo en claro **y** en oscuro si tu tema toca el `brillo` — quien lo instale puede
   venir de cualquiera de los dos.
3. Sube la carpeta a un repositorio, o comprímela en un `.zip`.
4. En el LÉEME, di dónde se descomprime: `%APPDATA%\neofy\temas` en Windows,
   `~/.config/neofy/temas` en Linux.

Cosas que conviene mirar antes de publicar:

- **Contraste.** El texto sobre el fondo tiene que leerse. Los temas incluidos pasan de 7:1,
  que es el AAA de la WCAG; si el tuyo baja de 4.5:1 se lee mal en pantallas malas.
- **Peso.** Una imagen de fondo de 8 MB se carga en cada arranque. Bájala a 1080p y a JPEG.
- **El fondo con carátula puede tapar el texto.** Sube `oscurecer` hasta que se lea con una
  portada blanca, que es el peor caso.
- **Licencia de la fuente y de la imagen.** Si empaquetas una fuente, mira que puedas.

---

## Cuando algo no va

| Lo que ves | Lo que pasa |
|---|---|
| El tema no sale en la lista | No hay `tema.json` en la carpeta, o el JSON está roto. Mira el selector: lo dice con el nombre de la carpeta. |
| «El JSON no es válido (línea 8…)» | Casi siempre una coma detrás del último campo, o un comentario. En JSON no valen comentarios. |
| Sale pero con los colores por defecto | Los nombres de las claves están mal escritos. Pasa `validar`. |
| Los cambios no se aplican al guardar | El editor guarda a un fichero temporal y renombra. Toca el `tema.json` otra vez, o pulsa recargar en el selector. |
| El cristal se ve gris y plano | No hay nada detrás que desenfocar. Añade `fondo` con `degradado` o `usarCaratula`. |
| Va a tirones con el cristal | Baja `cristal.desenfoque` y `fondo.desenfoque`. O enciende el modo rendimiento, que lo apaga todo. |
| La fuente no se aplica | Falta `ficheros`, o el nombre de `familia` no es el que trae el `.ttf` por dentro. |
| Renombré la carpeta y perdí mi tema | El id cambió. Pon el id viejo en la clave `id` del `tema.json`. |

---

## Los temas incluidos

Vienen once, y sirven de referencia: **Claro**, **Oscuro**, **Verde claro**, **Verde
oscuro**, **Azul claro**, **Azul oscuro**, **Rojo claro**, **Rojo oscuro**, **Material
claro**, **Material oscuro** y **Liquid Glass**. Más la opción **Automático**, que va
cambiando entre Claro y Oscuro según lo que diga Windows o tu escritorio.

Los dos **Material** son los más interesantes para copiar, porque enseñan dos cosas que el
resto no hace:

- **La paleta no está inventada.** Sale del algoritmo de color de Google
  (`material_color_utilities`, que Flutter ya trae) con la semilla `#6750A4` de Material 3,
  así que son los tonos exactos que usan las apps de Android, con sus superficies teñidas
  de violeta (`#FDF7FF` en claro, `#141218` en oscuro).
- **En oscuro, `panel` es más claro que `fondo`**, al revés que en todos los demás. No es
  un despiste: Material marca la elevación aclarando, mientras que Spotify —y el resto de
  temas de aquí— la marca oscureciendo. El formato aguanta las dos escuelas.

Y usan `radio: 26` con `radioBoton: 999`, que es la mezcla de formas de Material 3
Expressive: contenedores muy redondeados y botones en píldora completa.

Están definidos en `lib/core/temas_incluidos.dart` con exactamente las mismas claves que
usarías tú; no hay nada que un tema de la comunidad no pueda hacer. Para partir de uno,
`dart run tool/tema.dart nuevo "..." --cristal` te da el de Liquid Glass ya montado.

---

## Lo que un tema todavía no puede hacer

Para que no pierdas el rato buscándolo:

- Mover, esconder o añadir elementos de la interfaz. No hay `user.css` ni `theme.js`.
- Cambiar los iconos.
- Poner fondos animados o vídeo.
- Tocar colores de una pantalla concreta: la paleta es global.

Si alguna te hace falta de verdad, ábre un issue en
[el repositorio](https://github.com/KOLPSE/NeoFy/issues) contando **para qué**, que es lo que
decide si merece la pena abrir esa puerta.
