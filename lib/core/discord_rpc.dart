import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

/// Integración con Rich Presence de Discord (Discord RPC).
///
/// Permite mostrar en el perfil de Discord qué canción está sonando en NeoFy,
/// la siguiente pista de la cola y un botón con enlace al repositorio de GitHub.
///
/// Funciona hablando directamente con el socket o named pipe local de Discord
/// mediante el protocolo Discord IPC (framing de 8 bytes + payload JSON), sin
/// librerías externas para no engordar el binario ni la memoria.
///
/// Si Discord no está abierto o se cierra, no se lanza ninguna excepción ni
/// aviso visible: degrada en silencio y reintenta la conexión periódicamente
/// mientras el ajuste esté activo.
class DiscordRpc {
  DiscordRpc({DiscordTransport? transporte})
      : _transporte = transporte ?? _crearTransporte();

  final DiscordTransport _transporte;
  String _clientId = '';
  bool _activo = false;
  Timer? _reintentoTimer;
  int _nonce = 0;

  String? _ultimoTrackUri;
  Track? _siguienteTrack;
  bool _cargandoCola = false;

  Track? _ultimoTrack;
  bool _ultimoSonando = false;
  int _ultimoProgresoMs = 0;
  int? _ultimoStartTime;
  String? _ultimaFirma;

  String get clientId => _clientId;
  bool get activo => _activo;
  bool get conectado => _transporte.conectado;

