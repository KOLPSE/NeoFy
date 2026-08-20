import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'reproductor_del_sistema.dart';

export 'reproductor_del_sistema.dart' show EstadoDelSistema, caratulaEnDisco;

class MprisService {
  MprisService({
    required this.onPlayPause,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onRaise,
    required this.estado,
  });

  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  final Future<void> Function(int microsegundos) onSeek;

  final void Function() onRaise;

  final EstadoDelSistema Function() estado;

  DBusClient? _cliente;
  _ObjetoMpris? _objeto;

  bool get activo => _objeto != null;

  Future<void> start() async {
    if (!Platform.isLinux || _objeto != null) return;
    try {
      final cliente = DBusClient.session();
      final objeto = _ObjetoMpris(this);
      await cliente.registerObject(objeto);
      await cliente.requestName('org.mpris.MediaPlayer2.neofy');
      _cliente = cliente;
      _objeto = objeto;
    } catch (e) {
      debugPrint('MPRIS no disponible: $e');
      await stop();
    }
  }

  String? _ultimaFirma;

  void notificarCambio() {
    final objeto = _objeto;
    if (objeto == null) return;
    final e = estado();
    final track = e.track;
    final caratula = track == null ? null : caratulaEnDisco(track);
    final firma = '${track?.uri}|${e.estadoDeReproduccion}|${e.volumen}|'
        '${e.puedeSaltar}|${e.puedeVolver}|$caratula';
    if (firma != _ultimaFirma) {
      _ultimaFirma = firma;
      unawaited(objeto.emitirCambios());
    }
    if (track != null && caratula == null) {
      _caratulas.asegurar(track, notificarCambio);
    }
  }

  late final DescargadorDeCaratula _caratulas =
      DescargadorDeCaratula(() => estado().track?.uri);

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

String _rutaDeTrack(String id) {
  final limpio = id.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return limpio.isEmpty
      ? '/xyz/neogex/neofy/desconocida'
      : '/xyz/neogex/neofy/track/$limpio';
}

Map<String, Object> metadatosMpris(Track? track) {
  if (track == null) return const {};
  final datos = <String, Object>{
    'mpris:trackid': _rutaDeTrack(track.id),
    'mpris:length': track.durationMs * 1000,
    'xesam:title': track.name,
    'xesam:album': track.album,
    'xesam:url': track.uri,
    'xesam:artist':
        track.artists.isEmpty ? const <String>[] : track.artists.split(', '),
  };

  final caratula = caratulaEnDisco(track);
  if (caratula != null) datos['mpris:artUrl'] = caratula;
  return datos;
}

class _ObjetoMpris extends DBusObject {
  _ObjetoMpris(this.servicio)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final MprisService servicio;

  static const _raiz = 'org.mpris.MediaPlayer2';
  static const _player = 'org.mpris.MediaPlayer2.Player';

  Future<void> emitirCambios() =>
      emitPropertiesChanged(_player, changedProperties: _propiedadesDelPlayer());

  Map<String, DBusValue> _propiedadesDeLaRaiz() => {
        'CanRaise': const DBusBoolean(true),
        'CanQuit': const DBusBoolean(false),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('NeoFy'),
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
      'Rate': const DBusDouble(1),
      'MinimumRate': const DBusDouble(1),
      'MaximumRate': const DBusDouble(1),
    };
  }

  Map<String, DBusValue> _metadatos(Track? track) =>
      metadatosMpris(track).map((clave, valor) => MapEntry(clave, switch (valor) {
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
    return DBusMethodErrorResponse.propertyReadOnly();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == _raiz) {
      if (call.name == 'Raise') {
        servicio.onRaise();
        return DBusMethodSuccessResponse();
      }
      return DBusMethodErrorResponse.unknownMethod();
    }
    if (call.interface != _player) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    debugPrint('MPRIS: ${call.name} <- ${call.sender}');

    switch (call.name) {
      case 'PlayPause':
        await servicio.onPlayPause();
      case 'Play':
        await servicio.onPlay();
      case 'Pause':
        await servicio.onPause();
      case 'Stop':
        await servicio.onPause();
      case 'Next':
        await servicio.onNext();
      case 'Previous':
        await servicio.onPrevious();
      case 'Seek':
        final delta = (call.values.first as DBusInt64).value;
        final destino = servicio.estado().posicionMs * 1000 + delta;
        await servicio.onSeek(destino < 0 ? 0 : destino);
      case 'SetPosition':
        final us = (call.values[1] as DBusInt64).value;
        await servicio.onSeek(us < 0 ? 0 : us);
      case 'OpenUri':
        return DBusMethodErrorResponse.unknownMethod();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

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
