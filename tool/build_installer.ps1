# Compila NeoFy entero y lo empaqueta en un instalador único.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
#
# Deja en dist\ un solo .exe con la interfaz, librespot y el sidecar de
# metadatos dentro. Es lo que hay que subir a GitHub Releases.
#
# Requiere Inno Setup 6:  winget install JRSoftware.InnoSetup

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Paso($texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }

# --- 1. Los sidecars -------------------------------------------------------
# Se compilan una vez y se quedan cacheados; build_librespot.ps1 ya lo detecta.
$librespot = "tool\librespot-build\bin\librespot.exe"
$sidecar   = "tool\metadata-sidecar\target\release\metadata-sidecar.exe"

if (-not (Test-Path $librespot) -or -not (Test-Path $sidecar)) {
  Paso "Compilando los sidecars (solo la primera vez, tarda un rato)"
  & powershell -ExecutionPolicy Bypass -File tool\build_librespot.ps1
  if ($LASTEXITCODE -ne 0) { throw "Falló la compilación de los sidecars" }
}
foreach ($f in @($librespot, $sidecar)) {
  if (-not (Test-Path $f)) { throw "No se encuentra $f" }
}

# --- 2. La app -------------------------------------------------------------
Paso "Compilando NeoFy"
# Con la app abierta, el enlazador no puede escribir el .exe.
foreach ($n in @('neofy', 'librespot', 'metadata-sidecar')) {
  Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force
}

# Flutter sale del PATH, no de una ruta fija: cada uno lo tiene donde le cabe,
# y una ruta absoluta aquí hace que el script solo funcione en un equipo.
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and $env:FLUTTER_ROOT) {
  $candidato = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
  if (Test-Path $candidato) { $flutter = $candidato }
}
if (-not $flutter) {
  # Sitios habituales, por si alguien no lo tiene en el PATH. Ninguna ruta
  # personal: para eso está FLUTTER_ROOT.
  foreach ($c in @('C:\src\flutter\bin\flutter.bat',
                   'C:\flutter\bin\flutter.bat',
                   "$env:LOCALAPPDATA\flutter\bin\flutter.bat")) {
    if (Test-Path $c) { $flutter = $c; break }
  }
}
if (-not $flutter) {
  throw 'No encuentro Flutter. Añádelo al PATH o define FLUTTER_ROOT con la ' +
        'carpeta donde lo tengas (la que contiene bin\flutter.bat).'
}
& $flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Falló la compilación de Flutter" }

$release = "build\windows\x64\runner\Release"

# --- 3. Juntarlo todo ------------------------------------------------------
Paso "Copiando los sidecars junto al ejecutable"
Copy-Item $librespot $release -Force
Copy-Item $sidecar   $release -Force
Get-ChildItem $release -Filter *.exe | ForEach-Object {
  "  {0,-24} {1,7:N1} MB" -f $_.Name, ($_.Length / 1MB)
}

# --- 4. El instalador ------------------------------------------------------
Paso "Generando el instalador"
# winget lo instala por usuario si no hay permisos de administrador, así que
# hay que mirar también en %LOCALAPPDATA%.
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
  throw "Falta Inno Setup 6. Instálalo con: winget install JRSoftware.InnoSetup"
}

# La versión sale de `kVersion` en app_config.dart y no del .iss: es la misma
# constante que usa el actualizador para decidir si hay algo más nuevo, así que
# teniéndola en dos sitios acabarían por no coincidir.
$fuente = Get-Content "lib\core\app_config.dart" -Raw
if ($fuente -notmatch "kVersion\s*=\s*'([^']+)'") {
  throw "No encuentro kVersion en lib\core\app_config.dart"
}
$version = $Matches[1]
Write-Host "  version: $version (leída de app_config.dart)"

New-Item -ItemType Directory -Force -Path dist | Out-Null
& $iscc /Q "/DVersion=$version" "installer\neofy.iss"
if ($LASTEXITCODE -ne 0) { throw "ISCC falló" }

Paso "Listo"
Get-ChildItem dist -Filter *.exe | ForEach-Object {
  "  {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB)
}