  /// Arranca o actualiza el Rich Presence con el [clientId] indicado.
  void start(String clientId) {
    final nuevoId = clientId.trim();
    if (nuevoId.isEmpty) {
      unawaited(stop());
      return;
    }
    if (_activo && _clientId == nuevoId && _transporte.conectado) {
      return;
    }
    _clientId = nuevoId;
    _activo = true;
    _iniciarConexion();

    _reintentoTimer?.cancel();
    _reintentoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_activo && !_transporte.conectado) {
        _iniciarConexion();
      }
    });
  }

  void _iniciarConexion() {
    if (!_activo || _clientId.isEmpty) return;
    unawaited(_conectar());
  }

  Future<void> _conectar() async {
    try {
      final ok = await _transporte.conectar(_clientId);
      if (ok && _activo) {
        if (_ultimoTrack != null) {
          await _enviarActividad(
            track: _ultimoTrack,
            siguiente: _siguienteTrack,
            sonando: _ultimoSonando,
            progresoMs: _ultimoProgresoMs,
            forzar: true,
          );
        }
      }
    } catch (_) {
      // Degradar en silencio sin interrumpir al usuario.
    }
  }

  /// Detiene el Rich Presence y cierra la conexión.
  Future<void> stop() async {
    _activo = false;
    _reintentoTimer?.cancel();
    _reintentoTimer = null;
    _ultimoTrackUri = null;
    _siguienteTrack = null;
    _ultimoTrack = null;
    _ultimaFirma = null;
    _ultimoStartTime = null;

    if (_transporte.conectado) {
      try {
        await _enviarPayloadLimpiar();
      } catch (_) {}
    }
    await _transporte.desconectar();
  }

  /// Limpia la presencia en Discord sin apagar el servicio.
  Future<void> limpiar() async {
    _ultimoTrackUri = null;
    _siguienteTrack = null;
    _ultimoTrack = null;
    _ultimaFirma = null;
    _ultimoStartTime = null;

    if (_transporte.conectado) {
      try {
        await _enviarPayloadLimpiar();
      } catch (_) {}
    }
  }

  /// Actualiza la presencia actual según la pista en reproducción.
  ///
  /// Solo pide la cola de reproducción cuando cambia el URI de la pista actual,
  /// evitando saturar la API de Spotify con peticiones innecesarias.
  void actualizarActividad({
    required Track? track,
    required bool sonando,
    required int progresoMs,
    required Future<List<Track>> Function() obtenerCola,
  }) {
    _ultimoTrack = track;
    _ultimoSonando = sonando;
    _ultimoProgresoMs = progresoMs;

    if (track == null) {
      unawaited(limpiar());
      return;
    }

    if (!_activo || _clientId.isEmpty) return;

    if (track.uri != _ultimoTrackUri) {
      _ultimoTrackUri = track.uri;
      _siguienteTrack = null;
      if (!_cargandoCola) {
        _cargandoCola = true;
        obtenerCola().then((cola) {
          _cargandoCola = false;
          if (_ultimoTrackUri == track.uri) {
            _siguienteTrack = cola.isNotEmpty ? cola.first : null;
            unawaited(_enviarActividad(
              track: track,
              siguiente: _siguienteTrack,
              sonando: _ultimoSonando,
              progresoMs: _ultimoProgresoMs,
            ));
          }
        }).catchError((_) {
          _cargandoCola = false;
        });
      }
    }

    unawaited(_enviarActividad(
      track: track,
      siguiente: _siguienteTrack,
      sonando: sonando,
      progresoMs: progresoMs,
    ));
  }

  Future<void> _enviarActividad({
    required Track? track,
    Track? siguiente,
    required bool sonando,
    required int progresoMs,
    bool forzar = false,
  }) async {
    if (!_activo || !_transporte.conectado || track == null) return;

    final ahora = DateTime.now();
    final startTime = ahora.millisecondsSinceEpoch - progresoMs;
    final firma = '${track.uri}|$sonando|${siguiente?.uri}';

    final saltoPosicion = _ultimoStartTime != null &&
        (startTime - _ultimoStartTime!).abs() > 3000;

    if (!forzar && firma == _ultimaFirma && !saltoPosicion) {
      return;
    }

    _ultimaFirma = firma;
    _ultimoStartTime = startTime;

    final actividad = construirActividad(
      track: track,
      siguiente: siguiente,
      sonando: sonando,
      progresoMs: progresoMs,
      ahora: ahora,
    );

    final payload = construirPayloadSetActivity(
      pid: pid,
      nonce: (++_nonce).toString(),
      activity: actividad,
    );

    await _transporte.enviar(1, jsonEncode(payload));
  }

  Future<void> _enviarPayloadLimpiar() async {
    final payload = construirPayloadSetActivity(
      pid: pid,
      nonce: (++_nonce).toString(),
      activity: null,
    );
    await _transporte.enviar(1, jsonEncode(payload));
  }

  /// Construye el objeto `activity` para el payload `SET_ACTIVITY` de Discord.
  ///
  /// Función pura sin dependencias de red ni sockets, pensada para testing.
  static Map<String, dynamic> construirActividad({
    required Track track,
    Track? siguiente,
    required bool sonando,
    required int progresoMs,
    DateTime? ahora,
  }) {
    final stateStr = siguiente != null && siguiente.name.isNotEmpty
        ? '${track.artists} · Siguiente: ${siguiente.name}'
        : track.artists;
    final startEpoch =
        (ahora ?? DateTime.now()).millisecondsSinceEpoch - progresoMs;

    return {
      // Sin esto Discord asume el tipo 0 (Jugando) y NeoFy sale como si fuera
      // un juego. 2 es "Escuchando", el tipo pensado para reproductores.
      'type': 2,
      'details': track.name,
      'state': stateStr,
      if (sonando) 'timestamps': {'start': startEpoch},
      'assets': const {
        'large_image': 'logo',
        'large_text': 'NeoFy',
      },
      'buttons': const [
        {
          'label': 'GitHub',
          'url': 'https://github.com/KOLPSE/NeoFy',
        },
      ],
    };
  }

  /// Construye el mapa completo del frame `SET_ACTIVITY`.
  static Map<String, dynamic> construirPayloadSetActivity({
    required int pid,
    required String nonce,
    Map<String, dynamic>? activity,
  }) =>
      {
        'cmd': 'SET_ACTIVITY',
        'nonce': nonce,
        'args': {
          'pid': pid,
          'activity': activity,
        },
      };

  /// Empaqueta un mensaje según el protocolo de framing de Discord IPC:
  /// 4 bytes little-endian de opcode + 4 bytes little-endian de longitud + JSON UTF-8.
  static Uint8List empaquetar(int opcode, String jsonStr) {
    final payloadBytes = utf8.encode(jsonStr);
    final bytes = Uint8List(8 + payloadBytes.length);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, opcode, Endian.little);
    data.setUint32(4, payloadBytes.length, Endian.little);
    bytes.setRange(8, 8 + payloadBytes.length, payloadBytes);
    return bytes;
  }

  void dispose() {
    unawaited(stop());
  }
}

