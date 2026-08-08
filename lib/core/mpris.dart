import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'art_cache.dart';
import 'models.dart';

/// Integración con el escritorio de Linux por MPRIS.
///
/// Es el equivalente de las teclas multimedia de Windows, y de paso bastante
/// más: en Windows hubo que escribir C++ (`RegisterHotKey` en
/// `windows/runner/flutter_window.cpp`) porque desde Dart no hay forma de ver un
/// `WM_HOTKEY`. En Linux el escritorio ya escucha esas teclas, y lo que busca es
/// un reproductor que hable MPRIS por D-Bus para mandárselas. Anunciarse aquí
/// consigue tres cosas de una vez:
///
/// - Las teclas multimedia y el botón de los cascos llegan **con la ventana
///   escondida**, sin registrar nada a mano.
/// - NeoFy sale en el widget de reproducción de KDE y GNOME, con carátula,
///   título y botones.
/// - `playerctl` y compañía funcionan sin plugin ninguno, igual que el Stream
///   Deck funciona en Windows porque el control va por la Web API.
///
/// Todo esto con `package:dbus`, que es Dart puro: no hay una línea de código
/// nativo en el runner de Linux.
class MprisService {
  MprisService({
    required this.onPlayPause,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.estado,
  });

  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  /// Salto absoluto, en microsegundos desde el principio de la canción. MPRIS
  /// trabaja siempre en µs; la Web API, en ms.
  final Future<void> Function(int microsegundos) onSeek;

  /// De dónde se lee lo que hay que publicar. Se pide como función y no como
  /// valor porque el estado cambia cada pocos segundos y el objeto de D-Bus
  /// vive todo lo que dure la app.
  final EstadoMpris Function() estado;

  DBusClient? _cliente;
  _ObjetoMpris? _objeto;

  bool get activo => _objeto != null;

  /// Se anuncia en el bus de sesión.
  ///
  /// No lanza: quedarse sin MPRIS significa perder las teclas multimedia y el
  /// widget del escritorio, que es una lástima pero no impide reproducir nada.
  /// Un contenedor sin bus de sesión, o un segundo NeoFy que llegue tarde al
  /// nombre, no pueden tumbar el arranque de la app.
  Future<void> start() async {
    if (!Platform.isLinux || _objeto != null) return;
    try {
      final cliente = DBusClient.session();
      final objeto = _ObjetoMpris(this);
      await cliente.registerObject(objeto);
      // El nombre lleva sufijo por especificación: org.mpris.MediaPlayer2.<lo
      // que sea>. Sin `replaceExisting` a propósito — si ya hay un NeoFy en el
      // bus, el que manda es el primero, que es el que tiene la ventana.
      await cliente.requestName('org.mpris.MediaPlayer2.neofy');
      _cliente = cliente;
      _objeto = objeto;
    } catch (e) {
      debugPrint('MPRIS no disponible: $e');
      await stop();
    }
  }

  /// Firma de lo último que se publicó, para no repetirse.
  String? _ultimaFirma;

  /// Avisa al escritorio de que ha cambiado la canción o el estado.
  ///
  /// ⚠️ **Se puede llamar en cada sondeo, y de hecho así se llama.** El
  /// `ChangeNotifier` de `PlayerController` salta cada 3 segundos aunque no
  /// haya cambiado nada, y emitir por el bus cada vez haría trabajar al
  /// escritorio para nada. Por eso aquí se compara una firma de lo que MPRIS
  /// publica de verdad y se sale sin emitir si es la misma.
  ///
  /// No basta con mirar la canción: pausar no la cambia, y sin esto el widget
  /// del escritorio se quedaría diciendo "reproduciendo" con la música parada.
  /// La posición queda fuera a propósito — avanza sola y es justo lo que la
  /// especificación dice que **no** hay que anunciar (ver [notificarSalto]).
  void notificarCambio() {
    final objeto = _objeto;
    if (objeto == null) return;
    final e = estado();
    final track = e.track;
    final caratula = track == null ? null : caratulaEnDisco(track);
    // La carátula entra en la firma a propósito: cuando termina de bajarse, la
    // firma cambia sola y se vuelve a anunciar con ella. Sin eso, el anuncio
    // del cambio de canción llega **antes** que la descarga y el escritorio se
    // queda con el hueco para siempre.
    final firma = '${track?.uri}|${e.estadoDeReproduccion}|${e.volumen}|'
        '${e.puedeSaltar}|${e.puedeVolver}|$caratula';
    if (firma != _ultimaFirma) {
      _ultimaFirma = firma;
      unawaited(objeto.emitirCambios());
    }
    if (track != null && caratula == null) _bajarCaratula(track);
  }

