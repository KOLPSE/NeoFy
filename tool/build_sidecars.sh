#!/usr/bin/env bash

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="$raiz/tool/librespot-build"
version='0.8.0'

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

echo
echo "Compilando el sidecar de metadatos..."
cargo build --release --manifest-path "$raiz/tool/metadata-sidecar/Cargo.toml"

sidecar="$raiz/tool/metadata-sidecar/target/release/metadata-sidecar"
[ -x "$sidecar" ] || { echo "La compilacion termino pero no aparece $sidecar" >&2; exit 1; }
echo "metadata-sidecar listo en $sidecar ($(du -h "$sidecar" | cut -f1))"

echo
echo "Listo. Ahora: flutter build linux --release"
