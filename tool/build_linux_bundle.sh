#!/usr/bin/env bash
#
# Empaqueta NeoFy para Linux: compila la app, junta los dos sidecars y saca un
# tarball listo para el PKGBUILD del AUR.
#
#   ./tool/build_linux_bundle.sh
#
# Sale dist/NeoFy-<version>-linux-x86_64.tar.gz. Es el equivalente de
# tool/build_installer.ps1, que es el de Windows.
#
# Los sidecars tienen que estar compilados antes (tool/build_sidecars.sh);
# si falta alguno, CMake avisa pero la compilacion sigue y el tarball saldria
# incompleto, asi que aqui se comprueba y se para.

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

# La version sale de kVersion, que es la UNICA fuente de la verdad: la misma de
# la que tira el instalador de Windows y con la que compara el actualizador.
# Teniendola en dos sitios acabarian por no coincidir, y el sintoma seria una
# app ofreciendose actualizarse a si misma en bucle.
version="$(grep -oP "kVersion\s*=\s*'\K[^']+" lib/core/app_config.dart)"
[ -n "$version" ] || { echo "No encuentro kVersion en lib/core/app_config.dart" >&2; exit 1; }
echo "NeoFy $version"

librespot='tool/librespot-build/bin/librespot'
sidecar='tool/metadata-sidecar/target/release/metadata-sidecar'
for bin in "$librespot" "$sidecar"; do
    [ -x "$bin" ] || { echo "Falta $bin. Ejecuta tool/build_sidecars.sh primero." >&2; exit 1; }
done

echo "Compilando la app..."
flutter build linux --release

bundle='build/linux/x64/release/bundle'
[ -d "$bundle" ] || { echo "No aparece $bundle" >&2; exit 1; }

# CMake ya los copia por su install(PROGRAMS), pero se comprueba: un tarball sin
# librespot instala una app que no suena, y el fallo solo se ve al arrancarla.
for bin in librespot metadata-sidecar; do
    [ -x "$bundle/$bin" ] || { echo "El bundle no trae $bin" >&2; exit 1; }
done

# Los ficheros de escritorio viajan dentro del tarball para que el PKGBUILD no
# tenga que descargarlos aparte ni llevarlos duplicados en el AUR.
cp linux/packaging/xyz.neogex.neofy.desktop "$bundle/"
cp -r linux/packaging/icons "$bundle/"
cp LICENSE "$bundle/"

mkdir -p dist
nombre="NeoFy-$version-linux-x86_64"
rm -rf "dist/$nombre" "dist/$nombre.tar.gz"
cp -r "$bundle" "dist/$nombre"

# --owner/--group a root: el tarball lo desempaqueta makepkg y no tiene por que
# arrastrar el usuario con el que se compilo.
tar -czf "dist/$nombre.tar.gz" -C dist --owner=0 --group=0 "$nombre"

# La carpeta se deja a proposito: tool/build_linux_packages.sh la reutiliza para
# montar el .deb y el .rpm, y asi los tres artefactos salen exactamente del mismo
# arbol de ficheros en vez de armarlo cada uno por su cuenta.

echo
echo "Listo: dist/$nombre.tar.gz ($(du -h "dist/$nombre.tar.gz" | cut -f1))"
echo "sha256: $(sha256sum "dist/$nombre.tar.gz" | cut -d' ' -f1)"
echo "Arbol en dist/$nombre/ (lo usa build_linux_packages.sh)"