  /// Uri de la canción cuya carátula se está bajando, para no pedir la misma
  /// una y otra vez en cada sondeo mientras la descarga está en curso.
  String? _bajando;

  /// Se trae la carátula que falta y vuelve a anunciar los metadatos.
  ///
  /// El escritorio no sabe volver a preguntar: si el anuncio del cambio de
  /// canción va sin `artUrl`, ahí se queda. Así que cuando no está en disco se
  /// pide y se reanuncia al llegar.
  void _bajarCaratula(Track track) {
    final url = track.artMedium ?? track.artSmall;
    if (url == null || _bajando == track.uri) return;
    _bajando = track.uri;
    unawaited(ArtCache.file(url).then((_) {
      _bajando = null;
      // Bajar tarda, y para entonces puede estar sonando otra cosa: reanunciar
      // la carátula de la canción anterior dejaría el escritorio desincronizado.
      if (estado().track?.uri != track.uri) return;
      notificarCambio();
    }).catchError((_) {
      _bajando = null;
    }));
  }

  /// Anuncia un salto de posición.
  ///
  /// Va por su propia señal y no por `PropertiesChanged`: la especificación dice
  /// expresamente que `Position` **no** se anuncia como propiedad cambiada,
  /// porque avanza sola y llenaría el bus de mensajes. Quien quiera el valor
  /// exacto lo pregunta; lo que hay que avisar es cuando *da un salto*.
  void notificarSalto(int microsegundos) {
    final objeto = _objeto;
    if (objeto == null) return;
    unawaited(objeto.emitSignal('org.mpris.MediaPlayer2.Player', 'Seeked',
        [DBusInt64(microsegundos)]));
  }

  Future<void> stop() async {
    final cliente = _cliente;
    _objeto = null;
    _cliente = null;
    if (cliente != null) {
      try {
        await cliente.close();
      } catch (_) {}
    }
  }
}

/// Lo que MPRIS necesita saber del reproductor en un momento dado.
class EstadoMpris {
  const EstadoMpris({
    required this.track,
    required this.sonando,
    required this.posicionMs,
    required this.puedeSaltar,
    required this.puedeVolver,
    required this.volumen,
  });

  final Track? track;
  final bool sonando;
  final int posicionMs;
  final bool puedeSaltar;
  final bool puedeVolver;

  /// 0..100, como lo da la Web API. MPRIS lo quiere de 0.0 a 1.0.
  final int? volumen;

  /// `Playing`, `Paused` o `Stopped`, que son los tres valores que admite la
  /// especificación.
  String get estadoDeReproduccion {
    if (track == null) return 'Stopped';
    return sonando ? 'Playing' : 'Paused';
  }
}

/// Los metadatos de la canción, con los nombres del vocabulario xesam que
/// espera la especificación.
///
/// Devuelve tipos de Dart y no de D-Bus para poder probarlo sin bus: la
/// codificación es un paso aparte. Las tres trampas están en el cuerpo.
Map<String, Object> metadatosMpris(Track? track) {
  if (track == null) return const {};
  final datos = <String, Object>{
    // ⚠️ El trackid es una **ruta de objeto**, no una cadena cualquiera: tiene
    // que empezar por `/` y no puede acabar en `/`. Los ids de Spotify son
    // alfanuméricos y valen, pero las pistas locales llegan con el id vacío y
    // dejarían `/xyz/neogex/neofy/track/`, que es inválida: D-Bus rechazaría el
    // diccionario entero y se perdería hasta el título por no tener id.
    'mpris:trackid': track.id.isEmpty
        ? '/xyz/neogex/neofy/desconocida'
        : '/xyz/neogex/neofy/track/${track.id}',
    // MPRIS trabaja en microsegundos y la Web API en milisegundos. Sin
    // convertir, una canción de tres minutos se anuncia como de 0,2 segundos.
    'mpris:length': track.durationMs * 1000,
    'xesam:title': track.name,
    'xesam:album': track.album,
    'xesam:url': track.uri,
    // `Track.artists` viene ya unido con ", " para pintarlo de un tirón en una
    // fila; MPRIS lo quiere troceado o el escritorio enseña los nombres pegados
    // como si fueran un solo artista.
    'xesam:artist':
        track.artists.isEmpty ? const <String>[] : track.artists.split(', '),
  };

  final caratula = caratulaEnDisco(track);
  if (caratula != null) datos['mpris:artUrl'] = caratula;
  return datos;
}

