# Compila librespot y lo deja donde la app lo busca.
#
# Solo hay que ejecutarlo una vez (o al cambiar de version de librespot); el
# binario resultante se versiona fuera del repo y CMake lo copia al bundle de
# release, junto al ejecutable de la app.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_librespot.ps1
#
# Requiere el toolchain de Rust MSVC y las Build Tools de Visual Studio.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$installRoot = Join-Path $root 'tool\librespot-build'
$version = '0.8.0'

# --no-default-features quita 'with-libmdns' (descubrimiento por mDNS), que no
# usamos porque arrancamos con --disable-discovery. Hay que dejar 'native-tls'
# explicitamente: sin ninguna feature de TLS, librespot-oauth no compila. En
# Windows native-tls va por schannel, asi que no hace falta nada mas instalado.
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

# --------------------------------------------------------------------------
# Sidecar de metadatos: lee por el protocolo interno de Spotify el contenido de
# las playlists ajenas, que la Web API deniega con 403 estando en Modo
# Desarrollo. Sin el, la app funciona igual salvo esas playlists.
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
