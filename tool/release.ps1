# Publica una versión de NeoFy: comprueba, compila, etiqueta y sube la release.
#
#   powershell -ExecutionPolicy Bypass -File tool\release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\release.ps1 -Notas notas.md
#   powershell -ExecutionPolicy Bypass -File tool\release.ps1 -Ensayo
#
# Antes de ejecutarlo, sube la versión en UN sitio: `kVersion` en
# lib/core/app_config.dart. De ahí salen el instalador y el actualizador.
#
# El token de GitHub se toma del gestor de credenciales de Windows (el mismo que
# usa `git push`), o de $env:GITHUB_TOKEN si está definido. No hay que guardar
# ninguna credencial en el proyecto.

param(
  # Fichero markdown con las notas. Si no se da, se generan con los commits
  # desde la última etiqueta.
  [string]$Notas,
  # Lo comprueba todo y compila, pero no etiqueta ni publica nada.
  [switch]$Ensayo
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Paso($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Mal($t)  { throw $t }

# --- 1. Que el repositorio esté en condiciones -----------------------------
Paso 'Comprobando el repositorio'

if ((git status --porcelain).Length -gt 0) {
  # ⚠️ Los paréntesis son obligatorios. `Mal 'a' + 'b'` no concatena: al llamar
  # a una función, PowerShell lee los argumentos en modo comando y `+ 'b'` pasa
  # como argumentos sueltos que se descartan, dejando el mensaje a medias.
  Mal ('Hay cambios sin confirmar. Publica desde un árbol limpio: lo que se ' +
       'etiqueta tiene que ser exactamente lo que se compila.')
}
$rama = git rev-parse --abbrev-ref HEAD
if ($rama -ne 'main') { Mal "Estás en '$rama'. Las releases salen de main." }

git fetch origin --quiet
$local  = git rev-parse main
$remoto = git rev-parse origin/main
if ($local -ne $remoto) {
  Mal 'main y origin/main no coinciden. Haz push (o pull) antes de publicar.'
}
Write-Host '  árbol limpio, en main y sincronizado'

# El token se pide AQUÍ y no cuando hace falta, que es al final.
#
# ⚠️ Esto arregla un fallo que pasó de verdad. Estaba justo antes de crear la
# release, o sea **después** de haber etiquetado y subido la etiqueta: cuando la
# credencial no se pudo leer, el script murió dejando `v0.1.3` publicada y
# ninguna release detrás. Y volver a ejecutarlo tampoco arreglaba nada, porque
# lo primero que comprueba es que la etiqueta no exista. Había que terminar a
# mano por la API.
#
# Pidiéndolo entre las comprobaciones previas, un token que falta o que no se
# puede leer para el script antes de tocar nada irreversible.
$token = $env:GITHUB_TOKEN
if (-not $token) {
  # El mismo token que usa git push, sin guardar nada en el proyecto.
  $token = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
           Where-Object { $_ -like 'password=*' } |
           ForEach-Object { $_.Substring(9) }
}
if (-not $token) {
  Mal ('No hay token de GitHub. Guarda la credencial haciendo un `git push`, ' +
       'o define $env:GITHUB_TOKEN antes de ejecutar esto.')
}
Write-Host '  token de GitHub disponible'

# --- 2. Que el código esté sano --------------------------------------------
Paso 'analyze y tests'
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and $env:FLUTTER_ROOT) {
  $flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
}
if (-not $flutter) { Mal 'No encuentro Flutter (PATH o FLUTTER_ROOT).' }

& $flutter analyze
if ($LASTEXITCODE -ne 0) { Mal 'analyze ha encontrado problemas.' }
& $flutter test
if ($LASTEXITCODE -ne 0) { Mal 'Hay tests en rojo.' }

# --- 3. La versión ----------------------------------------------------------
Paso 'Versión'
$fuente = Get-Content 'lib\core\app_config.dart' -Raw
if ($fuente -notmatch "kVersion\s*=\s*'([^']+)'") {
  Mal 'No encuentro kVersion en lib\core\app_config.dart'
}
$version = $Matches[1]
$tag = "v$version"
Write-Host "  $tag (de kVersion)"

# Reetiquetar una versión ya publicada rompe a quien ya la tenga: el
# actualizador se fía del número, no del contenido.
$existe = git tag -l $tag
if ($existe) { Mal "La etiqueta $tag ya existe. Sube kVersion antes de publicar." }

# --- 4. El instalador -------------------------------------------------------
Paso 'Compilando el instalador'
& powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
if ($LASTEXITCODE -ne 0) { Mal 'Falló la compilación del instalador.' }

$exe = "dist\NeoFy-$version-windows-x64.exe"
if (-not (Test-Path $exe)) { Mal "No se generó $exe" }
Write-Host ('  {0}  ({1:N1} MB)' -f $exe, ((Get-Item $exe).Length / 1MB))

# --- 5. Las notas -----------------------------------------------------------
Paso 'Notas de la versión'
if ($Notas) {
  if (-not (Test-Path $Notas)) { Mal "No existe $Notas" }
  # -Encoding UTF8 no es opcional: sin el, PowerShell 5.1 lee un fichero UTF-8
  # sin BOM como ANSI, y las notas se publican con los acentos rotos
  # ("Se acabo" sale como "Se acabÃ³") porque luego se vuelven a codificar.
  #
  # ⚠️ Y el [string] tampoco. `Get-Content -Raw` no devuelve una cadena pelada
  # sino una **decorada** con PSPath, PSProvider y compañía; ConvertTo-Json
  # serializa entonces el objeto entero y GitHub rechaza la release con un 422
  # "properties/body ... is not a string" que no menciona a Get-Content por
  # ningún lado. Pasó publicando la 0.1.4, con la etiqueta ya subida.
  $cuerpo = [string](Get-Content $Notas -Raw -Encoding UTF8)
} else {
  $ultima = git describe --tags --abbrev=0 2>$null
  $rango = if ($ultima) { "$ultima..HEAD" } else { 'HEAD' }
  $cuerpo = "## Cambios`n`n" + ((git log $rango --format='- %s') -join "`n")
  Write-Host '  generadas desde los commits (usa -Notas para escribirlas a mano)'
}
Write-Host ($cuerpo -split "`n" | Select-Object -First 6 | ForEach-Object { "  | $_" })

if ($Ensayo) {
  Paso 'Ensayo: no se ha etiquetado ni publicado nada'
  exit 0
}

# --- 6. Etiquetar y publicar ------------------------------------------------
Paso 'Etiquetando'
git tag -a $tag -m "NeoFy $version"
git push origin $tag
Write-Host "  $tag subida"

Paso 'Creando la release'
# El token ya se comprobó al principio, antes de etiquetar.
$cabeceras = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json' }
$cuerpoJson = @{ tag_name = $tag; name = "NeoFy $version"; body = $cuerpo
                 draft = $false; prerelease = $false } | ConvertTo-Json

$release = Invoke-RestMethod -Method Post -Headers $cabeceras `
  -Uri 'https://api.github.com/repos/KOLPSE/NeoFy/releases' `
  -Body ([System.Text.Encoding]::UTF8.GetBytes($cuerpoJson)) -ContentType 'application/json'
Write-Host "  $($release.html_url)"

Paso 'Subiendo el instalador'
$subida = $release.upload_url -replace '\{.*$', ''
$asset = Invoke-RestMethod -Method Post -Headers $cabeceras `
  -Uri "${subida}?name=$(Split-Path $exe -Leaf)" `
  -InFile $exe -ContentType 'application/octet-stream'
Write-Host ('  {0}  {1:N1} MB  {2}' -f $asset.name, ($asset.size / 1MB), $asset.state)

# --- 7. Comprobar que se puede descargar ------------------------------------
Paso 'Verificando'
$r = Invoke-WebRequest -Method Head -Uri $asset.browser_download_url -UseBasicParsing
Write-Host "  descarga pública: HTTP $($r.StatusCode)"
Write-Host "`nPublicada NeoFy $version" -ForegroundColor Green
Write-Host 'Quien tenga una versión anterior la verá en Ajustes.'
Write-Host ''
Write-Host 'Los instaladores de Linux (.deb y .rpm) los añade GitHub Actions a esta misma' -ForegroundColor Yellow
Write-Host 'release y tardan unos veinte minutos: el workflow "Linux" se dispara solo al' -ForegroundColor Yellow
Write-Host 'publicarla. La release queda incompleta hasta que termine.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Cuando acabe, para actualizar el AUR: coge el sha256 del tarball que imprime el'
Write-Host 'workflow, ponlo en linux/packaging/PKGBUILD junto con el pkgver y sube el'
Write-Host 'PKGBUILD y su .SRCINFO al repositorio de neofy-bin.'
