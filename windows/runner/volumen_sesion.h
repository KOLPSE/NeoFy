#ifndef RUNNER_VOLUMEN_SESION_H_
#define RUNNER_VOLUMEN_SESION_H_

// Pone el volumen de la sesión WASAPI de librespot.exe, 0–100.
// Devuelve true si encontró al menos una sesión.
bool SetVolumenLibrespot(int percent);

#endif
