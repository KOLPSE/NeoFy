$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installRoot = Join-Path $root 'tool\librespot-build'
$version = '0.8.0'

function Limpiar-CacheCargo {
  $homes = @($env:CARGO_HOME, (Join-Path $env:USERPROFILE '.cargo'), 'C:\ci\cargo') |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -Unique
  foreach ($h in $homes) {
    foreach ($sub in @('registry\cache', 'registry\src')) {
      $dir = Join-Path $h $sub
      if (Test-Path $dir) {
        Write-Host "Limpiando caché de Cargo corrupta en $dir..."
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

$argsCargo = @(
  'install', 'librespot',
  '--version', $version,
  '--locked',
  '--no-default-features',
  '--features', 'native-tls,rodio-backend',
  '--root', $installRoot
)

$prevOptLevel = $env:CARGO_PROFILE_RELEASE_OPT_LEVEL
$prevLto = $env:CARGO_PROFILE_RELEASE_LTO
$prevStrip = $env:CARGO_PROFILE_RELEASE_STRIP
$env:CARGO_PROFILE_RELEASE_OPT_LEVEL = 'z'
$env:CARGO_PROFILE_RELEASE_LTO = 'thin'
$env:CARGO_PROFILE_RELEASE_STRIP = 'symbols'

try {
  $ErrorActionPreference = 'Continue'
  & cargo @argsCargo
  $codigoCargo = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($codigoCargo -ne 0) {
    Limpiar-CacheCargo
    $ErrorActionPreference = 'Continue'
    & cargo @argsCargo
    $codigoCargo = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($codigoCargo -ne 0) { throw "Falló cargo install librespot (código $codigoCargo)" }
  }
} finally {
  $env:CARGO_PROFILE_RELEASE_OPT_LEVEL = $prevOptLevel
  $env:CARGO_PROFILE_RELEASE_LTO = $prevLto
  $env:CARGO_PROFILE_RELEASE_STRIP = $prevStrip
}

$exe = Join-Path $installRoot 'bin\librespot.exe'
if (-not (Test-Path $exe)) {
    throw "La compilacion termino pero no aparece $exe"
}

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Output "librespot $version listo en $exe ($size MB)"

Write-Output ""
Write-Output "Compilando el sidecar de metadatos..."

$manifestSidecar = Join-Path $root 'tool\metadata-sidecar\Cargo.toml'
$ErrorActionPreference = 'Continue'
& cargo build --release --manifest-path $manifestSidecar
$codigoSidecar = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($codigoSidecar -ne 0) {
  Limpiar-CacheCargo
  $ErrorActionPreference = 'Continue'
  & cargo build --release --manifest-path $manifestSidecar
  $codigoSidecar = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($codigoSidecar -ne 0) { throw "Falló cargo build metadata-sidecar (código $codigoSidecar)" }
}

$sidecarBuild = if ($env:CARGO_TARGET_DIR) {
  Join-Path $env:CARGO_TARGET_DIR 'release\metadata-sidecar.exe'
} else {
  Join-Path $root 'tool\metadata-sidecar\target\release\metadata-sidecar.exe'
}
if (-not (Test-Path $sidecarBuild)) {
    throw "La compilacion termino pero no aparece $sidecarBuild"
}

$sidecar = Join-Path $root 'tool\metadata-sidecar\target\release\metadata-sidecar.exe'
if ($env:CARGO_TARGET_DIR) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sidecar) | Out-Null
  Copy-Item $sidecarBuild $sidecar -Force
}

$sizeSidecar = [math]::Round((Get-Item $sidecar).Length / 1MB, 1)
Write-Output "metadata-sidecar listo en $sidecar ($sizeSidecar MB)"
Write-Output ""
Write-Output "Listo. Ahora: flutter build windows --release"
