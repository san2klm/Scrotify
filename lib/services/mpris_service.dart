import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'navidrome_service.dart';
import 'player_controller.dart';

/// Controles multimedia de Linux (MPRIS 2): teclas multimedia, widgets del
/// escritorio, `playerctl`, KDE Connect… Solo Linux; en otras plataformas
/// [start] no hace nada.
///
/// Expone `org.mpris.MediaPlayer2` y `org.mpris.MediaPlayer2.Player` en el bus
/// de sesión con el nombre `org.mpris.MediaPlayer2.scrotify`.
class MprisService {
  MprisService(this._player);

  final PlayerController _player;

  DBusClient? _client;
  VoidCallback? _listener;

  static const busName = 'org.mpris.MediaPlayer2.scrotify';

  /// `false` fuera de Linux o si no hay bus de sesión.
  Future<bool> start() async {
    if (!Platform.isLinux || _client != null) return _client != null;
    try {
      final client = DBusClient.session();
      final result = await client.requestName(busName);
      if (result == DBusRequestNameReply.exists) {
        await client.close();
        return false;
      }
      final object = _MprisObject(_player);
      await client.registerObject(object);
      _client = client;
      _listener = () => object.publish();
      _player.addListener(_listener!);
      object.publish();
      return true;
    } catch (e) {
      debugPrint('MprisService: no se pudo iniciar ($e)');
      return false;
    }
  }

  Future<void> stop() async {
    final listener = _listener;
    if (listener != null) _player.removeListener(listener);
    _listener = null;
    final client = _client;
    _client = null;
    try {
      await client?.close();
    } catch (_) {}
  }

  /// Para pruebas: el estado que se publicaría ahora.
  @visibleForTesting
  static Map<String, Object?> snapshot(
    Track? track, {
    required bool playing,
    required Duration position,
  }) =>
      _MprisObject.metadataFor(track, playing: playing, position: position);
}

class _MprisObject extends DBusObject {
  _MprisObject(this._player) : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final PlayerController _player;

  static const _root = 'org.mpris.MediaPlayer2';
  static const _playerIface = 'org.mpris.MediaPlayer2.Player';

  String? _lastTrackId;
  bool? _lastPlaying;

  static Map<String, Object?> metadataFor(
    Track? track, {
    required bool playing,
    required Duration position,
  }) =>
      {
        'PlaybackStatus':
            track == null ? 'Stopped' : (playing ? 'Playing' : 'Paused'),
        'Position': position.inMicroseconds,
        'xesam:title': track?.title,
        'xesam:artist': track == null ? null : [track.artist],
        'xesam:album': track?.album,
      };

  Map<String, DBusValue> _metadata() {
    final track = _player.currentTrack;
    if (track == null) return {};
    final seconds = double.tryParse(track.duration) ?? 0;
    return {
      'mpris:trackid':
          DBusObjectPath('/org/scrotify/track/${_safeId(track.id)}'),
      'mpris:length': DBusInt64((seconds * 1000000).round()),
      'xesam:title': DBusString(track.title),
      'xesam:artist': DBusArray.string([track.artist]),
      'xesam:album': DBusString(track.album),
    }.map((k, v) => MapEntry(k, DBusVariant(v)));
  }

  static String _safeId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

  String get _status {
    if (_player.currentTrack == null) return 'Stopped';
    return _player.playing ? 'Playing' : 'Paused';
  }

  /// Avisa de cambios de estado a los clientes MPRIS.
  void publish() {
    final id = _player.currentTrack?.id;
    final playing = _player.playing;
    if (id == _lastTrackId && playing == _lastPlaying) return;
    _lastTrackId = id;
    _lastPlaying = playing;
    try {
      emitPropertiesChanged(_playerIface, changedProperties: {
        'PlaybackStatus': DBusString(_status),
        'Metadata': DBusDict.stringVariant(_metadata()),
        'CanPlay': DBusBoolean(_player.currentTrack != null),
        'CanPause': DBusBoolean(_player.currentTrack != null),
      });
    } catch (_) {}
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(_root, methods: [
          DBusIntrospectMethod('Raise'),
          DBusIntrospectMethod('Quit'),
        ], properties: [
          DBusIntrospectProperty('CanQuit', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanRaise', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('HasTrackList', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Identity', DBusSignature('s'),
              access: DBusPropertyAccess.read),
        ]),
        DBusIntrospectInterface(_playerIface, methods: [
          DBusIntrospectMethod('Next'),
          DBusIntrospectMethod('Previous'),
          DBusIntrospectMethod('Pause'),
          DBusIntrospectMethod('PlayPause'),
          DBusIntrospectMethod('Stop'),
          DBusIntrospectMethod('Play'),
        ], properties: [
          DBusIntrospectProperty('PlaybackStatus', DBusSignature('s'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Metadata', DBusSignature('a{sv}'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('Position', DBusSignature('x'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanGoNext', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanGoPrevious', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanPlay', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanPause', DBusSignature('b'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('CanControl', DBusSignature('b'),
              access: DBusPropertyAccess.read),
        ]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == _playerIface) {
      switch (call.name) {
        case 'Play':
          if (!_player.playing) unawaited(_player.togglePlay());
        case 'Pause':
          if (_player.playing) unawaited(_player.togglePlay());
        case 'PlayPause':
          unawaited(_player.togglePlay());
        case 'Next':
          unawaited(_player.skipNext());
        case 'Previous':
          unawaited(_player.skipPrevious());
        case 'Stop':
          if (_player.playing) unawaited(_player.togglePlay());
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
      return DBusMethodSuccessResponse();
    }
    if (call.interface == _root &&
        (call.name == 'Raise' || call.name == 'Quit')) {
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = _properties(interface)[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(_properties(interface));
  }

  Map<String, DBusValue> _properties(String interface) {
    final hasTrack = _player.currentTrack != null;
    if (interface == _root) {
      return {
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(false),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('Scrotify'),
      };
    }
    if (interface == _playerIface) {
      return {
        'PlaybackStatus': DBusString(_status),
        'Metadata': DBusDict.stringVariant(_metadata()),
        'Position': DBusInt64(_player.position.inMicroseconds),
        'CanGoNext': DBusBoolean(hasTrack),
        'CanGoPrevious': DBusBoolean(hasTrack),
        'CanPlay': DBusBoolean(hasTrack),
        'CanPause': DBusBoolean(hasTrack),
        'CanControl': const DBusBoolean(true),
      };
    }
    return {};
  }
}
