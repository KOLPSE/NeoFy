# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "neofy")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
#
# Tiene que coincidir con el nombre del fichero .desktop y con su StartupWMClass
# (linux/packaging/neofy.desktop). Si no, el escritorio no asocia la ventana con
# su lanzador: sale con icono generico y no se puede anclar a la barra.
set(APPLICATION_ID "xyz.neogex.neofy")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# ⚠️ Sin esto, NeoFy no compila en Arch (ni en ninguna distro con
# libayatana-appindicator >= 0.6): tray_manager llama a `app_indicator_new`, que
# esas cabeceras marcan como obsoleta, y el `-Werror` de APPLY_STANDARD_SETTINGS
# —que se aplica también a los plugins, como avisa su propio comentario— la
# convierte en error duro y tumba el build entero.
#
# El CI no lo ve porque el job `compilar` va sobre Ubuntu, cuyas cabeceras son
# más antiguas y todavía no la marcan. O sea que esto solo revienta al compilar
# en local sobre Arch, que es justo donde se compila ahora.
#
# Se acota al target del plugin en vez de tocar APPLY_STANDARD_SETTINGS: el
# código propio del runner tiene que seguir fallando si usa algo obsoleto. Y va
# `-Wno-error=` (no `-Wno-`) para que el aviso se siga viendo; es deuda del
# plugin, no nuestra, pero conviene enterarse el día que desaparezca la función.
#
# El orden importa: esta opción se añade DESPUÉS del `-Werror` del target, y en
# clang/gcc la última que toca un diagnóstico es la que manda. Al revés no haría
# nada.
if(TARGET tray_manager_plugin)
  target_compile_options(tray_manager_plugin PRIVATE -Wno-error=deprecated-declarations)
endif()


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# librespot: el sidecar que reproduce el audio de verdad. Va junto al ejecutable
# porque es donde lo busca `LibrespotManager.findBinary()`. Se compila aparte con
# tool/build_sidecars.sh; si no esta, el build sigue y la app avisa al arrancar.
#
# ⚠️ Va con install(PROGRAMS) y no install(FILES): FILES instala con permiso 644
# y el binario no se podria ejecutar.
set(LIBRESPOT_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../tool/librespot-build/bin/librespot")
if(EXISTS "${LIBRESPOT_BIN}")
  install(PROGRAMS "${LIBRESPOT_BIN}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
else()
  message(WARNING "No se encuentra librespot; ejecuta tool/build_sidecars.sh antes de empaquetar.")
endif()

# metadata-sidecar: lee por el protocolo interno lo que la Web API deniega con
# 403 (las playlists ajenas). Sin el, la app funciona igual salvo esas.
set(METADATA_SIDECAR_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../tool/metadata-sidecar/target/release/metadata-sidecar")
if(EXISTS "${METADATA_SIDECAR_BIN}")
  install(PROGRAMS "${METADATA_SIDECAR_BIN}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
else()
  message(WARNING "No se encuentra metadata-sidecar; compilalo con: cargo build --release --manifest-path tool/metadata-sidecar/Cargo.toml")
endif()

# yt-dlp: el descodificador de la via libre, que resuelve la URL del stream de cada
# pista. Sin el, las cuentas sin Premium no suenan. No se compila: lo baja
# tool/fetch_ytdlp.sh del release del propio proyecto.
#
# El que se empaqueta es `yt-dlp_linux`, el binario autonomo (~40 MB), y no el
# zipapp de 3 MB: aquel necesitaria un python3 >= 3.9 en el sistema y este trae
# su propio interprete dentro, asi que ningun paquete declara ya python3.
set(YTDLP_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../tool/ytdlp-build/bin/yt-dlp")
if(EXISTS "${YTDLP_BIN}")
  install(PROGRAMS "${YTDLP_BIN}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
else()
  message(WARNING "No se encuentra yt-dlp; ejecuta tool/fetch_ytdlp.sh antes de empaquetar (las cuentas sin Premium no sonaran sin el).")
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
