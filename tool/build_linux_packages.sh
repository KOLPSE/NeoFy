#!/usr/bin/env bash
#
# Saca los instaladores nativos de Linux a partir del arbol que deja
# tool/build_linux_bundle.sh:
#
#   dist/neofy_<version>_amd64.deb        Debian, Ubuntu, Mint, Pop!_OS
#   dist/neofy-<version>-1.x86_64.rpm     Fedora, openSUSE, RHEL
#
#   ./tool/build_linux_bundle.sh && ./tool/build_linux_packages.sh
#
# Arch no sale de aqui: alli se instala con `sudo pacman -S neofy-bin` desde el
# repositorio propio (ver el README), y su PKGBUILD (linux/packaging/PKGBUILD),
# que lo construye el job `arch` del workflow, se baja el tarball de la release.
#
# Requiere dpkg-deb (viene en Debian y Ubuntu) y rpmbuild (paquete `rpm`).
#
# ⚠️ Los tres formatos instalan EXACTAMENTE el mismo arbol de ficheros, y a
# proposito: /opt/neofy con el bundle entero, un enlace en /usr/bin, el .desktop
# y los iconos hicolor. El bundle de Flutter no se puede repartir por /usr
# porque el ejecutable busca data/ y lib/ a su lado.

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

version="$(grep -oP "kVersion\s*=\s*'\K[^']+" lib/core/app_config.dart)"
[ -n "$version" ] || { echo "No encuentro kVersion en lib/core/app_config.dart" >&2; exit 1; }

arbol="dist/NeoFy-$version-linux-x86_64"
[ -d "$arbol" ] || { echo "Falta $arbol. Ejecuta tool/build_linux_bundle.sh primero." >&2; exit 1; }

