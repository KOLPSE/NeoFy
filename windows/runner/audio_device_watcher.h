#ifndef RUNNER_AUDIO_DEVICE_WATCHER_H_
#define RUNNER_AUDIO_DEVICE_WATCHER_H_

#include <mmdeviceapi.h>
#include <windows.h>

class AudioDeviceWatcher {
 public:
  AudioDeviceWatcher() = default;
  ~AudioDeviceWatcher();

  AudioDeviceWatcher(const AudioDeviceWatcher&) = delete;
  AudioDeviceWatcher& operator=(const AudioDeviceWatcher&) = delete;

  bool Start(HWND window, UINT message);
  void Stop();

 private:
  IMMDeviceEnumerator* enumerator_ = nullptr;
  IMMNotificationClient* client_ = nullptr;
};

#endif
