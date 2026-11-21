$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# El SDK vive fuera del directorio del repo en una ruta corta para evitar
# errores de MAX_PATH (>260 caracteres) al limpiar el workspace del runner.
$toolsDir = if ($env:NEOFY_CI_TOOLS_DIR) { $env:NEOFY_CI_TOOLS_DIR } else { 'C:\ci\flutter-3.44.6' }
$sdkRoot = Join-Path $toolsDir 'flutter'
$completed = Join-Path $toolsDir 'sdk-ready'
if (-not (Test-Path $completed)) {
  Write-Host 'Preparando Flutter 3.44.6 en el directorio del job.'
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  $manifest = Invoke-RestMethod -TimeoutSec 45 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $release = $manifest.releases | Where-Object { $_.version -eq '3.44.6' -and $_.channel -eq 'stable' } | Select-Object -First 1
  if (-not $release -or -not $release.sha256) { throw 'No se encuentra Flutter 3.44.6 en el manifiesto oficial.' }
  $archive = Join-Path $toolsDir "flutter-$env:CI_JOB_ID.zip"
  try {
    & curl.exe --fail --location --retry 3 --connect-timeout 20 --max-time 1200 --output $archive "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar el SDK de Flutter.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash -ne $release.sha256) {
      throw 'La suma de Flutter no coincide con el manifiesto oficial.'
    }
    Write-Host 'SDK descargado y verificado; extrayendo archivos.'
    & tar.exe -xf $archive -C $toolsDir
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $sdkRoot 'bin\flutter.bat'))) {
      throw 'No se pudo extraer el SDK de Flutter.'
    }
    [IO.File]::WriteAllText($completed, 'Flutter 3.44.6')
  } finally {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
  }
}
if ($env:PUB_CACHE) {
  $env:PUB_CACHE = [IO.Path]::GetFullPath($env:PUB_CACHE)
} else {
  $env:PUB_CACHE = 'C:\ci\pub-cache'
}
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE | Out-Null

# Si falta el snapshot compilado (primer uso o intento previo fallido), limpia
# el estado de flutter_tools para regenerar package_config.json con rutas válidas.
$snapshot = Join-Path $sdkRoot 'bin\cache\flutter_tools.snapshot'
if (-not (Test-Path $snapshot)) {
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'packages\flutter_tools\.dart_tool') -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter.bat.lock') -Force -ErrorAction SilentlyContinue
}

$env:PATH = "$sdkRoot\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $sdkRoot.Replace('\', '/')
& (Join-Path $sdkRoot 'bin\flutter.bat') --version
if ($LASTEXITCODE -ne 0) { throw 'Flutter no está disponible.' }
