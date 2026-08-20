

param(
  [string]$Notas,
  [switch]$Ensayo
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Paso($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Mal($t)  { throw $t }

Paso 'Comprobando el repositorio'

if ((git status --porcelain).Length -gt 0) {
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

$token = $env:GITHUB_TOKEN
if (-not $token) {
  $peticion = Join-Path ([System.IO.Path]::GetTempPath()) "neofy-credencial-$PID.txt"
  try {
    [System.IO.File]::WriteAllBytes(
      $peticion,
      [System.Text.Encoding]::ASCII.GetBytes("protocol=https`nhost=github.com`n`n"))
    $token = cmd /c "git credential fill < `"$peticion`"" |
             Where-Object { $_ -like 'password=*' } |
             Select-Object -First 1
    if ($token) { $token = $token.Substring(9).Trim() }
  } finally {
    Remove-Item $peticion -Force -ErrorAction SilentlyContinue
  }
}
if (-not $token) {
  Mal ('No hay token de GitHub. Guarda la credencial haciendo un `git push`, ' +
       'o define $env:GITHUB_TOKEN antes de ejecutar esto.')
}
Write-Host '  token de GitHub disponible'

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

Paso 'Versión'
$fuente = Get-Content 'lib\core\app_config.dart' -Raw
if ($fuente -notmatch "kVersion\s*=\s*'([^']+)'") {
  Mal 'No encuentro kVersion en lib\core\app_config.dart'
}
$version = $Matches[1]
$tag = "v$version"
Write-Host "  $tag (de kVersion)"

$existe = git tag -l $tag
if ($existe) { Mal "La etiqueta $tag ya existe. Sube kVersion antes de publicar." }

Paso 'Compilando el instalador'
& powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
if ($LASTEXITCODE -ne 0) { Mal 'Falló la compilación del instalador.' }

$exe = "dist\NeoFy-$version-windows-x64.exe"
if (-not (Test-Path $exe)) { Mal "No se generó $exe" }
Write-Host ('  {0}  ({1:N1} MB)' -f $exe, ((Get-Item $exe).Length / 1MB))

Paso 'Notas de la versión'
if ($Notas) {
  if (-not (Test-Path $Notas)) { Mal "No existe $Notas" }
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

Paso 'Etiquetando'
git tag -a $tag -m "NeoFy $version"
git push origin $tag
Write-Host "  $tag subida"

Paso 'Creando la release'
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

Paso 'Verificando'
$r = Invoke-WebRequest -Method Head -Uri $asset.browser_download_url -UseBasicParsing
Write-Host "  descarga pública: HTTP $($r.StatusCode)"
Write-Host "`nPublicada NeoFy $version" -ForegroundColor Green
Write-Host 'Quien tenga una versión anterior la verá en Ajustes.'
Write-Host ''
Write-Host 'El tarball y el paquete de Arch los añade GitHub Actions a esta misma release' -ForegroundColor Yellow
Write-Host 'y tardan unos veinte minutos: el workflow "Linux" se dispara solo al publicarla.' -ForegroundColor Yellow
Write-Host 'La release queda incompleta hasta que termine (faltan 2 de los 3 artefactos).' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Cuando acabe: coge el sha256 del tarball que imprime el workflow y ponlo en'
Write-Host 'linux/packaging/PKGBUILD junto con el pkgver. Los usuarios de Arch no tienen que'
Write-Host 'hacer nada: el repositorio pacman propio se actualiza en el mismo workflow.'