/// La carátula de [track] que **ya esté descargada**, como `file://`, o `null`.
///
/// Se sirve desde disco para que el escritorio la pinte sin bajar nada y sin
/// gastar cuota; no se puede esperar a una descarga para contestar por D-Bus, y
/// dar la url `http` haría que el escritorio se la bajara por su cuenta.
///
/// ⚠️ **Se prueban las dos variantes, y esa es la corrección de un fallo real**:
/// unas carátulas salían en el reproductor del sistema y otras no, sin patrón
/// aparente. La causa es que [ArtImage] elige qué variante descarga **según los
/// píxeles reales** en los que va a pintarla: las filas de una lista caben en la
/// de 64 y las tarjetas de la portada necesitan la de 300. Pidiendo aquí solo la
/// mediana, las canciones que solo se habían visto en una lista no tenían ese
/// fichero y se quedaban sin carátula.
String? caratulaEnDisco(Track track) {
  for (final url in [track.artMedium, track.artSmall]) {
    if (url == null) continue;
    final fichero = ArtCache.ficheroSiEstaEnDisco(url);
    if (fichero != null) return fichero.uri.toString();
  }
  return null;
}

/// El objeto que se cuelga de `/org/mpris/MediaPlayer2`.
class _ObjetoMpris extends DBusObject {
  _ObjetoMpris(this.servicio)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final MprisService servicio;

  static const _raiz = 'org.mpris.MediaPlayer2';
  static const _player = 'org.mpris.MediaPlayer2.Player';

  Future<void> emitirCambios() =>
      emitPropertiesChanged(_player, changedProperties: _propiedadesDelPlayer());

  // ------------------------------------------------------------- propiedades

  Map<String, DBusValue> _propiedadesDeLaRaiz() => {
        // Lo que el escritorio hace al pulsar el nombre del reproductor. Se
        // puede: la app sabe salir de la bandeja.
        'CanRaise': const DBusBoolean(true),
        'CanQuit': const DBusBoolean(false),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('NeoFy'),
        // Tiene que ser el nombre del .desktop sin extension, o el escritorio no
        // encuentra el icono del reproductor en su widget.
        'DesktopEntry': const DBusString('xyz.neogex.neofy'),
        'SupportedUriSchemes': DBusArray.string([]),
        'SupportedMimeTypes': DBusArray.string([]),
      };

  Map<String, DBusValue> _propiedadesDelPlayer() {
    final e = servicio.estado();
    return {
      'PlaybackStatus': DBusString(e.estadoDeReproduccion),
      'Metadata': DBusDict.stringVariant(_metadatos(e.track)),
      'Position': DBusInt64(e.posicionMs * 1000),
      'Volume': DBusDouble((e.volumen ?? 100) / 100),
      'CanGoNext': DBusBoolean(e.puedeSaltar),
      'CanGoPrevious': DBusBoolean(e.puedeVolver),
      'CanPlay': DBusBoolean(e.track != null),
      'CanPause': DBusBoolean(e.track != null),
      'CanSeek': DBusBoolean(e.track != null),
      'CanControl': const DBusBoolean(true),
      // Se anuncia 1.0 fijo: no ofrecemos cambiar la velocidad, y decir otra
      // cosa haria que el escritorio calculara mal la posicion entre consultas.
      'Rate': const DBusDouble(1),
      'MinimumRate': const DBusDouble(1),
      'MaximumRate': const DBusDouble(1),
    };
  }