/// Contrato para el canal de comunicación IPC con Discord (named pipe o socket Unix).
abstract class DiscordTransport {
  bool get conectado;
  Future<bool> conectar(String clientId);
  Future<bool> enviar(int opcode, String jsonStr);
  Future<void> desconectar();
}

DiscordTransport _crearTransporte() {
  if (Platform.isWindows) return _WindowsPipeTransport();
  if (Platform.isLinux) return _LinuxSocketTransport();
  return _NoopTransport();
}

class _NoopTransport implements DiscordTransport {
  @override
  bool get conectado => false;

  @override
  Future<bool> conectar(String clientId) async => false;

  @override
  Future<bool> enviar(int opcode, String jsonStr) async => false;

  @override
  Future<void> desconectar() async {}
}

// -----------------------------------------------------------------------------
// Windows: Named Pipe con FFI de Win32 (kernel32.dll)
// -----------------------------------------------------------------------------

typedef _CreateFileWC = IntPtr Function(
  Pointer<Utf16> lpFileName,
  Uint32 dwDesiredAccess,
  Uint32 dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  Uint32 dwCreationDisposition,
  Uint32 dwFlagsAndAttributes,
  IntPtr hTemplateFile,
);
typedef _CreateFileWDart = int Function(
  Pointer<Utf16> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  int hTemplateFile,
);

typedef _ReadFileC = Int32 Function(
  IntPtr hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nNumberOfBytesToRead,
  Pointer<Uint32> lpNumberOfBytesRead,
  Pointer<Void> lpOverlapped,
);
typedef _ReadFileDart = int Function(
  int hFile,
  Pointer<Uint8> lpBuffer,
  int nNumberOfBytesToRead,
  Pointer<Uint32> lpNumberOfBytesRead,
  Pointer<Void> lpOverlapped,
);

typedef _WriteFileC = Int32 Function(
  IntPtr hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nNumberOfBytesToWrite,
  Pointer<Uint32> lpNumberOfBytesWritten,
  Pointer<Void> lpOverlapped,
);
typedef _WriteFileDart = int Function(
  int hFile,
  Pointer<Uint8> lpBuffer,
  int nNumberOfBytesToWrite,
  Pointer<Uint32> lpNumberOfBytesWritten,
  Pointer<Void> lpOverlapped,
);

typedef _CloseHandleC = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

typedef _PeekNamedPipeC = Int32 Function(
  IntPtr hNamedPipe,
  Pointer<Void> lpBuffer,
  Uint32 nBufferSize,
  Pointer<Uint32> lpBytesRead,
  Pointer<Uint32> lpTotalBytesAvail,
  Pointer<Uint32> lpBytesLeftThisMessage,
);
typedef _PeekNamedPipeDart = int Function(
  int hNamedPipe,
  Pointer<Void> lpBuffer,
  int nBufferSize,
  Pointer<Uint32> lpBytesRead,
  Pointer<Uint32> lpTotalBytesAvail,
  Pointer<Uint32> lpBytesLeftThisMessage,
);