# Un paquete sin librespot instala una app que no suena, y eso solo se descubre
# usandola: mejor que se caiga aqui. Con yt-dlp igual, pero para NeoTube.
for bin in neofy librespot metadata-sidecar yt-dlp; do
    [ -x "$arbol/$bin" ] || { echo "El arbol no trae $bin" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# El arbol tal y como queda instalado. Lo montan los dos formatos.
montar_raiz() {
    local destino="$1"
    rm -rf "$destino"
    install -dm755 "$destino/opt/neofy" "$destino/usr/bin" \
        "$destino/usr/share/applications"

    cp -r "$arbol/data" "$arbol/lib" "$destino/opt/neofy/"
    for bin in neofy librespot metadata-sidecar yt-dlp; do
        install -Dm755 "$arbol/$bin" "$destino/opt/neofy/$bin"
    done

    # El enlace es seguro: Dart resuelve Platform.resolvedExecutable al destino
    # real, asi que findBinary() sigue encontrando los sidecars en /opt.
    ln -sf /opt/neofy/neofy "$destino/usr/bin/neofy"

    install -Dm644 "$arbol/xyz.neogex.neofy.desktop" \
        "$destino/usr/share/applications/xyz.neogex.neofy.desktop"

    for tamano in 16 24 32 48 64 128 256; do
        install -Dm644 "$arbol/icons/${tamano}x${tamano}/neofy.png" \
            "$destino/usr/share/icons/hicolor/${tamano}x${tamano}/apps/neofy.png"
    done
}

mkdir -p dist
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# .deb
echo "Montando el .deb..."
deb="$tmp/deb"
montar_raiz "$deb"
install -dm755 "$deb/DEBIAN"
install -Dm644 "$arbol/LICENSE" "$deb/usr/share/doc/neofy/copyright"

# Installed-Size va en KiB y lo mira apt para avisar del espacio que hara falta.
tamano_kb="$(du -sk "$deb" | cut -f1)"

# Los nombres son los de Debian y no los de Arch: libgtk-3-0 y no gtk3,
# libpulse0 y no libpulse. libssl3 lo pide solo el sidecar de metadatos.
#
# ⚠️ Las alternativas con sufijo t64 no son adorno. Ubuntu 24.04 renombro las
# librerias que exponen time_t en su ABI (la transicion a time_t de 64 bits),
# asi que alli libgtk-3-0 se llama libgtk-3-0t64 y libssl3, libssl3t64. Sin la
# alternativa, el paquete instala en Debian 12 pero es imposible de instalar en
# la Ubuntu mas usada, y el error habla de dependencias inexistentes sin
# explicar por que.
cat > "$deb/DEBIAN/control" <<EOF
Package: neofy
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Depends: libgtk-3-0 | libgtk-3-0t64, libayatana-appindicator3-1, libpulse0, libssl3 | libssl3t64, xdg-utils, python3 (>= 3.9), libwebkit2gtk-4.1-0
Installed-Size: $tamano_kb
Maintainer: KOLPSE <117825722+KOLPSE@users.noreply.github.com>
Homepage: https://github.com/KOLPSE/NeoFy
Description: Cliente de Spotify ligero y nativo
 NeoFy reproduce Spotify en unos 150 MB de memoria, frente a los 400-700 MB
 del cliente oficial, porque no lleva navegador embebido: el audio va por
 librespot y todo lo demas por la Web API oficial.
 .
 Necesita una cuenta Spotify Premium y un Client ID propio, que la aplicacion
 pide la primera vez que se abre.
EOF

# Actualizar las cachés del escritorio. Sin esto, el lanzador puede tardar en
# aparecer o salir sin icono hasta el siguiente reinicio de sesión.
cat > "$deb/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
    update-desktop-database -q /usr/share/applications || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
fi
EOF
cp "$deb/DEBIAN/postinst" "$deb/DEBIAN/postrm"
chmod 755 "$deb/DEBIAN/postinst" "$deb/DEBIAN/postrm"

# --root-owner-group evita que el paquete arrastre el usuario que lo compilo,
# que en un runner de CI seria "runner" y en local el tuyo.
dpkg-deb --build --root-owner-group "$deb" "dist/neofy_${version}_amd64.deb" > /dev/null
echo "  dist/neofy_${version}_amd64.deb"

# ---------------------------------------------------------------------------
# .rpm
echo "Montando el .rpm..."
rpmroot="$tmp/rpmbuild"
install -dm755 "$rpmroot"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
montar_raiz "$tmp/rpm"

# AutoReqProv desactivado a proposito. Con el puesto, rpmbuild leeria los ELF
# del bundle y generaria Requires de las propias librerias que el paquete trae
# dentro (libflutter_linux_gtk.so y las de los plugins), que no existen como
# paquete en ninguna distribucion: el rpm quedaria imposible de instalar.
#
# ⚠️ Dentro del %install NO valen rutas relativas. El scriptlet no corre en la
# raiz del proyecto sino en el directorio de trabajo de rpmbuild, asi que un
# "dist/NeoFy-.../LICENSE" resuelve contra otro sitio y falla con un
# "cannot stat" que no menciona el directorio por ningun lado. De ahi el $raiz.
cat > "$rpmroot/SPECS/neofy.spec" <<EOF
# rpmbuild pasa por defecto un strip a todo binario que encuentra. Aqui sobra y
# ademas es arriesgado: la libreria AOT que genera Flutter no gana nada con ello
# y no hay motivo para tocar unos binarios que ya vienen compilados.
%define __os_install_post %{nil}

Name:           neofy
Version:        $version
Release:        1
Summary:        Cliente de Spotify ligero y nativo
License:        MIT
URL:            https://github.com/KOLPSE/NeoFy
BuildArch:      x86_64
AutoReqProv:    no
Requires:       gtk3, libayatana-appindicator-gtk3, pulseaudio-libs, openssl-libs, python3 >= 3.9, webkit2gtk4.1

%description
NeoFy reproduce Spotify en unos 150 MB de memoria, frente a los 400-700 MB del
cliente oficial, porque no lleva navegador embebido: el audio va por librespot
y todo lo demas por la Web API oficial.

Necesita una cuenta Spotify Premium y un Client ID propio, que la aplicacion
pide la primera vez que se abre.

%install
mkdir -p %{buildroot}
cp -a $tmp/rpm/. %{buildroot}/
install -Dm644 $raiz/$arbol/LICENSE %{buildroot}/usr/share/licenses/neofy/LICENSE

%post
update-desktop-database -q /usr/share/applications 2>/dev/null || :
gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || :

%postun
update-desktop-database -q /usr/share/applications 2>/dev/null || :
gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || :

%files
/opt/neofy
/usr/bin/neofy
/usr/share/applications/xyz.neogex.neofy.desktop
/usr/share/icons/hicolor/*/apps/neofy.png
%license /usr/share/licenses/neofy/LICENSE
EOF

# --define para no escribir en el ~/rpmbuild del usuario ni en /usr/src.
rpmbuild -bb "$rpmroot/SPECS/neofy.spec" \
    --define "_topdir $rpmroot" \
    --define "_build_id_links none" \
    --quiet
cp "$rpmroot/RPMS/x86_64/neofy-$version-1.x86_64.rpm" dist/
echo "  dist/neofy-$version-1.x86_64.rpm"

echo
for f in "dist/neofy_${version}_amd64.deb" "dist/neofy-$version-1.x86_64.rpm"; do
    echo "$(du -h "$f" | cut -f1)	$(basename "$f")"
    echo "	sha256: $(sha256sum "$f" | cut -d' ' -f1)"
done
