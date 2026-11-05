$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# El SDK vive en el directorio de trabajo del runner, no en el sistema.
$toolsDir = Join-Path $env:CI_PROJECT_DIR '.ci-tools\flutter-3.44.6-tar'
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
$env:PATH = "$sdkRoot\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $sdkRoot.Replace('\', '/')
& (Join-Path $sdkRoot 'bin\flutter.bat') --version
if ($LASTEXITCODE -ne 0) { throw 'Flutter no está disponible.' }
