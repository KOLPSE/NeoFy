#!/usr/bin/env bash

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

version="$(grep -oP "kVersion\s*=\s*'\K[^']+" lib/core/app_config.dart)"
[ -n "$version" ] || { echo "No encuentro kVersion en lib/core/app_config.dart" >&2; exit 1; }
echo "NeoFy $version"

librespot='tool/librespot-build/bin/librespot'
sidecar='tool/metadata-sidecar/target/release/metadata-sidecar'
for bin in "$librespot" "$sidecar"; do
    [ -x "$bin" ] || { echo "Falta $bin. Ejecuta tool/build_sidecars.sh primero." >&2; exit 1; }
done

echo "Actualizando yt-dlp (el descodificador de la via libre)..."
bash ./tool/fetch_ytdlp.sh
[ -x 'tool/ytdlp-build/bin/yt-dlp' ] || { echo "Falta tool/ytdlp-build/bin/yt-dlp" >&2; exit 1; }

echo "Compilando la app..."
flutter build linux --release

bundle='build/linux/x64/release/bundle'
[ -d "$bundle" ] || { echo "No aparece $bundle" >&2; exit 1; }

for bin in librespot metadata-sidecar yt-dlp; do
    [ -x "$bundle/$bin" ] || { echo "El bundle no trae $bin" >&2; exit 1; }
done

cp linux/packaging/xyz.neogex.neofy.desktop "$bundle/"
cp -r linux/packaging/icons "$bundle/"
cp LICENSE "$bundle/"

mkdir -p dist
nombre="NeoFy-$version-linux-x86_64"
rm -rf "dist/$nombre" "dist/$nombre.tar.gz"
cp -r "$bundle" "dist/$nombre"

tar -czf "dist/$nombre.tar.gz" -C dist --owner=0 --group=0 "$nombre"

echo
echo "Listo: dist/$nombre.tar.gz ($(du -h "dist/$nombre.tar.gz" | cut -f1))"
echo "sha256: $(sha256sum "dist/$nombre.tar.gz" | cut -d' ' -f1)"
echo "Arbol sin comprimir en dist/$nombre/"
