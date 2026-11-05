#!/usr/bin/env bash
# Crea un AppImage a partir del bundle Flutter compilado para Linux x86_64.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(sed -n "s/^const String kVersion = '\([^']*\)';/\1/p" lib/core/app_config.dart)"
bundle="build/linux/x64/release/bundle"
[ -x "$bundle/neofy" ] && [ -n "$version" ] || { echo 'Falta el bundle Linux o la versión' >&2; exit 1; }
cache="${APPIMAGE_TOOL_CACHE:-$PWD/tool/.appimage-cache}"
mkdir -p "$cache" dist
linuxdeploy="$cache/linuxdeploy-x86_64.AppImage"
if [ ! -x "$linuxdeploy" ]; then
  curl -fsSL --retry 3 -o "$linuxdeploy" https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x "$linuxdeploy"
fi
appdir="$PWD/dist/NeoFy.AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/lib"
cp -a "$bundle/." "$appdir/usr/bin/"
# linuxdeploy excluye estas bibliotecas por defecto, pero libmpv las necesita
# incluso en escritorios que no ejecutan JACK o PipeWire.
for name in libjack.so.0 libpipewire-0.3.so.0; do
  path="$(ldconfig -p | awk -v name="$name" '$1 == name {path=$NF} END {print path}')"
  [ -n "$path" ] || { echo "Falta $name para el AppImage" >&2; exit 1; }
  cp -L "$path" "$appdir/usr/lib/$name"
done
cat > "$PWD/dist/neofy-appimage.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=NeoFy
Comment=Reproductor de música
Exec=neofy
Icon=neofy
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=xyz.neogex.neofy
DESKTOP

# linuxdeploy recopila dependencias ELF; las bibliotecas del bundle permanecen
# junto al ejecutable para que Flutter y sus sidecars las encuentren.
export APPIMAGE_EXTRACT_AND_RUN=1
export ARCH=x86_64
export OUTPUT="$PWD/dist/NeoFy-$version-linux-x86_64.AppImage"
mpv="$(ldconfig -p | awk '/libmpv\.so\.2 / {path=$NF} END {print path}')"
[ -n "$mpv" ] || { echo 'Falta libmpv2 para el AppImage' >&2; exit 1; }
"$linuxdeploy" --appdir "$appdir" --desktop-file "$PWD/dist/neofy-appimage.desktop" \
  --icon-file "$PWD/linux/packaging/icons/256x256/neofy.png" --executable "$appdir/usr/bin/neofy" \
  --executable "$appdir/usr/bin/librespot" \
  --executable "$appdir/usr/bin/metadata-sidecar" --library "$mpv" --output appimage
chmod +x "$OUTPUT"
sha256sum "$OUTPUT"
