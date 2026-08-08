import 'dart:async';
import 'dart:convert';
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
/// En Windows se lee con `GetProcessMemoryInfo` y `GetProcessTimes` por FFI
/// —`dart:ffi` viene con el SDK— en vez de lanzar `tasklist` cada pocos
/// segundos, que costaría más que lo que mide. En Linux se lee de `/proc`, sin
/// FFI ninguna: el PSS de `smaps_rollup` y los ticks de `stat`.
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

// glibc: `int malloc_trim(size_t pad)`. Devuelve al sistema la memoria libre
// que el asignador tiene retenida en sus arenas.
typedef _MallocTrimC = Int32 Function(IntPtr);
typedef _MallocTrimDart = int Function(int);

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
  /// Lo pone el modo rendimiento. Cuando el total lo pasa, se le devuelve al
  /// sistema lo que la app tenga retenido sin usar. No es un límite duro
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

  /// `malloc_trim` del propio proceso, o `null` donde no exista.
  ///
  /// Se busca en el proceso ya cargado (`DynamicLibrary.process()`, que en
  /// Windows ni siquiera está soportado) en vez de abrir `libc.so.6` por
  /// nombre: el fichero se llama distinto según la libc, y con musl la función
  /// directamente no existe. Si no aparece, se queda en `null` y no se llama a
  /// nadie — un sistema sin glibc no es un error, solo no tiene esta palanca.
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
      devolverMemoriaAlSistema(pidsDeSidecars());
    }

    if (nuevo.pareceIgualQue(uso)) return;
    uso = nuevo;
    notifyListeners();
  }

  /// Devuelve al sistema la memoria que la app tiene retenida sin usar.
  ///
  /// Se llama al encender el modo rendimiento, al esconderse en la bandeja y
  /// cada 30 s mientras el total pase del techo. Las dos plataformas tienen
  /// mecanismos distintos y **ninguno pierde nada**: lo recuperado vuelve solo
  /// en cuanto haga falta.
  ///
  /// - **Windows: `EmptyWorkingSet`** en los tres procesos. Saca las páginas
  ///   del working set y las manda a la lista de espera del sistema; volver a
  ///   tocarlas cuesta un fallo de página blando. Es lo mismo que hace Windows
  ///   por su cuenta al minimizar una ventana.
  /// - **Linux: `malloc_trim(0)`**, y solo en el proceso propio. No hay
  ///   equivalente de `EmptyWorkingSet` —el kernel no acepta que un proceso le
  ///   pida podarse— pero sí se puede obligar al asignador a soltar lo que ya
  ///   está libre.
  ///
  /// ⚠️ **Por qué `malloc_trim` sí vale la pena aquí**, en contra de lo que
  /// parece: es verdad que el heap de Dart no pasa por `malloc`, pero el resto
  /// del proceso sí. Las cachés ráster de Skia, los búferes de decodificación
  /// de imágenes y todo el lado GTK/GDK piden por ahí, y justo antes de esta
  /// llamada se acaba de vaciar la caché de imágenes: sin un trim, glibc se
  /// queda esas páginas en sus arenas y el residente no baja ni un byte aunque
  /// la memoria ya esté libre. El trim no puede hacer nada con los sidecars,
  /// que son procesos aparte con su propio asignador.
  static void devolverMemoriaAlSistema(List<int?> procesos) {
    if (Platform.isLinux) {
      // El argumento es cuánto dejar sin devolver en lo alto del heap. Cero:
      // que suelte todo lo que pueda.
      _mallocTrim?.call(0);
      return;
    }
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

  /// Memoria residente y tiempo de CPU de un pid. `(0, 0)` si no existe o no
  /// se deja mirar.
  ///
  /// Los ticks van **siempre en unidades de 100 ns**, pase lo que pase la
  /// plataforma: es lo que espera el cálculo del porcentaje de [_muestrear], y
  /// tenerlo en dos unidades distintas daría una CPU cien mil veces mayor en
  /// una de las dos sin que saltara ningún error.
  static (int, int) _medir(int? proceso) {
    if (proceso == null) return (0, 0);
    return Platform.isWindows ? _medirWindows(proceso) : _medirLinux(proceso);
  }

  /// Lo mismo por `/proc`, que es texto plano y no necesita FFI.
  ///
  /// ⚠️ **Se mide el PSS y no el RSS**, y la diferencia en Linux es enorme. El
  /// residente cuenta **enteras** las páginas compartidas, y una app GTK las
  /// tiene a montones: además de `libflutter_linux_gtk.so`, están GTK, GLib,
  /// Pango, Cairo, HarfBuzz, fontconfig, dbus y el driver de Mesa. Nada de eso
  /// es memoria de NeoFy —está compartida con el resto del escritorio— pero el
  /// RSS se la imputa toda, y por eso el mismo binario "gasta" el doble aquí
  /// que en Windows sin gastar nada más. El PSS reparte cada página compartida
  /// entre los procesos que la usan, que es exactamente lo que esta clase dice
  /// medir: lo que la app le cuesta al equipo.
  ///
  /// `smaps_rollup` es más caro que `statm` porque el kernel recorre todos los
  /// mapeos para sumarlo, pero es un fichero pequeño y esto va cada 3 s. Si no
  /// existe (kernel anterior al 4.14, o `/proc` montado con `hidepid`) se cae
  /// al RSS de siempre, que sobreestima pero nunca miente hacia abajo.
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
      // El proceso ha muerto entre una muestra y la siguiente, que es de lo más
      // normal con sidecars que se reinician solos.
      return (0, 0);
    }
  }

  /// Bytes de la línea `Pss:` de `/proc/<pid>/smaps_rollup`, o 0 si no está.
  ///
  /// El fichero son pares `Campo:   <n> kB`, uno por línea. Se busca `Pss`
  /// **exacto**: hay varios campos que empiezan igual (`Pss_Dirty`,
  /// `Pss_Anon`, `Pss_File`, `Pss_Shmem`) y quedarse con el primero que empiece
  /// por "Pss" daría un número plausible pero equivocado, que es la peor clase
  /// de error para algo que solo se mira de reojo.
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

  /// Residente en bytes de `/proc/<pid>/statm`. Es el plan B de [_medirLinux]
  /// cuando no hay `smaps_rollup`.
  ///
  /// Los campos son `size resident shared text lib data dt`, **en páginas**. El
  /// que interesa es el segundo: `size` es el espacio de direcciones virtual,
  /// que en un proceso con Skia son gigas y no dice nada de lo que gasta.
  @visibleForTesting
  static int rssDeStatm(String statm) {
    final campos = statm.trim().split(RegExp(r'\s+'));
    if (campos.length < 2) return 0;
    return (int.tryParse(campos[1]) ?? 0) * _tamanoDePagina;
  }

  /// Tiempo de CPU de `/proc/<pid>/stat`, convertido a unidades de 100 ns.
  ///
  /// ⚠️ **El segundo campo es el nombre del proceso entre paréntesis y puede
  /// llevar espacios y paréntesis dentro** (`(un proceso (raro))`), así que
  /// partir la línea por espacios desde el principio desalinea todo lo demás.
  /// Se busca el **último** `)` y se cuenta a partir de ahí: el primer campo
  /// que queda es el estado, o sea el número 3.
  @visibleForTesting
  static int ticksDeStat(String stat) {
    final cierre = stat.lastIndexOf(')');
    if (cierre < 0) return 0;
    final campos = stat.substring(cierre + 1).trim().split(RegExp(r'\s+'));
    // utime y stime son los campos 14 y 15; contando desde el 3, el 11 y el 12.
    if (campos.length < 13) return 0;
    final utime = int.tryParse(campos[11]) ?? 0;
    final stime = int.tryParse(campos[12]) ?? 0;
    return (utime + stime) * _cienNanosPorTick;
  }

  /// 4 KiB en x86-64 y arm64, que son las dos arquitecturas donde esto corre.
  /// Preguntárselo al sistema exigiría lanzar `getconf`, y hacerlo cada tres
  /// segundos costaría más que la medida entera.
  static const int _tamanoDePagina = 4096;

  /// `USER_HZ` vale 100 en Linux —es ABI, no depende del `CONFIG_HZ` del
  /// kernel—, así que cada tick son 10 ms, o sea 100.000 unidades de 100 ns.
  static const int _cienNanosPorTick = 100000;

  /// Working set y ticks de CPU de un pid, en una sola apertura del proceso.
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
