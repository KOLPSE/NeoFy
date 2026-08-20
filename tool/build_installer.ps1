

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Paso($texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }

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

$ytdlp = "tool\ytdlp-build\bin\yt-dlp.exe"
Paso "Actualizando yt-dlp (el descodificador de la via libre)"
& powershell -ExecutionPolicy Bypass -File tool\fetch_ytdlp.ps1
if ($LASTEXITCODE -ne 0) { throw "Falló la descarga de yt-dlp" }
if (-not (Test-Path $ytdlp)) { throw "No se encuentra $ytdlp" }

Paso "Compilando NeoFy"
foreach ($n in @('neofy', 'librespot', 'metadata-sidecar', 'yt-dlp')) {
  Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force
}

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and $env:FLUTTER_ROOT) {
  $candidato = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
  if (Test-Path $candidato) { $flutter = $candidato }
}
if (-not $flutter) {
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

Paso "Copiando los sidecars junto al ejecutable"
Copy-Item $librespot $release -Force
Copy-Item $sidecar   $release -Force
Copy-Item $ytdlp     $release -Force
foreach ($n in @('librespot.exe', 'metadata-sidecar.exe', 'yt-dlp.exe')) {
  if (-not (Test-Path (Join-Path $release $n))) { throw "No llegó $n al Release" }
}
Get-ChildItem $release -Filter *.exe | ForEach-Object {
  "  {0,-24} {1,7:N1} MB" -f $_.Name, ($_.Length / 1MB)
}

Paso "Generando el instalador"
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
  throw "Falta Inno Setup 6. Instálalo con: winget install JRSoftware.InnoSetup"
}

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
