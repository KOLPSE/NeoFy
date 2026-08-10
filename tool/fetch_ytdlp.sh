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
# ⚠️ Se baja `yt-dlp_linux`, el binario AUTONOMO (unos 40 MB), y no el asset
# `yt-dlp`, que es el zipapp (3 MB) y necesita un python3 >= 3.9 en el sistema.
#
# Lo era al reves hasta la 0.2.4, para ahorrar 40 MB en cada artefacto. El
# problema no es el tamano sino que NeoTube dejaba de reproducir en cuanto el
# interprete no estaba o era viejo, y eso es una dependencia que el usuario
# tiene que entender y resolver antes de que la app le sirva. El autonomo trae
# su propio Python dentro: ni los paquetes lo declaran ni hay nada que instalar.
#
# Si alguna vez se vuelve al zipapp, hay que devolver `python3 >= 3.9` a los
# tres paquetes (.deb, .rpm y PKGBUILD).
url='https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux'

echo "Descargando yt-dlp desde $url ..."
curl -L --fail -o "$bin" "$url"
chmod +x "$bin"

[ -x "$bin" ] || { echo "La descarga termino pero no aparece $bin" >&2; exit 1; }
echo "yt-dlp listo en $bin ($(du -h "$bin" | cut -f1))"
echo
echo "Listo. Ahora: flutter build linux --release"
