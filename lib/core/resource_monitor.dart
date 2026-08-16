import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class UsoDeRecursos {
  const UsoDeRecursos({
    this.app = 0,
    this.audio = 0,
    this.metadatos = 0,
    this.cpu = 0,
  });

  final int app;
  final int audio;
  final int metadatos;

  final double cpu;

  int get total => app + audio + metadatos;

  static String mb(int bytes) => '${(bytes / (1 << 20)).round()} MB';

  bool pareceIgualQue(UsoDeRecursos otro) =>
      (total - otro.total).abs() < (1 << 20) &&
      (app - otro.app).abs() < (1 << 20) &&
      (cpu - otro.cpu).abs() < 0.5;

  @override
  String toString() =>
      'app ${mb(app)} + audio ${mb(audio)} + metadatos ${mb(metadatos)}, '
      'CPU ${cpu.toStringAsFixed(1)} %';
}

final class _ContadoresDeMemoria extends Struct {
  @Uint32()
  external int cb;
  @Uint32()
  external int pageFaultCount;
  @IntPtr()
  external int peakWorkingSetSize;
  @IntPtr()
  external int workingSetSize;
  @IntPtr()
  external int quotaPeakPagedPoolUsage;
  @IntPtr()
  external int quotaPagedPoolUsage;
  @IntPtr()
  external int quotaPeakNonPagedPoolUsage;
  @IntPtr()
  external int quotaNonPagedPoolUsage;
  @IntPtr()
  external int pagefileUsage;
  @IntPtr()
  external int peakPagefileUsage;
}

typedef _OpenProcessC = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _CloseHandleC = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
typedef _GetMemC = Int32 Function(IntPtr, Pointer<_ContadoresDeMemoria>, Uint32);
typedef _GetMemDart = int Function(int, Pointer<_ContadoresDeMemoria>, int);

