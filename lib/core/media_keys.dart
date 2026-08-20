import 'package:flutter/services.dart';

class MediaKeys {
  MediaKeys({
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onPause,
  });

  static const _channel = MethodChannel('neofy/media_keys');

  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onPause;

  void start() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          await onPlayPause();
        case 'next':
          await onNext();
        case 'previous':
          await onPrevious();
        case 'pause':
          await onPause();
      }
      return null;
    });
  }

  void stop() => _channel.setMethodCallHandler(null);
}
