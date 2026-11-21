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

/// Detector de voz sobre PCM orientado a música mezclada: combina separación
/// Mid/Side (la voz principal va centrada), balance espectral frente a graves
/// (< 200 Hz) y agudos (> 4000 Hz), periodicidad vocal (90–950 Hz) y piso
/// instrumental adaptativo con histéresis temporal.
class AnalizadorVozPcm {
  AnalizadorVozPcm({
    int sampleRate = 48000,
    this.umbralEntrada = 0.022,
    this.umbralSosten = 0.013,
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
  double _pisoVocal = 0;

  late _Biquad _pasaAltosVoz;
  late _Biquad _pasaBajosVoz;
  late _Biquad _pasaBajosGraves;
  late _Biquad _pasaAltosAgudos;
  late _Biquad _pasaAltosSide;
  late _Biquad _pasaBajosSide;

  Float64List _vozDecimada = Float64List(0);

  void _configurarFiltros(int sr) {
    _sampleRate = sr.clamp(8000, 192000);
    final srD = _sampleRate.toDouble();
    final corteSuperiorVoz = math.min(2800.0, _sampleRate * 0.40);
    final corteAgudos = math.min(4000.0, _sampleRate * 0.44);
    _pasaAltosVoz = _Biquad.highPass(srD, 280);
    _pasaBajosVoz = _Biquad.lowPass(srD, corteSuperiorVoz);
    _pasaBajosGraves = _Biquad.lowPass(srD, 200);
    _pasaAltosAgudos = _Biquad.highPass(srD, corteAgudos);
    _pasaAltosSide = _Biquad.highPass(srD, 280);
    _pasaBajosSide = _Biquad.lowPass(srD, corteSuperiorVoz);
  }

  void reiniciar() {
    _hayVoz = false;
    _acumuladoEntradaMs = 0;
    _restanteRetencionMs = 0;
    _pisoVocal = 0;
    _pasaAltosVoz.reset();
    _pasaBajosVoz.reset();
    _pasaBajosGraves.reset();
    _pasaAltosAgudos.reset();
    _pasaAltosSide.reset();
    _pasaBajosSide.reset();
  }

  EstadoVoz analizarMono(List<double> muestras, {int? sampleRate}) =>
      analizarEstereo(muestras, null, sampleRate: sampleRate);

  EstadoVoz analizarEstereo(
    List<double> mid,
    List<double>? side, {
    int? sampleRate,
  }) {
    if (sampleRate != null && sampleRate != _sampleRate) {
      _configurarFiltros(sampleRate);
    }
    final n = mid.length;
    if (n == 0) {
      return EstadoVoz(hayVoz: _hayVoz, nivelVoz: 0);
    }

    final paso = (_sampleRate / 12000).round().clamp(1, 8);
    final nDec = (n + paso - 1) ~/ paso;
    if (_vozDecimada.length < nDec) {
      _vozDecimada = Float64List(nDec);
    }

    var sumaVoz = 0.0;
    var sumaGraves = 0.0;
    var sumaAgudos = 0.0;
    var sumaTotal = 0.0;
    var sumaSideVoz = 0.0;
    final haySide = side != null && side.length >= n;

    var idxDec = 0;
    for (var i = 0; i < n; i++) {
      final x = mid[i];
      sumaTotal += x * x;
      final voz = _pasaBajosVoz.process(_pasaAltosVoz.process(x));
      final grave = _pasaBajosGraves.process(x);
      final agudo = _pasaAltosAgudos.process(x);
      sumaVoz += voz * voz;
      sumaGraves += grave * grave;
      sumaAgudos += agudo * agudo;
      if (i % paso == 0) {
        _vozDecimada[idxDec++] = voz;
      }
      if (haySide) {
        final s = _pasaBajosSide.process(_pasaAltosSide.process(side[i]));
        sumaSideVoz += s * s;
      }
    }

    final rmsVoz = math.sqrt(sumaVoz / n);
    final rmsGraves = math.sqrt(sumaGraves / n);
    final rmsAgudos = math.sqrt(sumaAgudos / n);
    final rmsTotal = math.sqrt(sumaTotal / n);
    final rmsSideVoz = haySide ? math.sqrt(sumaSideVoz / n) : 0.0;
    final duracionMs = ((n * 1000) / _sampleRate).round().clamp(1, 200);

    // En estéreo, la voz principal va centrada (Mid >> Side); los instrumentos
    // panoramizados y reverberados aportan mucha energía en Side.
    final tieneEstereoReal = haySide && rmsSideVoz > 1e-4;
    final razonCentro = tieneEstereoReal
        ? rmsVoz / (rmsVoz + rmsSideVoz + 1e-9)
        : 1.0;
    final energiaVocal = tieneEstereoReal
        ? math.max(0.0, rmsVoz - rmsSideVoz * 0.95)
        : rmsVoz;

    final umbralBase = _hayVoz ? umbralSosten : umbralEntrada;
    final factorPiso = _hayVoz ? 1.25 : 1.55;
    final superaPiso = energiaVocal >= math.max(umbralBase, _pisoVocal * factorPiso);

    final relacionCentro = !tieneEstereoReal ||
        razonCentro >= (_hayVoz ? 0.64 : 0.70);
    final relacionGraves = rmsVoz >= rmsGraves * (_hayVoz ? 0.55 : 0.65);
    final relacionAgudos = rmsVoz >= rmsAgudos * (_hayVoz ? 1.0 : 1.15);
    final relacionTotal = rmsTotal <= 1e-6 || rmsVoz >= rmsTotal * 0.30;

    final candidatoEspectral =
        superaPiso &&
        relacionCentro &&
        relacionGraves &&
        relacionAgudos &&
        relacionTotal;

    // Solo calculamos autocorrelación si pasó los filtros energéticos rápidos.
    var periodicidad = 0.0;
    if (candidatoEspectral && idxDec >= 24) {
      periodicidad = _periodicidadVocal(
        _vozDecimada,
        idxDec,
        _sampleRate / paso,
      );
    }
    final esArmonico = periodicidad >= (_hayVoz ? 0.40 : 0.48);
    final frameConVoz = candidatoEspectral && esArmonico;

    // Piso adaptativo: sigue la energía instrumental cuando no hay voz y baja
    // rápido en silencio, pero nunca sube arrastrado por la propia voz.
    if (rmsTotal < 0.005) {
      _pisoVocal *= 0.85;
    } else if (!frameConVoz) {
      final alfa = energiaVocal < _pisoVocal ? 0.18 : 0.06;
      _pisoVocal = _pisoVocal * (1 - alfa) + energiaVocal * alfa;
    } else if (energiaVocal < _pisoVocal) {
      _pisoVocal = _pisoVocal * 0.95 + energiaVocal * 0.05;
    }

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

    final nivel = (energiaVocal / (umbralEntrada * 4)).clamp(0.0, 1.0);
    return EstadoVoz(hayVoz: _hayVoz, nivelVoz: nivel);
  }

  /// Autocorrelación normalizada en el rango fundamental de canto (90–950 Hz).
  /// Separa vocales armónicas de baterías, ruido, platillos y mezclas densas.
  static double _periodicidadVocal(
    Float64List muestras,
    int n,
    double srEfectivo,
  ) {
    final lagMin = math.max(2, (srEfectivo / 950.0).floor());
    final lagMax = math.min(n ~/ 2, (srEfectivo / 90.0).ceil());
    if (lagMin >= lagMax) return 0;

    var mejor = 0.0;
    for (var lag = lagMin; lag <= lagMax; lag++) {
      final limite = n - lag;
      var cruce = 0.0;
      var e1 = 0.0;
      var e2 = 0.0;
      for (var i = 0; i < limite; i++) {
        final a = muestras[i];
        final b = muestras[i + lag];
        cruce += a * b;
        e1 += a * a;
        e2 += b * b;
      }
      final denom = math.sqrt(e1 * e2);
      if (denom > 1e-12) {
        final r = cruce / denom;
        if (r > mejor) mejor = r;
      }
    }
    return mejor;
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
  ReceivePort? _onExit;
  StreamSubscription<dynamic>? _rxSub;
  SendPort? _controlPort;
  Completer<void>? _salida;
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
    final onExit = ReceivePort();
    final salida = Completer<void>();
    _rx = rx;
    _onExit = onExit;
    _salida = salida;
    final controlReady = Completer<SendPort?>();

    unawaited(
      onExit.first.then(
        (_) {
          if (!salida.isCompleted) salida.complete();
        },
        onError: (_) {
          if (!salida.isCompleted) salida.complete();
        },
      ),
    );

    _rxSub = rx.listen((msg) {
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

    _isolate = await Isolate.spawn(
      _isolateLoopbackWindows,
      rx.sendPort,
      onExit: onExit.sendPort,
    );
    _controlPort = await controlReady.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    if (!_activa || _disposed) {
      await detener();
    }
  }

  @override
  Future<void> detener() async {
    _activa = false;
    final control = _controlPort;
    _controlPort = null;
    control?.send('stop');

    final salida = _salida;
    _salida = null;
    if (salida != null) {
      await salida.future.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () {},
      );
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    await _rxSub?.cancel();
    _rxSub = null;
    _rx?.close();
    _rx = null;
    _onExit?.close();
    _onExit = null;
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

Future<void> _esperarCooperativo(int ms, bool Function() debeDetener) async {
  var restante = ms;
  while (restante > 0 && !debeDetener()) {
    final paso = restante > 25 ? 25 : restante;
    await Future<void>.delayed(Duration(milliseconds: paso));
    restante -= paso;
  }
}

Future<void> _isolateLoopbackWindows(SendPort mainPort) async {
  final cmdPort = ReceivePort();
  mainPort.send(cmdPort.sendPort);
  var detener = false;
  final cmdSub = cmdPort.listen((msg) {
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

  try {
    while (!detener) {
      final ok = await _ejecutarBucleWasapi(
        coCreate: coCreate,
        coTaskMemFree: coTaskMemFree,
        clsidEnum: clsidEnum,
        iidEnum: iidEnum,
        iidAudioClient: iidAudioClient,
        iidCaptureClient: iidCaptureClient,
        debeDetener: () => detener,
        onMuestras: (mid, side, sampleRate) {
          final actual = analizador.analizarEstereo(
            mid,
            side,
            sampleRate: sampleRate,
          );
          if (actual.hayVoz != ultimoEnvio.hayVoz ||
              (actual.nivelVoz - ultimoEnvio.nivelVoz).abs() > 0.08) {
            ultimoEnvio = actual;
            mainPort.send([actual.hayVoz, actual.nivelVoz, true]);
          }
        },
      );
      if (!ok && !detener) {
        mainPort.send([false, 0.0, false]);
        await _esperarCooperativo(500, () => detener);
      } else if (!detener) {
        analizador.reiniciar();
        await _esperarCooperativo(250, () => detener);
      }
    }
  } finally {
    calloc.free(clsidEnum);
    calloc.free(iidEnum);
    calloc.free(iidAudioClient);
    calloc.free(iidCaptureClient);
    if (debeDesinicializar) coUninit();
    await cmdSub.cancel();
    cmdPort.close();
  }
}

Future<bool> _ejecutarBucleWasapi({
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
  required void Function(
    List<double> mid,
    List<double>? side,
    int sampleRate,
  ) onMuestras,
}) async {
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
      var silencio = Float64List((sampleRate * 0.02).round());
      var bufferMid = Float64List((sampleRate * 0.02).round());
      var bufferSide = Float64List((sampleRate * 0.02).round());
      final esEstereo = channels >= 2;
      final invCanales = 1.0 / channels;
      final invPcm16 = invCanales / 32768.0;
      const invPcm16Estereo = 0.5 / 32768.0;

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
              if (silencio.length < frames) {
                silencio = Float64List(frames);
              }
              final vista = Float64List.sublistView(silencio, 0, frames);
              onMuestras(vista, esEstereo ? vista : null, sampleRate);
            } else if (esFloat) {
              if (bufferMid.length < frames) {
                bufferMid = Float64List(frames);
                if (esEstereo) bufferSide = Float64List(frames);
              }
              final floats = ppData.value.cast<Float>().asTypedList(
                frames * channels,
              );
              if (esEstereo) {
                for (var i = 0; i < frames; i++) {
                  final base = i * channels;
                  final l = floats[base];
                  final r = floats[base + 1];
                  bufferMid[i] = (l + r) * 0.5;
                  bufferSide[i] = (l - r) * 0.5;
                }
                onMuestras(
                  Float64List.sublistView(bufferMid, 0, frames),
                  Float64List.sublistView(bufferSide, 0, frames),
                  sampleRate,
                );
              } else {
                for (var i = 0; i < frames; i++) {
                  var acc = 0.0;
                  final base = i * channels;
                  for (var c = 0; c < channels; c++) {
                    acc += floats[base + c];
                  }
                  bufferMid[i] = acc * invCanales;
                }
                onMuestras(
                  Float64List.sublistView(bufferMid, 0, frames),
                  null,
                  sampleRate,
                );
              }
            } else {
              if (bufferMid.length < frames) {
                bufferMid = Float64List(frames);
                if (esEstereo) bufferSide = Float64List(frames);
              }
              final ints = ppData.value.cast<Int16>().asTypedList(
                frames * channels,
              );
              if (esEstereo) {
                for (var i = 0; i < frames; i++) {
                  final base = i * channels;
                  final l = ints[base];
                  final r = ints[base + 1];
                  bufferMid[i] = (l + r) * invPcm16Estereo;
                  bufferSide[i] = (l - r) * invPcm16Estereo;
                }
                onMuestras(
                  Float64List.sublistView(bufferMid, 0, frames),
                  Float64List.sublistView(bufferSide, 0, frames),
                  sampleRate,
                );
              } else {
                for (var i = 0; i < frames; i++) {
                  var acc = 0.0;
                  final base = i * channels;
                  for (var c = 0; c < channels; c++) {
                    acc += ints[base + c];
                  }
                  bufferMid[i] = acc * invPcm16;
                }
                onMuestras(
                  Float64List.sublistView(bufferMid, 0, frames),
                  null,
                  sampleRate,
                );
              }
            }
          }
          releaseBuffer(captureClient, frames);
          hr = getNextPacket(captureClient, pPacket);
          if (hr < 0) return true;
        }
        if (!leidoAlgo) {
          onMuestras(silencio, esEstereo ? silencio : null, sampleRate);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
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
