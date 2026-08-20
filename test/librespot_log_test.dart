import 'package:flutter_test/flutter_test.dart';
import 'package:neofy/core/librespot.dart';

void main() {
  group('un error del backend de audio se reconoce', () {
    const lineas = [
      '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::rodio] '
          'Rodio play error: device no longer valid',
      '[2026-08-07T10:12:00Z ERROR librespot_playback::player] Audio Sink Error '
          'Write: NoDevice',
      'ERROR cpal: the requested output device is no longer available',
      '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::pulseaudio] '
          'PulseAudio failed to write: ConnectionTerminated',
      '[2026-08-07T10:12:00Z ERROR librespot_playback::audio_backend::alsa] '
          'Alsa error PCM write failed',
    ];
    for (final linea in lineas) {
      test(linea.substring(0, 40), () => expect(esFalloDeAudio(linea), isTrue));
    }
  });

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
