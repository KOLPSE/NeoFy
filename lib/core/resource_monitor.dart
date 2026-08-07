import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Qué gasta la app **de verdad**: los tres procesos sumados, en memoria y CPU.
///
/// Hace falta porque el Administrador de tareas no ayuda: agrupa por ventanas
/// de nivel superior, y los dos sidecars son procesos de consola sin ventana,
/// así que aparecen sueltos en "procesos en segundo plano" en vez de bajo
/// `neofy.exe`. Mirar solo esa fila engaña: se deja fuera el 25 % del
/// gasto. No hay forma de cambiar cómo lo agrupa Windows, así que la app lo
/// suma por su cuenta.
///
/// Se lee con `GetProcessMemoryInfo` y `GetProcessTimes` por FFI —`dart:ffi`
/// viene con el SDK— en vez de lanzar `tasklist` cada pocos segundos, que
/// costaría más que lo que mide.
class UsoDeRecursos {
  const UsoDeRecursos({
    this.app = 0,
    this.audio = 0,
    this.metadatos = 0,
    this.cpu = 0,
  });

  /// Working set en bytes de cada proceso. 0 = no está corriendo.
  final int app;
  final int audio;
  final int metadatos;

  /// Porcentaje de CPU de los tres juntos, ya normalizado al número de núcleos:
  /// 100 % significa la máquina entera, no un núcleo.
  final double cpu;

  int get total => app + audio + metadatos;

  static String mb(int bytes) => '${(bytes / (1 << 20)).round()} MB';

  /// Solo se considera un cambio digno de repintar si mueve al menos un mega o
  /// medio punto de CPU: los dos valores oscilan constantemente.
  bool pareceIgualQue(UsoDeRecursos otro) =>
      (total - otro.total).abs() < (1 << 20) &&
      (app - otro.app).abs() < (1 << 20) &&
      (cpu - otro.cpu).abs() < 0.5;

  @override
  String toString() =>
      'app ${mb(app)} + audio ${mb(audio)} + metadatos ${mb(metadatos)}, '
      'CPU ${cpu.toStringAsFixed(1)} %';
}

/// Estructura `PROCESS_MEMORY_COUNTERS` de psapi.h. Los `SIZE_T` son punteros
/// en tamaño, de ahí `IntPtr`.
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

// Los FILETIME son ocho bytes; un Pointer<Uint64> vale y ahorra otra Struct.
typedef _GetTimesC = Int32 Function(
    IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetTimesDart = int Function(
    int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

typedef _EmptyWorkingSetC = Int32 Function(IntPtr);
typedef _EmptyWorkingSetDart = int Function(int);

class ResourceMonitor extends ChangeNotifier {
  ResourceMonitor({required this.pidsDeSidecars});

  /// De dónde salen los pids de los procesos hijos. Se pide como función y no
  /// como valor porque los sidecars se reinician solos y cambian de pid.
  final List<int?> Function() pidsDeSidecars;

  static const _intervalo = Duration(seconds: 3);

  UsoDeRecursos uso = const UsoDeRecursos();
  Timer? _timer;

  /// Techo que mantener, en bytes, o `null` para no hacer nada.
  ///
  /// Lo pone el modo rendimiento. Cuando el total lo pasa, se le pide a Windows
  /// que recoja las páginas que la app no está usando. No es un límite duro
  /// —nadie puede prometerle a un proceso que no crecerá—, pero sí mantiene el
  /// residente pegado al objetivo en vez de dejarlo subir y quedarse arriba.
  int? techoBytes;

  /// Podar tiene un coste (los fallos de página blandos al volver a tocar lo
  /// recogido), así que no se hace en cada muestra aunque siga por encima.
  static const _entrePodas = Duration(seconds: 30);
  DateTime _ultimaPoda = DateTime.fromMillisecondsSinceEpoch(0);

  /// Última lectura del tiempo de CPU acumulado, para poder sacar el
  /// porcentaje: `GetProcessTimes` da el total desde que arrancó el proceso,
  /// así que el dato útil es la diferencia entre dos muestras.
  int _ticksAnteriores = 0;
  DateTime? _momentoAnterior;

  // Windows: PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ.
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

  void start() {
    if (!Platform.isWindows) return;
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
        // Los ticks son unidades de 100 ns: 10.000.000 por segundo de CPU.
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
      vaciarWorkingSet(pidsDeSidecars());
    }

    if (nuevo.pareceIgualQue(uso)) return;
    uso = nuevo;
    notifyListeners();
  }

  /// Le pide a Windows que devuelva al sistema las páginas residentes que no
  /// hagan falta ahora mismo, en los tres procesos.
  ///
  /// Es lo que hace Windows por su cuenta al minimizar una ventana, y aquí se
  /// pide a mano al esconderse en la bandeja y al encender el modo rendimiento.
  /// No se pierde nada: las páginas pasan a la lista de espera del sistema y
  /// vuelven solas si se necesitan; lo único que cuesta es un fallo de página
  /// blando la primera vez. A cambio, la memoria que la app tenía retenida
  /// queda libre para el resto del equipo, que es lo que se está midiendo.
  static void vaciarWorkingSet(List<int?> procesos) {
    final abrir = _openProcess;
    final vaciar = _emptyWorkingSet;
    final cerrar = _closeHandle;
    if (abrir == null || vaciar == null || cerrar == null) return;
    for (final p in [pid, ...procesos]) {
      if (p == null) continue;
      // PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA, que es lo que pide
      // EmptyWorkingSet (el de "limited" no basta aquí).
      final handle = abrir(0x0400 | 0x0100, 0, p);
      if (handle == 0) continue;
      vaciar(handle);
      cerrar(handle);
    }
  }

  /// Working set y ticks de CPU de un pid, en una sola apertura del proceso.
  /// `(0, 0)` si no existe o no se deja mirar.
  static (int, int) _medir(int? proceso) {
    final abrir = _openProcess;
    final memoria = _getMemoryInfo;
    final tiempos = _getProcessTimes;
    final cerrar = _closeHandle;
    if (proceso == null ||
        abrir == null ||
        memoria == null ||
        tiempos == null ||
        cerrar == null) {
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
        // Solo interesan kernel + usuario; creación y salida se ignoran.
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