typedef _GetTimesC = Int32 Function(
    IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetTimesDart = int Function(
    int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

typedef _EmptyWorkingSetC = Int32 Function(IntPtr);
typedef _EmptyWorkingSetDart = int Function(int);

typedef _MallocTrimC = Int32 Function(IntPtr);
typedef _MallocTrimDart = int Function(int);

class ResourceMonitor extends ChangeNotifier {
  ResourceMonitor({required this.pidsDeSidecars});

  final List<int?> Function() pidsDeSidecars;

  static const _intervalo = Duration(seconds: 3);

  UsoDeRecursos uso = const UsoDeRecursos();
  Timer? _timer;

  int? techoBytes;

  static const _entrePodas = Duration(seconds: 30);
  DateTime _ultimaPoda = DateTime.fromMillisecondsSinceEpoch(0);

  int _ticksAnteriores = 0;
  DateTime? _momentoAnterior;

  static const _acceso = 0x1000 | 0x0010;

  static final _kernel32 =
      Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;
  static final _psapi =
      Platform.isWindows ? DynamicLibrary.open('psapi.dll') : null;

  static final _openProcess = _kernel32
      ?.lookupFunction<_OpenProcessC, _OpenProcessDart>('OpenProcess');
  static final _closeHandle = _kernel32
      ?.lookupFunction<_CloseHandleC, _CloseHandleDart>('CloseHandle');
  static final _getProcessTimes = _kernel32
      ?.lookupFunction<_GetTimesC, _GetTimesDart>('GetProcessTimes');
  static final _getMemoryInfo =
      _psapi?.lookupFunction<_GetMemC, _GetMemDart>('GetProcessMemoryInfo');
  static final _emptyWorkingSet = _psapi
      ?.lookupFunction<_EmptyWorkingSetC, _EmptyWorkingSetDart>('EmptyWorkingSet');

  static final _mallocTrim = _buscarMallocTrim();

  static _MallocTrimDart? _buscarMallocTrim() {
    if (!Platform.isLinux) return null;
    try {
      return DynamicLibrary.process()
          .lookupFunction<_MallocTrimC, _MallocTrimDart>('malloc_trim');
    } catch (_) {
      return null;
    }
  }

  void start() {
    _muestrear();
    _timer ??= Timer.periodic(_intervalo, (_) => _muestrear());
  }

  void _muestrear() {
    final pids = <int?>[pid, ...pidsDeSidecars()];

    var ticks = 0;
    final memoria = <int>[];
    for (final p in pids) {
      final m = _medir(p);
      memoria.add(m.$1);
      ticks += m.$2;
    }

    final ahora = DateTime.now();
    final antes = _momentoAnterior;
    var cpu = uso.cpu;
    if (antes != null) {
      final segundos = ahora.difference(antes).inMicroseconds / 1e6;
      if (segundos > 0) {
        final segundosDeCpu = (ticks - _ticksAnteriores) / 1e7;
        cpu = (segundosDeCpu / segundos / Platform.numberOfProcessors * 100)
            .clamp(0.0, 100.0);
      }
    }
    _ticksAnteriores = ticks;
    _momentoAnterior = ahora;

    final nuevo = UsoDeRecursos(
      app: memoria[0],
      audio: memoria.length > 1 ? memoria[1] : 0,
      metadatos: memoria.length > 2 ? memoria[2] : 0,
      cpu: cpu,
    );
    final techo = techoBytes;
    if (techo != null &&
        nuevo.total > techo &&
        ahora.difference(_ultimaPoda) > _entrePodas) {
      _ultimaPoda = ahora;
      devolverMemoriaAlSistema(pidsDeSidecars());
    }

    if (nuevo.pareceIgualQue(uso)) return;
    uso = nuevo;
    notifyListeners();
  }

  static void devolverMemoriaAlSistema(List<int?> procesos) {
    if (Platform.isLinux) {
      _mallocTrim?.call(0);
      return;
    }
    final abrir = _openProcess;
    final vaciar = _emptyWorkingSet;
    final cerrar = _closeHandle;
    if (abrir == null || vaciar == null || cerrar == null) return;
    for (final p in [pid, ...procesos]) {
      if (p == null) continue;
      final handle = abrir(0x0400 | 0x0100, 0, p);
      if (handle == 0) continue;
      vaciar(handle);
      cerrar(handle);
    }
  }

  static (int, int) _medir(int? proceso) {
    if (proceso == null) return (0, 0);
    return Platform.isWindows ? _medirWindows(proceso) : _medirLinux(proceso);
  }

  static (int, int) _medirLinux(int proceso) {
    try {
      final ticks = ticksDeStat(File('/proc/$proceso/stat').readAsStringSync());

      var bytes = 0;
      final rollup = File('/proc/$proceso/smaps_rollup');
      if (rollup.existsSync()) {
        bytes = pssDeSmapsRollup(rollup.readAsStringSync());
      }
      if (bytes == 0) {
        bytes = rssDeStatm(File('/proc/$proceso/statm').readAsStringSync());
      }
      return (bytes, ticks);
    } catch (_) {
      return (0, 0);
    }
  }

  @visibleForTesting
  static int pssDeSmapsRollup(String rollup) {
    for (final linea in const LineSplitter().convert(rollup)) {
      final dosPuntos = linea.indexOf(':');
      if (dosPuntos < 0) continue;
      if (linea.substring(0, dosPuntos).trim() != 'Pss') continue;
      final resto = linea.substring(dosPuntos + 1).trim();
      final numero = resto.split(RegExp(r'\s+')).first;
      final kb = int.tryParse(numero);
      return kb == null ? 0 : kb * 1024;
    }
    return 0;
  }

  @visibleForTesting
  static int rssDeStatm(String statm) {
    final campos = statm.trim().split(RegExp(r'\s+'));
    if (campos.length < 2) return 0;
    return (int.tryParse(campos[1]) ?? 0) * _tamanoDePagina;
  }

  @visibleForTesting
  static int ticksDeStat(String stat) {
    final cierre = stat.lastIndexOf(')');
    if (cierre < 0) return 0;
    final campos = stat.substring(cierre + 1).trim().split(RegExp(r'\s+'));
    if (campos.length < 13) return 0;
    final utime = int.tryParse(campos[11]) ?? 0;
    final stime = int.tryParse(campos[12]) ?? 0;
    return (utime + stime) * _cienNanosPorTick;
  }

  static const int _tamanoDePagina = 4096;

  static const int _cienNanosPorTick = 100000;

  static (int, int) _medirWindows(int proceso) {
    final abrir = _openProcess;
    final memoria = _getMemoryInfo;
    final tiempos = _getProcessTimes;
    final cerrar = _closeHandle;
    if (abrir == null || memoria == null || tiempos == null || cerrar == null) {
      return (0, 0);
    }

    final handle = abrir(_acceso, 0, proceso);
    if (handle == 0) return (0, 0);

    final buf = calloc<_ContadoresDeMemoria>();
    final ft = calloc<Uint64>(4);
    try {
      var bytes = 0;
      buf.ref.cb = sizeOf<_ContadoresDeMemoria>();
      if (memoria(handle, buf, buf.ref.cb) != 0) bytes = buf.ref.workingSetSize;

      var ticks = 0;
      if (tiempos(handle, ft, ft + 1, ft + 2, ft + 3) != 0) {
        ticks = (ft + 2).value + (ft + 3).value;
      }
      return (bytes, ticks);
    } finally {
      calloc.free(buf);
      calloc.free(ft);
      cerrar(handle);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
