$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installRoot = Join-Path $root 'tool\librespot-build'
$version = '0.8.0'

cargo install librespot `
    --version $version `
    --locked `
    --no-default-features `
    --features native-tls,rodio-backend `
    --root $installRoot

$exe = Join-Path $installRoot 'bin\librespot.exe'
if (-not (Test-Path $exe)) {
    throw "La compilacion termino pero no aparece $exe"
}

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Output "librespot $version listo en $exe ($size MB)"

Write-Output ""
Write-Output "Compilando el sidecar de metadatos..."

cargo build --release --manifest-path (Join-Path $root 'tool\metadata-sidecar\Cargo.toml')

$sidecar = Join-Path $root 'tool\metadata-sidecar\target\release\metadata-sidecar.exe'
if (-not (Test-Path $sidecar)) {
    throw "La compilacion termino pero no aparece $sidecar"
}

$sizeSidecar = [math]::Round((Get-Item $sidecar).Length / 1MB, 1)
Write-Output "metadata-sidecar listo en $sidecar ($sizeSidecar MB)"
Write-Output ""
Write-Output "Listo. Ahora: flutter build windows --release"
