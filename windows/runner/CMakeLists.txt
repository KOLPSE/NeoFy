cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "audio_device_watcher.cpp"
  "flutter_window.cpp"
  "main.cpp"
  "system_media.cpp"
  "thumb_bar.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# COM: el vigilante del dispositivo de salida va por IMMNotificationClient, y
# los botones de la miniatura de la barra de tareas por ITaskbarList3.
target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib")
# WinRT sin C++/WinRT: los controles multimedia del sistema se activan con
# RoGetActivationFactory y las cadenas van en HSTRING.
target_link_libraries(${BINARY_NAME} PRIVATE "runtimeobject.lib")
# La carátula que se le pasa al panel del sistema se envuelve con
# CreateRandomAccessStreamOverStream (shcore) sobre SHCreateStreamOnFileEx
# (shlwapi), que es la única vía síncrona: la de StorageFile es asíncrona y
# esperarla bloquearía el hilo de la ventana.
target_link_libraries(${BINARY_NAME} PRIVATE "shcore.lib" "shlwapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
