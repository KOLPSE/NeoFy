#!/usr/bin/env bash

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="$raiz/tool/ytdlp-build/bin"
mkdir -p "$destino"

bin="$destino/yt-dlp"
url='https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux'

echo "Descargando yt-dlp desde $url ..."
curl -L --fail -o "$bin" "$url"
chmod +x "$bin"

[ -x "$bin" ] || { echo "La descarga termino pero no aparece $bin" >&2; exit 1; }
echo "yt-dlp listo en $bin ($(du -h "$bin" | cut -f1))"
echo
echo "Listo. Ahora: flutter build linux --release"
