import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reproductor_del_sistema.dart';

export 'reproductor_del_sistema.dart' show EstadoDelSistema;

/// Integración con los controles multimedia de Windows.
///
/// Es el gemelo de [MprisService], y hace por Windows lo que MPRIS hace por
/// Linux: contarle al sistema que NeoFy es un reproductor de audio y no una
/// ventana cualquiera que resulta que hace ruido. De ahí salen dos cosas que
/// hasta ahora no existían:
///
/// - **El panel multimedia del centro de control**, el mismo que aparece al
///   pulsar una tecla de volumen, con carátula, título, artista, barra de
///   progreso y botones. Es lo que Windows llama SMTC.
/// - **Los botones bajo la miniatura de la barra de tareas**, los que salen al
///   dejar el ratón encima del icono de la app.
///
/// Las dos son COM/WinRT y viven en el runner de C++ (`windows/runner/`),
/// porque desde Dart no se llega a ninguna de ellas; aquí solo se habla por el
/// canal `neofy/system_media`. El reparto es el mismo que con las teclas
/// multimedia: lo que necesita un HWND se hace en C++ y lo que es lógica, aquí.
class SmtcService {
  SmtcService({
    required this.onPlayPause,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.estado,
  });

  static const _canal = MethodChannel('neofy/system_media');

  final Future<void> Function() onPlayPause;

  /// ⚠️ `Play` no es `onPlayPause`: el panel del sistema distingue las dos
  /// cosas y manda `Play` a secas cuando el usuario pulsa reproducir. Mapearlo
  /// al toggle pausaría lo que ya está sonando. Es la misma trampa que en MPRIS.
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  /// Salto absoluto, en **milisegundos**. El runner ya convierte desde las
  /// unidades de 100 ns en las que cuenta WinRT.
  final Future<void> Function(int milisegundos) onSeek;

  /// De dónde se lee lo que hay que publicar. Función y no valor porque el
  /// estado cambia cada pocos segundos y esto vive todo lo que dure la app.
  final EstadoDelSistema Function() estado;

  bool _activo = false;

  bool get activo => _activo;

  void start() {
    if (!Platform.isWindows || _activo) return;
    _canal.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          await onPlayPause();
        case 'play':
          await onPlay();
        case 'pause':
          await onPause();
        // No hay "parar" en esta app: lo más cercano es pausar.
        case 'stop':
          await onPause();
        case 'next':
          await onNext();
        case 'previous':
          await onPrevious();
        case 'seek':
          final ms = call.arguments;
          if (ms is int) await onSeek(ms < 0 ? 0 : ms);
      }
      return null;
    });
    _activo = true;
    notificarCambio();
  }

  Future<void> stop() async {
    if (!_activo) return;
    _activo = false;
    _canal.setMethodCallHandler(null);
    // Se manda un último estado vacío para que el panel del sistema no se quede
    // enseñando la canción de una sesión que ya no existe. Al cerrar la app de
    // esto se encarga además el runner, pero cerrar sesión no destruye la
    // ventana y ahí no habría nadie más que lo hiciera.
    await _mandar(EstadoDelSistema.vacio, null);
  }

  /// Firma de lo último que se publicó, para no repetirse.
  String? _ultimaFirma;

  late final DescargadorDeCaratula _caratulas =
      DescargadorDeCaratula(() => estado().track?.uri);

  /// Avisa al sistema de que ha cambiado la canción o el estado.
  ///
  /// ⚠️ **Se puede llamar en cada sondeo, y así se llama.** El `ChangeNotifier`
  /// de `PlayerController` salta cada 3 segundos aunque no haya cambiado nada;
  /// por eso se compara una firma de lo que el panel enseña de verdad y se sale
  /// sin mandar nada si es la misma.
  ///
  /// **La posición queda fuera de la firma a propósito**, igual que en MPRIS:
  /// Windows la extrapola solo mientras el estado sea "reproduciendo", así que
  /// mandarla cada tres segundos sería trabajo para nada. Lo que sí hay que
  /// avisar es cuando *da un salto*, y de eso va [notificarSalto].
  void notificarCambio() {
    if (!_activo) return;
    final e = estado();
    final track = e.track;
    final caratula = track == null ? null : ficheroDeCaratula(track)?.path;
    // La carátula entra en la firma a propósito: cuando termina de bajarse, la
    // firma cambia sola y se vuelve a mandar con ella. Sin eso, el aviso del
    // cambio de canción llega **antes** que la descarga y el panel se queda con
    // el hueco hasta la canción siguiente.
    final firma = '${track?.uri}|${e.estadoDeReproduccion}|'
        '${e.puedeSaltar}|${e.puedeVolver}|$caratula';
    if (firma != _ultimaFirma) {
      _ultimaFirma = firma;
      unawaited(_mandar(e, caratula));
    }
    if (track != null && caratula == null) {
      _caratulas.asegurar(track, notificarCambio);
    }
  }

  /// Anuncia un salto de posición.
  ///
  /// Windows lleva la cuenta por su cuenta desde la última posición que se le
  /// dio, así que sin esto la barra del panel se queda donde estaba: el usuario
  /// arrastra dentro de NeoFy y el panel del sistema sigue enseñando el minuto
  /// de antes hasta que cambie la canción.
  void notificarSalto(int posicionMs) {
    if (!_activo) return;
    final e = estado();
    final track = e.track;
    final caratula = track == null ? null : ficheroDeCaratula(track)?.path;
    unawaited(_mandar(e, caratula, posicionMs: posicionMs));
  }

  Future<void> _mandar(EstadoDelSistema e, String? caratula,
      {int? posicionMs}) async {
    final track = e.track;
    try {
      await _canal.invokeMethod<void>('update', <String, Object?>{
        // No es lo mismo que estar en pausa: sin canción el sistema tiene que
        // quitar el reproductor del panel, no dejarlo ahí con los botones
        // muertos.
        'hayCancion': track != null,
        'sonando': e.sonando,
        'titulo': track?.name ?? '',
        'artista': track?.artists ?? '',
        'album': track?.album ?? '',
        // Ruta en disco, nunca la url: el panel del sistema no debe salir a la
        // red, y la app ya tiene la imagen bajada.
        'caratula': caratula ?? '',
        'puedeSaltar': e.puedeSaltar,
        'puedeVolver': e.puedeVolver,
        'duracionMs': track?.durationMs ?? 0,
        'posicionMs': posicionMs ?? e.posicionMs,
      });
    } on MissingPluginException {
      // El runner no trae el canal (una compilación anterior a esto, o los
      // tests). Perder el panel del sistema no es motivo para nada.
    } on PlatformException catch (error) {
      debugPrint('Controles del sistema: $error');
    }
  }
}
