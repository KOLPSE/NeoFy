import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class EstadoVoz {
  const EstadoVoz({
    this.hayVoz = false,
    this.nivelVoz = 0,
    this.disponible = true,
  });

  final bool hayVoz;
  final double nivelVoz;
  final bool disponible;

  @override
  bool operator ==(Object other) =>
      other is EstadoVoz &&
      other.hayVoz == hayVoz &&
      other.nivelVoz == nivelVoz &&
      other.disponible == disponible;

  @override
  int get hashCode => Object.hash(hayVoz, nivelVoz, disponible);
}

abstract class FuenteDeteccionVoz {
  ValueListenable<EstadoVoz> get estado;
  bool get disponible;
  Future<void> iniciar();
  Future<void> detener();
  void dispose();
}

/// Detector de voz sobre PCM usando separación de banda vocal (280–3400 Hz)
/// frente a graves (< 200 Hz) y suavizado por histéresis temporal.
class AnalizadorVozPcm {
  AnalizadorVozPcm({
    int sampleRate = 48000,
    this.umbralEntrada = 0.012,
    this.umbralSosten = 0.007,
    this.confirmacionMs = 70,
    this.retencionMs = 200,
  }) : _sampleRate = sampleRate.clamp(8000, 192000) {
    _configurarFiltros(_sampleRate);
  }

  final double umbralEntrada;
  final double umbralSosten;
  final int confirmacionMs;
  final int retencionMs;

  int _sampleRate;
  bool _hayVoz = false;
  int _acumuladoEntradaMs = 0;
  int _restanteRetencionMs = 0;

  late _Biquad _pasaAltosVoz;
  late _Biquad _pasaBajosVoz;
  late _Biquad _pasaBajosGraves;

  void _configurarFiltros(int sr) {
    _sampleRate = sr.clamp(8000, 192000);
    _pasaAltosVoz = _Biquad.highPass(_sampleRate.toDouble(), 280);
    _pasaBajosVoz = _Biquad.lowPass(
      _sampleRate.toDouble(),
      math.min(3400.0, _sampleRate * 0.42),
    );
    _pasaBajosGraves = _Biquad.lowPass(_sampleRate.toDouble(), 200);
  }

  void reiniciar() {
    _hayVoz = false;
    _acumuladoEntradaMs = 0;
    _restanteRetencionMs = 0;
    _pasaAltosVoz.reset();
    _pasaBajosVoz.reset();
    _pasaBajosGraves.reset();
  }

  EstadoVoz analizarMono(List<double> muestras, {int? sampleRate}) {
    if (sampleRate != null && sampleRate != _sampleRate) {
      _configurarFiltros(sampleRate);
    }
    if (muestras.isEmpty) {
      return EstadoVoz(hayVoz: _hayVoz, nivelVoz: 0);
    }

    var sumaVoz = 0.0;
    var sumaGraves = 0.0;
    var sumaTotal = 0.0;
    for (final x in muestras) {
      sumaTotal += x * x;
      final voz = _pasaBajosVoz.process(_pasaAltosVoz.process(x));
      final grave = _pasaBajosGraves.process(x);
      sumaVoz += voz * voz;
      sumaGraves += grave * grave;
    }

    final n = muestras.length;
    final rmsVoz = math.sqrt(sumaVoz / n);
    final rmsGraves = math.sqrt(sumaGraves / n);
    final rmsTotal = math.sqrt(sumaTotal / n);
    final duracionMs = ((n * 1000) / _sampleRate).round().clamp(1, 200);

    // Exige energía en banda vocal que no quede eclipsada por puro bombo/bajo.
    final umbral = _hayVoz ? umbralSosten : umbralEntrada;
    final relacionGraves = rmsVoz > rmsGraves * 0.45 || rmsVoz > umbral * 2.2;
    final relacionTotal = rmsTotal <= 1e-6 || rmsVoz >= rmsTotal * 0.16;
    final frameConVoz = rmsVoz >= umbral && relacionGraves && relacionTotal;

    if (frameConVoz) {
      _acumuladoEntradaMs += duracionMs;
      _restanteRetencionMs = retencionMs;
      if (_hayVoz || _acumuladoEntradaMs >= confirmacionMs) {
        _hayVoz = true;
      }
    } else {
      _acumuladoEntradaMs = 0;
      if (_hayVoz) {
        _restanteRetencionMs -= duracionMs;
        if (_restanteRetencionMs <= 0) {
          _restanteRetencionMs = 0;
          _hayVoz = false;
        }
      }
    }

    final nivel = (rmsVoz / (umbralEntrada * 4)).clamp(0.0, 1.0);
    return EstadoVoz(hayVoz: _hayVoz, nivelVoz: nivel);
  }
}

