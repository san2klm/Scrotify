import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../navidrome_service.dart';
import '../remote_playback.dart';
import 'connect_protocol.dart';
import 'connect_service.dart';
import 'track_codec.dart';

/// Hace que `PlayerController` refleje y maneje el dispositivo que
/// `ConnectService` está controlando.
class ConnectMirror extends ChangeNotifier implements RemotePlayback {
  ConnectMirror(this.connect, {required this.scope}) {
    connect.addListener(notifyListeners);
  }

  final ConnectService connect;
  final String? Function() scope;

  List<Map<String, dynamic>>? _cachedFor;
  List<Track> _cached = const [];

  @override
  void dispose() {
    connect.removeListener(notifyListeners);
    super.dispose();
  }

  ConnectRemoteState? get _state => connect.controlledState;

  @override
  bool get active => connect.controlled != null;

  @override
  List<Track> get queue {
    final raw = _state?.queue ?? const [];
    if (!identical(raw, _cachedFor)) {
      _cachedFor = raw;
      _cached = [for (final m in raw) trackFromConnectJson(m)];
    }
    return _cached;
  }

  @override
  int get index => _state?.index ?? -1;

  @override
  bool get playing => _state?.playing ?? false;

  @override
  Duration get position =>
      _state?.estimatedPosition(DateTime.now()) ?? Duration.zero;

  @override
  Duration? get duration {
    final ms = _state?.durationMs ?? 0;
    return ms > 0 ? Duration(milliseconds: ms) : null;
  }

  @override
  double get volume => _state?.volume ?? 1;

  @override
  bool get shuffle => _state?.shuffle ?? false;

  @override
  LoopMode get repeat => switch (_state?.repeat) {
        'all' => LoopMode.all,
        'one' => LoopMode.one,
        _ => LoopMode.off,
      };

  int get _offset => _state?.queueOffset ?? 0;

  @override
  void playQueue(List<Track> tracks, int startIndex, {bool shuffle = false}) {
    final scope = this.scope();
    if (scope == null || tracks.isEmpty) return;
    final start = startIndex.clamp(0, tracks.length - 1);
    final split = ConnectQueueChunks.split(
        [for (final t in tracks.skip(start)) trackToConnectJson(t)]);
    unawaited(connect.commandSequence([
      (
        command: ConnectCommand.playQueue,
        data: {
          'scope': scope,
          'tracks': split.head,
          'index': 0,
          'shuffle': shuffle,
          if (split.xfer != null) 'xfer': split.xfer,
          if (split.xfer != null) 'more': split.more,
        }
      ),
      for (var seq = 0; seq < split.rest.length; seq++)
        (
          command: ConnectCommand.queueAppend,
          data: split.appendData(scope, seq)
        ),
    ]));
  }

  void _withTrack(String command, Track track) {
    final scope = this.scope();
    if (scope == null) return;
    connect.command(
        command, null, {'scope': scope, 'track': trackToConnectJson(track)});
  }

  @override
  void addToQueue(Track track) => _withTrack(ConnectCommand.queueAdd, track);

  @override
  void addNext(Track track) => _withTrack(ConnectCommand.queueNext, track);

  @override
  void removeFromQueue(int orderIndex) =>
      connect.command(ConnectCommand.queueRemove, orderIndex + _offset);

  @override
  void reorderQueue(int oldIndex, int newIndex) => connect.command(
      ConnectCommand.queueMove,
      null,
      {'from': oldIndex + _offset, 'to': newIndex + _offset});

  @override
  void clearQueue() => connect.command(ConnectCommand.queueClear);

  @override
  void toggle() => connect.command(ConnectCommand.toggle);

  @override
  void play() => connect.command(ConnectCommand.play);

  @override
  void pause() => connect.command(ConnectCommand.pause);

  @override
  void next() => connect.command(ConnectCommand.next);

  @override
  void previous() => connect.command(ConnectCommand.previous);

  @override
  void seek(Duration target) =>
      connect.command(ConnectCommand.seek, target.inMilliseconds);

  @override
  void setVolume(double volume) =>
      connect.command(ConnectCommand.volume, volume);

  @override
  void toggleShuffle() => connect.command(ConnectCommand.shuffle);

  @override
  void toggleRepeat() => connect.command(ConnectCommand.repeat);
}
