#!/usr/bin/env bash
#
# Descarga el binario de yt-dlp y lo deja donde la app lo busca.
# Equivalente de tool/fetch_ytdlp.ps1, que es el de Windows.
#
# A diferencia de librespot, yt-dlp no se compila: es Python empaquetado como
# binario independiente por el propio proyecto, asi que basta con bajar el
# ultimo release. Hay que repetir este paso de vez en cuando -YouTube rompe
# extractores sin aviso y yt-dlp se actualiza para seguirle el paso-, no es
# un "una vez y ya" como librespot.
#
#   ./tool/fetch_ytdlp.sh

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="$raiz/tool/ytdlp-build/bin"
mkdir -p "$destino"

bin="$destino/yt-dlp"
# ⚠️ El asset `yt-dlp` es el **zipapp** (3 MB) y necesita python3 >= 3.9 en el
# sistema; `yt-dlp_linux` seria autonomo pero pesa 40 MB. Se empaqueta el
# primero a proposito: son 40 MB menos en cada .deb, .rpm, tarball y paquete de
# Arch, y python3 esta en cualquier escritorio actual. Por eso los tres
# paquetes lo declaran en sus dependencias; si se cambia por el autonomo, hay
# que quitarlas.
url='https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp'

echo "Descargando yt-dlp desde $url ..."
curl -L --fail -o "$bin" "$url"
chmod +x "$bin"

[ -x "$bin" ] || { echo "La descarga termino pero no aparece $bin" >&2; exit 1; }
echo "yt-dlp listo en $bin ($(du -h "$bin" | cut -f1))"
echo
echo "Listo. Ahora: flutter build linux --release"