class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory _Biquad.lowPass(double sampleRate, double cutoffHz) {
    final w0 = 2 * math.pi * cutoffHz / sampleRate;
    final cosW = math.cos(w0);
    final alpha = math.sin(w0) / math.sqrt2;
    final a0 = 1 + alpha;
    return _Biquad(
      (1 - cosW) / 2 / a0,
      (1 - cosW) / a0,
      (1 - cosW) / 2 / a0,
      (-2 * cosW) / a0,
      (1 - alpha) / a0,
    );
  }

  factory _Biquad.highPass(double sampleRate, double cutoffHz) {
    final w0 = 2 * math.pi * cutoffHz / sampleRate;
    final cosW = math.cos(w0);
    final alpha = math.sin(w0) / math.sqrt2;
    final a0 = 1 + alpha;
    return _Biquad(
      (1 + cosW) / 2 / a0,
      -(1 + cosW) / a0,
      (1 + cosW) / 2 / a0,
      (-2 * cosW) / a0,
      (1 - alpha) / a0,
    );
  }

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double _z1 = 0;
  double _z2 = 0;

  double process(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    _z1 = 0;
    _z2 = 0;
  }
}

/// Implementación real para Windows usando WASAPI Loopback en un Isolate.
class CapturaVozWasapi implements FuenteDeteccionVoz {
  CapturaVozWasapi()
      : _estado = ValueNotifier(
          EstadoVoz(disponible: Platform.isWindows),
        );

  final ValueNotifier<EstadoVoz> _estado;
  Isolate? _isolate;
  ReceivePort? _rx;
  SendPort? _controlPort;
  bool _activa = false;
  bool _disposed = false;

  @override
  ValueListenable<EstadoVoz> get estado => _estado;

  @override
  bool get disponible => Platform.isWindows && _estado.value.disponible;

