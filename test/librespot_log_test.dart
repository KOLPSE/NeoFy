import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/librespot.dart';

void main() {
  // Cuando la salida de audio desaparece, librespot no se muere: se queda vivo
  // y mudo, así que el reinicio por caída del proceso no entra. Estas líneas
  // del log son el único aviso de que hay que reabrir la salida.
  group('un error del backend de audio se reconoce', () {
    const lineas = [
      '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::rodio] '
          'Rodio play error: device no longer valid',
      '[2026-08-07T10:12:00Z ERROR librespot_playback::player] Audio Sink Error '
          'Write: NoDevice',
      'ERROR cpal: the requested output device is no longer available',
      // Los backends de Linux. En Arch se usa el de PulseAudio, que PipeWire
      // expone por su shim; sus errores llegan firmados con ese nombre.
      '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::pulseaudio] '
          'PulseAudio failed to write: ConnectionTerminated',
      '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::alsa] '
          'Alsa error PCM write failed',
    ];
    for (final linea in lineas) {
      test(linea.substring(0, 40), () => expect(esFalloDeAudio(linea), isTrue));
    }
  });

  // Y lo contrario importa igual: reiniciar el audio corta la música un par de
  // segundos, así que ni un aviso normal ni un error de otra cosa pueden
  // dispararlo.
  group('lo demás se deja en paz', () {
    const lineas = [
      '[2026-08-07T10:12:00Z INFO  librespot] librespot 0.8.0 loading',
      '[2026-08-07T10:12:00Z INFO  librespot_playback::audio_backend::rodio] '
          'Using audio device: Altavoces',
      '[2026-08-07T10:12:00Z ERROR librespot_core::session] Connection failed: '
          'IO error',
      '[2026-08-07T10:12:00Z WARN  librespot_playback::player] Loading track '
          'took a long time',
    ];
    for (final linea in lineas) {
      test(linea.substring(30, 60), () => expect(esFalloDeAudio(linea), isFalse));
    }
  });
}