  /// Los metadatos ya codificados para el bus.
  Map<String, DBusValue> _metadatos(Track? track) =>
      metadatosMpris(track).map((clave, valor) => MapEntry(clave, switch (valor) {
            // El trackid es lo unico que no es una cadena normal: D-Bus lo
            // quiere tipado como ruta de objeto, y mandarlo como texto hace que
            // el escritorio descarte los metadatos enteros.
            _ when clave == 'mpris:trackid' =>
              DBusObjectPath(valor as String),
            final int n => DBusInt64(n),
            final List<String> l => DBusArray.string(l),
            _ => DBusString(valor as String),
          }));

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final propiedades = switch (interface) {
      _raiz => _propiedadesDeLaRaiz(),
      _player => _propiedadesDelPlayer(),
      _ => const <String, DBusValue>{},
    };
    final valor = propiedades[name];
    if (valor == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(valor);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(switch (interface) {
      _raiz => _propiedadesDeLaRaiz(),
      _player => _propiedadesDelPlayer(),
      _ => const <String, DBusValue>{},
    });
  }

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    // El volumen se deja de solo lectura a proposito. La Web API lo aplica con
    // un par de segundos de retraso y el escritorio, al no ver el cambio,
    // reenviaria el valor: acabaria en el tira y afloja que ya obligo a que los
    // sliders manden en `onChangeEnd` y no en `onChanged`.
    return DBusMethodErrorResponse.propertyReadOnly();
  }

  // ----------------------------------------------------------------- metodos

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == _raiz) {
      return switch (call.name) {
        // Quien la llama es el widget del escritorio al pulsar el nombre del
        // reproductor. Sacar la ventana de la bandeja lo hace main.dart.
        'Raise' => DBusMethodSuccessResponse(),
        _ => DBusMethodErrorResponse.unknownMethod(),
      };
    }
    if (call.interface != _player) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    // Se deja rastro de quién pide qué. En Linux, MPRIS es **la única vía** por
    // la que algo de fuera puede pausar la música (las teclas multimedia van por
    // aquí), así que cuando alguien reporta que se pausa sola, esta línea dice
    // si vino de fuera y de qué programa.
    debugPrint('MPRIS: ${call.name} <- ${call.sender}');

    switch (call.name) {
      case 'PlayPause':
        await servicio.onPlayPause();
      case 'Play':
        await servicio.onPlay();
      case 'Pause':
        await servicio.onPause();
      case 'Stop':
        // No hay "parar" en esta app: lo mas cercano es pausar.
        await servicio.onPause();
      case 'Next':
        await servicio.onNext();
      case 'Previous':
        await servicio.onPrevious();
      case 'Seek':
        // Seek es RELATIVO y puede venir en negativo; SetPosition es absoluto.
        // Confundirlos manda la cancion al principio en cada pulsacion de la
        // flecha de adelantar del escritorio.
        final delta = (call.values.first as DBusInt64).value;
        final destino = servicio.estado().posicionMs * 1000 + delta;
        await servicio.onSeek(destino < 0 ? 0 : destino);
      case 'SetPosition':
        // El primer argumento es el trackid; se ignora porque solo hay una
        // cancion sonando y no llevamos lista de reproduccion en el bus.
        final us = (call.values[1] as DBusInt64).value;
        await servicio.onSeek(us < 0 ? 0 : us);
      case 'OpenUri':
        return DBusMethodErrorResponse.unknownMethod();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  // --------------------------------------------------------------- introspec

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(_raiz, methods: [
          DBusIntrospectMethod('Raise'),
        ], properties: [
          DBusIntrospectProperty('CanRaise', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanQuit', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('HasTrackList', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Identity', DBusSignature('s'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('DesktopEntry', DBusSignature('s'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('SupportedUriSchemes', DBusSignature('as'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('SupportedMimeTypes', DBusSignature('as'),
              access: DBusPropertyAccess.read),
        ]),
        DBusIntrospectInterface(_player, methods: [
          DBusIntrospectMethod('PlayPause'),
          DBusIntrospectMethod('Play'),
          DBusIntrospectMethod('Pause'),
          DBusIntrospectMethod('Stop'),
          DBusIntrospectMethod('Next'),
          DBusIntrospectMethod('Previous'),
          DBusIntrospectMethod('Seek', args: [
            DBusIntrospectArgument(
                DBusSignature('x'), DBusArgumentDirection.in_,
                name: 'Offset'),
          ]),
          DBusIntrospectMethod('SetPosition', args: [
            DBusIntrospectArgument(
                DBusSignature('o'), DBusArgumentDirection.in_,
                name: 'TrackId'),
            DBusIntrospectArgument(
                DBusSignature('x'), DBusArgumentDirection.in_,
                name: 'Position'),
          ]),
        ], signals: [
          DBusIntrospectSignal('Seeked', args: [
            DBusIntrospectArgument(
                DBusSignature('x'), DBusArgumentDirection.out,
                name: 'Position'),
          ]),
        ], properties: [
          DBusIntrospectProperty('PlaybackStatus', DBusSignature('s'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Metadata', DBusSignature('a{sv}'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Position', DBusSignature('x'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Volume', DBusSignature('d'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Rate', DBusSignature('d'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('MinimumRate', DBusSignature('d'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('MaximumRate', DBusSignature('d'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanGoNext', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanGoPrevious', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanPlay', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanPause', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanSeek', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanControl', DBusSignature('b'),
              access: DBusPropertyAccess.read),
        ]),
      ];
}