  @override
  Future<void> iniciar() async {
    if (_disposed || _activa || !Platform.isWindows) return;
    _activa = true;
    final rx = ReceivePort();
    _rx = rx;
    final controlReady = Completer<SendPort>();

    rx.listen((msg) {
      if (msg is SendPort) {
        if (!controlReady.isCompleted) controlReady.complete(msg);
      } else if (msg is List && msg.length == 3) {
        if (_disposed) return;
        final hayVoz = msg[0] == true;
        final nivel = (msg[1] as num).toDouble();
        final disp = msg[2] == true;
        _estado.value = EstadoVoz(
          hayVoz: hayVoz,
          nivelVoz: nivel,
          disponible: disp,
        );
      }
    });

    _isolate = await Isolate.spawn(_isolateLoopbackWindows, rx.sendPort);
    _controlPort = await controlReady.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => rx.sendPort,
    );
  }

  @override
  Future<void> detener() async {
    _activa = false;
    _controlPort?.send('stop');
    _controlPort = null;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _rx?.close();
    _rx = null;
    if (!_disposed) {
      _estado.value = EstadoVoz(
        hayVoz: false,
        nivelVoz: 0,
        disponible: Platform.isWindows,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(detener());
    _estado.dispose();
  }
}

void _isolateLoopbackWindows(SendPort mainPort) {
  final cmdPort = ReceivePort();
  mainPort.send(cmdPort.sendPort);
  var detener = false;
  cmdPort.listen((msg) {
    if (msg == 'stop') detener = true;
  });

  final ole32 = DynamicLibrary.open('ole32.dll');
  final coInit = ole32.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('CoInitializeEx');
  final coUninit = ole32.lookupFunction<Void Function(), void Function()>(
    'CoUninitialize',
  );
  final coCreate = ole32.lookupFunction<
      Int32 Function(
        Pointer<Uint8>,
        Pointer<Void>,
        Uint32,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<Uint8>,
        Pointer<Void>,
        int,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>,
      )>('CoCreateInstance');
  final coTaskMemFree = ole32.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CoTaskMemFree');

  final hrInit = coInit(nullptr, 0); // COINIT_MULTITHREADED
  final debeDesinicializar = hrInit == 0 || hrInit == 1;

  final clsidEnum = _guidBytes(0xBCDE0395, 0xE52F, 0x467C, [
    0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E,
  ]);
  final iidEnum = _guidBytes(0xA95664D2, 0x9614, 0x4F35, [
    0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6,
  ]);
  final iidAudioClient = _guidBytes(0x1CB9AD4C, 0xDBFA, 0x4C32, [
    0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2,
  ]);
  final iidCaptureClient = _guidBytes(0xC8ADBD64, 0xE71E, 0x48A0, [
    0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17,
  ]);

  final analizador = AnalizadorVozPcm();
  var ultimoEnvio = EstadoVoz(disponible: true);

  while (!detener) {
    final ok = _ejecutarBucleWasapi(
      coCreate: coCreate,
      coTaskMemFree: coTaskMemFree,
      clsidEnum: clsidEnum,
      iidEnum: iidEnum,
      iidAudioClient: iidAudioClient,
      iidCaptureClient: iidCaptureClient,
      debeDetener: () => detener,
      onMuestras: (muestras, sampleRate) {
        final actual = analizador.analizarMono(muestras, sampleRate: sampleRate);
        if (actual.hayVoz != ultimoEnvio.hayVoz ||
            (actual.nivelVoz - ultimoEnvio.nivelVoz).abs() > 0.08) {
          ultimoEnvio = actual;
          mainPort.send([actual.hayVoz, actual.nivelVoz, true]);
        }
      },
    );
    if (!ok && !detener) {
      mainPort.send([false, 0.0, false]);
      sleep(const Duration(milliseconds: 500));
    } else if (!detener) {
      analizador.reiniciar();
      sleep(const Duration(milliseconds: 250));
    }
  }

  calloc.free(clsidEnum);
  calloc.free(iidEnum);
  calloc.free(iidAudioClient);
  calloc.free(iidCaptureClient);
  if (debeDesinicializar) coUninit();
  cmdPort.close();
}

bool _ejecutarBucleWasapi({
  required int Function(
    Pointer<Uint8>,
    Pointer<Void>,
    int,
    Pointer<Uint8>,
    Pointer<Pointer<Void>>,
  ) coCreate,
  required void Function(Pointer<Void>) coTaskMemFree,
  required Pointer<Uint8> clsidEnum,
  required Pointer<Uint8> iidEnum,
  required Pointer<Uint8> iidAudioClient,
  required Pointer<Uint8> iidCaptureClient,
  required bool Function() debeDetener,
  required void Function(List<double> muestras, int sampleRate) onMuestras,
}) {
  final ppEnum = calloc<Pointer<Void>>();
  Pointer<Void> enumerator = nullptr;
  Pointer<Void> device = nullptr;
  Pointer<Void> audioClient = nullptr;
  Pointer<Void> captureClient = nullptr;
  Pointer<Void> mixFormat = nullptr;

  try {
    var hr = coCreate(clsidEnum, nullptr, 23, iidEnum, ppEnum);
    if (hr < 0 || ppEnum.value == nullptr) return false;
    enumerator = ppEnum.value;

    final ppDev = calloc<Pointer<Void>>();
    try {
      final getDefault = _vtablePtr<
          Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Pointer<Void>>)>(
        enumerator,
        4,
      ).asFunction<
          int Function(Pointer<Void>, int, int, Pointer<Pointer<Void>>)>();
      hr = getDefault(enumerator, 0, 0, ppDev); // eRender, eConsole
      if (hr < 0 || ppDev.value == nullptr) return false;
      device = ppDev.value;
    } finally {
      calloc.free(ppDev);
    }

    final ppClient = calloc<Pointer<Void>>();
    try {
      final activate = _vtablePtr<
          Int32 Function(
            Pointer<Void>,
            Pointer<Uint8>,
            Uint32,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          )>(device, 3)
          .asFunction<
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            )
          >();
      hr = activate(device, iidAudioClient, 23, nullptr, ppClient);
      if (hr < 0 || ppClient.value == nullptr) return false;
      audioClient = ppClient.value;
    } finally {
      calloc.free(ppClient);
    }

    final ppFmt = calloc<Pointer<Void>>();
    try {
      final getMixFormat = _vtablePtr<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>)>(
        audioClient,
        8,
      ).asFunction<int Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
      hr = getMixFormat(audioClient, ppFmt);
      if (hr < 0 || ppFmt.value == nullptr) return false;
      mixFormat = ppFmt.value;
    } finally {
      calloc.free(ppFmt);
    }

    final fmtBytes = mixFormat.cast<Uint8>();
    final bd = ByteData.sublistView(fmtBytes.asTypedList(40));
    final formatTag = bd.getUint16(0, Endian.little);
    final channels = bd.getUint16(2, Endian.little).clamp(1, 16);
    final sampleRate = bd.getUint32(4, Endian.little).clamp(8000, 192000);
    final bitsPerSample = bd.getUint16(14, Endian.little);

    var esFloat = formatTag == 3;
    var esPcm16 = formatTag == 1 && bitsPerSample == 16;
    if (formatTag == 0xFFFE) {
      final subTag = bd.getUint32(24, Endian.little);
      esFloat = subTag == 3 && bitsPerSample == 32;
      esPcm16 = subTag == 1 && bitsPerSample == 16;
    }
    if (!esFloat && !esPcm16) return false;

    final initFn = _vtablePtr<
        Int32 Function(
          Pointer<Void>,
          Int32,
          Uint32,
          Int64,
          Int64,
          Pointer<Void>,
          Pointer<Void>,
        )>(audioClient, 3)
        .asFunction<
          int Function(
            Pointer<Void>,
            int,
            int,
            int,
            int,
            Pointer<Void>,
            Pointer<Void>,
          )
        >();
    // AUDCLNT_SHAREMODE_SHARED = 0, AUDCLNT_STREAMFLAGS_LOOPBACK = 0x00020000
    hr = initFn(audioClient, 0, 0x00020000, 1000000, 0, mixFormat, nullptr);
    if (hr < 0) return false;

    final ppCap = calloc<Pointer<Void>>();
    try {
      final getService = _vtablePtr<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<Void>>)>(
        audioClient,
        14,
      ).asFunction<
          int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<Void>>)>();
      hr = getService(audioClient, iidCaptureClient, ppCap);
      if (hr < 0 || ppCap.value == nullptr) return false;
      captureClient = ppCap.value;
    } finally {
      calloc.free(ppCap);
    }

    final startFn = _vtablePtr<Int32 Function(Pointer<Void>)>(
      audioClient,
      10,
    ).asFunction<int Function(Pointer<Void>)>();
    hr = startFn(audioClient);
    if (hr < 0) return false;

    final getNextPacket = _vtablePtr<
        Int32 Function(Pointer<Void>, Pointer<Uint32>)>(
      captureClient,
      5,
    ).asFunction<int Function(Pointer<Void>, Pointer<Uint32>)>();
    final getBuffer = _vtablePtr<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )>(captureClient, 3)
        .asFunction<
          int Function(
            Pointer<Void>,
            Pointer<Pointer<Void>>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >();
    final releaseBuffer = _vtablePtr<Int32 Function(Pointer<Void>, Uint32)>(
      captureClient,
      4,
    ).asFunction<int Function(Pointer<Void>, int)>();

    final pPacket = calloc<Uint32>();
    final ppData = calloc<Pointer<Void>>();
    final pFrames = calloc<Uint32>();
    final pFlags = calloc<Uint32>();
    final pDevPos = calloc<Uint64>();
    final pQpcPos = calloc<Uint64>();

    try {
      final silencio = List<double>.filled((sampleRate * 0.02).round(), 0.0);
      while (!debeDetener()) {
        hr = getNextPacket(captureClient, pPacket);
        if (hr < 0) return true; // dispositivo cambiado: reintentar limpio

        var leidoAlgo = false;
        while (pPacket.value > 0 && !debeDetener()) {
          hr = getBuffer(
            captureClient,
            ppData,
            pFrames,
            pFlags,
            pDevPos,
            pQpcPos,
          );
          if (hr < 0) return true;
          final frames = pFrames.value;
          final silent = (pFlags.value & 0x2) != 0;
          if (frames > 0) {
            leidoAlgo = true;
            if (silent || ppData.value == nullptr) {
              onMuestras(List<double>.filled(frames, 0.0), sampleRate);
            } else if (esFloat) {
              final floats = ppData.value.cast<Float>().asTypedList(
                frames * channels,
              );
              final mono = List<double>.filled(frames, 0.0);
              for (var i = 0; i < frames; i++) {
                var acc = 0.0;
                final base = i * channels;
                for (var c = 0; c < channels; c++) {
                  acc += floats[base + c];
                }
                mono[i] = acc / channels;
              }
              onMuestras(mono, sampleRate);
            } else {
              final ints = ppData.value.cast<Int16>().asTypedList(
                frames * channels,
              );
              final mono = List<double>.filled(frames, 0.0);
              for (var i = 0; i < frames; i++) {
                var acc = 0.0;
                final base = i * channels;
                for (var c = 0; c < channels; c++) {
                  acc += ints[base + c] / 32768.0;
                }
                mono[i] = acc / channels;
              }
              onMuestras(mono, sampleRate);
            }
          }
          releaseBuffer(captureClient, frames);
          hr = getNextPacket(captureClient, pPacket);
          if (hr < 0) return true;
        }
        if (!leidoAlgo) {
          onMuestras(silencio, sampleRate);
        }
        sleep(const Duration(milliseconds: 20));
      }
      final stopFn = _vtablePtr<Int32 Function(Pointer<Void>)>(
        audioClient,
        11,
      ).asFunction<int Function(Pointer<Void>)>();
      stopFn(audioClient);
      return true;
    } finally {
      calloc.free(pPacket);
      calloc.free(ppData);
      calloc.free(pFrames);
      calloc.free(pFlags);
      calloc.free(pDevPos);
      calloc.free(pQpcPos);
    }
  } finally {
    if (mixFormat != nullptr) coTaskMemFree(mixFormat);
    _releaseCom(captureClient);
    _releaseCom(audioClient);
    _releaseCom(device);
    _releaseCom(enumerator);
    calloc.free(ppEnum);
  }
}

void _releaseCom(Pointer<Void> obj) {
  if (obj == nullptr) return;
  final release = _vtablePtr<Uint32 Function(Pointer<Void>)>(
    obj,
    2,
  ).asFunction<int Function(Pointer<Void>)>();
  release(obj);
}

Pointer<NativeFunction<N>> _vtablePtr<N extends Function>(
  Pointer<Void> obj,
  int slot,
) {
  final vtable = obj.cast<Pointer<IntPtr>>().value;
  final addr = vtable[slot];
  return Pointer<NativeFunction<N>>.fromAddress(addr);
}

Pointer<Uint8> _guidBytes(int d1, int d2, int d3, List<int> d4) {
  final p = calloc<Uint8>(16);
  final bd = ByteData(16)
    ..setUint32(0, d1, Endian.little)
    ..setUint16(4, d2, Endian.little)
    ..setUint16(6, d3, Endian.little);
  for (var i = 0; i < 8; i++) {
    bd.setUint8(8 + i, d4[i]);
  }
  p.asTypedList(16).setAll(0, bd.buffer.asUint8List());
  return p;
}
