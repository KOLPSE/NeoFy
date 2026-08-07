#!/usr/bin/env bash
#
# Compila los dos sidecars de Rust y los deja donde la app los busca.
# Equivalente de tool/build_librespot.ps1, que es el de Windows.
#
# Solo hay que ejecutarlo una vez (o al cambiar de version de librespot); los
# binarios se versionan fuera del repo y CMake los copia al bundle de release,
# junto al ejecutable de la app.
#
#   ./tool/build_sidecars.sh
#
# Requiere el toolchain de Rust, pkg-config, las cabeceras de PulseAudio y las
# de OpenSSL:
#
#   Arch:   sudo pacman -S --needed rust pkgconf libpulse openssl
#   Debian: sudo apt install -y cargo pkg-config libpulse-dev libssl-dev
#
# ⚠️ OpenSSL lo pide **solo el sidecar de metadatos**: librespot se compila aqui
# con rustls (ver mas abajo), pero librespot-core, que el sidecar usa como
# libreria, arrastra native-tls por sus features por defecto. Se deja asi a
# proposito: cambiarlo obliga a regenerar el Cargo.lock, que es compartido con
# la compilacion de Windows y ahi funciona. El acoplamiento es tolerable porque
# se queda en el soname (libssl.so.3 tanto en Debian como en Arch), pero por eso
# el PKGBUILD lleva `openssl` en depends.

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="$raiz/tool/librespot-build"
version='0.8.0'

# Dos diferencias con la receta de Windows, y las dos importan:
#
# 1. TLS por rustls y no por native-tls. En Windows native-tls va por schannel y
#    no arrastra nada; aqui iria por OpenSSL y ataria el binario a la version
#    exacta de libssl de la maquina donde se compilo. Como este binario acaba en
#    un paquete -bin que se instala en equipos ajenos, eso es justo lo que no
#    queremos: con rustls las raices se leen del sistema y el binario es
#    portable entre distribuciones.
#
# 2. Backend de PulseAudio en vez de rodio. PipeWire lo expone por su shim y
#    **mueve el flujo solo** cuando cambia el altavoz, que es el fallo que en
#    Windows hay que vigilar a mano con un IMMNotificationClient.
#
# --no-default-features quita 'with-libmdns' (descubrimiento por mDNS), que no
# usamos porque arrancamos con --disable-discovery.
echo "Compilando librespot $version..."
cargo install librespot \
    --version "$version" \
    --locked \
    --no-default-features \
    --features rustls-tls-native-roots,pulseaudio-backend \
    --root "$destino"

bin="$destino/bin/librespot"
[ -x "$bin" ] || { echo "La compilacion termino pero no aparece $bin" >&2; exit 1; }
echo "librespot $version listo en $bin ($(du -h "$bin" | cut -f1))"

# ---------------------------------------------------------------------------
# Sidecar de metadatos: lee por el protocolo interno de Spotify el contenido de
# las playlists ajenas, que la Web API deniega con 403 estando en Modo
# Desarrollo. Sin el, la app funciona igual salvo esas playlists.
echo
echo "Compilando el sidecar de metadatos..."
cargo build --release --manifest-path "$raiz/tool/metadata-sidecar/Cargo.toml"

sidecar="$raiz/tool/metadata-sidecar/target/release/metadata-sidecar"
[ -x "$sidecar" ] || { echo "La compilacion termino pero no aparece $sidecar" >&2; exit 1; }
echo "metadata-sidecar listo en $sidecar ($(du -h "$sidecar" | cut -f1))"

echo
echo "Listo. Ahora: flutter build linux --release"