class _WindowsPipeTransport implements DiscordTransport {
  int _handle = 0;
  bool _conectado = false;

  static final _kernel32 =
      Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;

  static final _createFile = _kernel32
      ?.lookupFunction<_CreateFileWC, _CreateFileWDart>('CreateFileW');
  static final _readFile =
      _kernel32?.lookupFunction<_ReadFileC, _ReadFileDart>('ReadFile');
  static final _writeFile =
      _kernel32?.lookupFunction<_WriteFileC, _WriteFileDart>('WriteFile');
  static final _closeHandle =
      _kernel32?.lookupFunction<_CloseHandleC, _CloseHandleDart>('CloseHandle');
  static final _peekNamedPipe = _kernel32
      ?.lookupFunction<_PeekNamedPipeC, _PeekNamedPipeDart>('PeekNamedPipe');

  @override
  bool get conectado => _conectado && _handle != 0 && _handle != -1;

  @override
  Future<bool> conectar(String clientId) async {
    await desconectar();

    final createFile = _createFile;
    final writeFile = _writeFile;
    final closeHandle = _closeHandle;
    final peekNamedPipe = _peekNamedPipe;
    final readFile = _readFile;

    if (createFile == null ||
        writeFile == null ||
        closeHandle == null ||
        peekNamedPipe == null ||
        readFile == null) {
      return false;
    }

    for (var i = 0; i < 10; i++) {
      final nombrePipe = r'\\.\pipe\discord-ipc-' + i.toString();
      final pathPtr = nombrePipe.toNativeUtf16();
      // GENERIC_READ | GENERIC_WRITE = 0xC0000000, OPEN_EXISTING = 3
      final handle = createFile(pathPtr, 0xC0000000, 0, nullptr, 3, 0, 0);
      calloc.free(pathPtr);

      if (handle == 0 || handle == -1) {
        continue;
      }

      // Enviar Handshake (Opcode 0)
      final handshakeJson = jsonEncode({'v': 1, 'client_id': clientId});
      final paquete = DiscordRpc.empaquetar(0, handshakeJson);
      final buf = calloc<Uint8>(paquete.length);
      buf.asTypedList(paquete.length).setAll(0, paquete);
      final escritos = calloc<Uint32>();

      final okEscritura =
          writeFile(handle, buf, paquete.length, escritos, nullptr);
      calloc.free(buf);
      calloc.free(escritos);

      if (okEscritura == 0) {
        closeHandle(handle);
        continue;
      }

      // Esperar respuesta READY sin bloquear el hilo
      var listo = false;
      final bytesDisp = calloc<Uint32>();
      try {
        for (var intento = 0; intento < 40; intento++) {
          final okPeek =
              peekNamedPipe(handle, nullptr, 0, nullptr, bytesDisp, nullptr);
          if (okPeek != 0 && bytesDisp.value >= 8) {
            final totalDisp = bytesDisp.value;
            final bufLectura = calloc<Uint8>(totalDisp);
            final leidos = calloc<Uint32>();
            final okRead =
                readFile(handle, bufLectura, totalDisp, leidos, nullptr);
            if (okRead != 0 && leidos.value >= 8) {
              final data = ByteData.sublistView(
                  bufLectura.asTypedList(leidos.value));
              final opcode = data.getUint32(0, Endian.little);
              final len = data.getUint32(4, Endian.little);
              if (leidos.value >= 8 + len) {
                final jsonStr = utf8.decode(
                    bufLectura.asTypedList(leidos.value).sublist(8, 8 + len));
                final decoded = jsonDecode(jsonStr);
                if (decoded is Map &&
                    (decoded['evt'] == 'READY' || opcode == 1)) {
                  listo = true;
                }
              }
            }
            calloc.free(bufLectura);
            calloc.free(leidos);
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      } catch (_) {
        // Ignorar fallo de lectura
      } finally {
        calloc.free(bytesDisp);
      }

      if (listo) {
        _handle = handle;
        _conectado = true;
        return true;
      } else {
        closeHandle(handle);
      }
    }

    return false;
  }

  @override
  Future<bool> enviar(int opcode, String jsonStr) async {
    final handle = _handle;
    final writeFile = _writeFile;
    if (!_conectado || handle == 0 || handle == -1 || writeFile == null) {
      return false;
    }

    final paquete = DiscordRpc.empaquetar(opcode, jsonStr);
    final buf = calloc<Uint8>(paquete.length);
    buf.asTypedList(paquete.length).setAll(0, paquete);
    final escritos = calloc<Uint32>();

    try {
      final ok = writeFile(handle, buf, paquete.length, escritos, nullptr);
      if (ok == 0) {
        await desconectar();
        return false;
      }
      return true;
    } catch (_) {
      await desconectar();
      return false;
    } finally {
      calloc.free(buf);
      calloc.free(escritos);
    }
  }

  @override
  Future<void> desconectar() async {
    _conectado = false;
    final handle = _handle;
    final closeHandle = _closeHandle;
    if (handle != 0 && handle != -1 && closeHandle != null) {
      closeHandle(handle);
    }
    _handle = 0;
  }
}

// -----------------------------------------------------------------------------
// Linux: Unix Domain Socket
// -----------------------------------------------------------------------------

class _LinuxSocketTransport implements DiscordTransport {
  Socket? _socket;
  bool _conectado = false;

  @override
  bool get conectado => _conectado && _socket != null;

  @override
  Future<bool> conectar(String clientId) async {
    await desconectar();

    final directorios = [
      Platform.environment['XDG_RUNTIME_DIR'],
      Platform.environment['TMPDIR'],
      '/tmp',
    ].whereType<String>().where((d) => d.isNotEmpty && Directory(d).existsSync());

    for (final dir in directorios) {
      for (var i = 0; i < 10; i++) {
        final ruta = p.join(dir, 'discord-ipc-$i');
        if (!File(ruta).existsSync()) continue;

        try {
          final s = await Socket.connect(
            InternetAddress(ruta, type: InternetAddressType.unix),
            0,
            timeout: const Duration(seconds: 2),
          );

          final completer = Completer<bool>();
          final sub = s.listen(
            (bytes) {
              if (!completer.isCompleted && bytes.length >= 8) {
                try {
                  final data = ByteData.sublistView(Uint8List.fromList(bytes));
                  final len = data.getUint32(4, Endian.little);
                  if (bytes.length >= 8 + len) {
                    final jsonStr = utf8.decode(bytes.sublist(8, 8 + len));
                    final decoded = jsonDecode(jsonStr);
                    if (decoded is Map &&
                        (decoded['evt'] == 'READY' ||
                            decoded['cmd'] == 'DISPATCH')) {
                      completer.complete(true);
                      return;
                    }
                  }
                } catch (_) {}
              }
            },
            onDone: () => desconectar(),
            onError: (_) => desconectar(),
          );

          final paquete = DiscordRpc.empaquetar(
              0, jsonEncode({'v': 1, 'client_id': clientId}));
          s.add(paquete);
          await s.flush();

          final ok = await completer.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );

          if (ok) {
            _socket = s;
            _conectado = true;
            return true;
          } else {
            await sub.cancel();
            s.destroy();
          }
        } catch (_) {
          // Intentar el siguiente socket disponible
        }
      }
    }

    return false;
  }

  @override
  Future<bool> enviar(int opcode, String jsonStr) async {
    final s = _socket;
    if (s == null || !_conectado) return false;
    try {
      final paquete = DiscordRpc.empaquetar(opcode, jsonStr);
      s.add(paquete);
      await s.flush();
      return true;
    } catch (_) {
      await desconectar();
      return false;
    }
  }

  @override
  Future<void> desconectar() async {
    _conectado = false;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }
}
