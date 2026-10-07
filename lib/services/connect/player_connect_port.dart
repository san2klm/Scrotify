import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../navidrome_service.dart';
import '../player_controller.dart';
import '../secure_storage.dart';
import 'connect_protocol.dart';
import 'connect_service.dart';
import 'track_codec.dart';

/// Identidad de este dispositivo en Connect: id estable y nombre visible.
class ConnectIdentity {
  const ConnectIdentity(this.id, this.name, this.kind);
  final String id;
  final String name;
  final ConnectKind kind;

  static const _storageKey = 'scrotify.connect_device_id';

  static Future<ConnectIdentity> load() async {
    var id = await SecureStorage.secureRead(_storageKey);
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id)) {
      final rng = Random.secure();
      id = List.generate(
          16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await SecureStorage.secureWrite(_storageKey, id);
    }
    final mobile = Platform.isAndroid || Platform.isIOS;
    final name =
        mobile ? (Platform.isIOS ? 'iPhone' : 'Teléfono Android') : _hostName();
    return ConnectIdentity(
        id, name, mobile ? ConnectKind.phone : ConnectKind.desktop);
  }

  static String _hostName() {
    final host = Platform.localHostname.trim();
    return host.isEmpty ? 'Esta computadora' : host;
  }
}

/// Conecta `ConnectService` con el reproductor real. Todo lo que toca el
/// reproductor local va por `runLocally`/`readLocally` para que siga siendo
/// el local aunque esta app esté controlando otro dispositivo.
class PlayerConnectPort extends ChangeNotifier implements ConnectPlayerPort {
  PlayerConnectPort(this.player, this.service) {
    player.addListener(notifyListeners);
  }

  /// Máximo de canciones que viajan en un mensaje (el mensaje cifrado tiene
  /// un tope de 64 KB en el servidor).
  static const maxTransferTracks = 40;

  /// Canciones anteriores a la actual que se publican en la ventana de cola.
  static const queueBehind = 5;

  final PlayerController player;
  final NavidromeService service;

  @override
  void dispose() {
    player.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  String? get scope => service.serverScope;

  @override
  Map<String, dynamic>? snapshot() => player.readLocally(() {
        final track = player.currentTrack;
        if (track == null) return null;
        final seconds = int.tryParse(track.duration) ?? 0;
        final ordered = player.orderedQueue;
        final pos = player.currentOrderPos;
        final start = max(0, pos - queueBehind);
        final end = min(ordered.length, start + maxTransferTracks);
        final window = ordered.sublist(start, end);
        return {
          'scope': scope,
          'track': trackToConnectJson(track),
          'playing': player.playing,
          'positionMs': player.position.inMilliseconds,
          'durationMs': player.duration?.inMilliseconds ?? seconds * 1000,
          'volume': player.volume,
          'queue': [for (final t in window) trackToConnectJson(t)],
          'queueSig': '$start|${Object.hashAll(window.map((t) => t.id))}',
          'offset': start,
          'index': pos - start,
          'shuffle': player.shuffleEnabled,
          'repeat': player.repeatMode.name,
        };
      });

  @override
  ConnectTransfer? exportTransfer() => player.readLocally(() {
        final scope = this.scope;
        final track = player.currentTrack;
        if (scope == null || track == null) return null;
        final upcoming = player.orderedQueue
            .skip(max(0, player.currentOrderPos))
            .take(maxTransferTracks)
            .toList();
        return ConnectTransfer(
          scope: scope,
          tracks: [for (final t in upcoming) trackToConnectJson(t)],
          index: 0,
          positionMs: player.position.inMilliseconds,
          playing: player.playing,
        );
      });

  @override
  Future<void> adopt(ConnectTransfer transfer) => player.runLocally(() async {
        final tracks = [
          for (final m in transfer.tracks) trackFromConnectJson(m),
        ];
        await player.playQueue(tracks, startIndex: transfer.index);
        if (transfer.positionMs > 0) {
          await player.seek(Duration(milliseconds: transfer.positionMs));
        }
        if (!transfer.playing) await player.pause();
      });

  Track? _track(Map<String, dynamic> data) {
    final raw = data['track'];
    if (data['scope'] != scope || raw is! Map || raw['id'] is! String) {
      return null;
    }
    return trackFromConnectJson(Map<String, dynamic>.from(raw));
  }

  @override
  Future<void> apply(String command, num? value, Map<String, dynamic> data) =>
      player.runLocally(() async {
        switch (command) {
          case ConnectCommand.toggle:
            await player.togglePlay();
          case ConnectCommand.play:
            await player.play();
          case ConnectCommand.pause:
            await player.pause();
          case ConnectCommand.next:
            await player.skipNext();
          case ConnectCommand.previous:
            await player.skipPrevious();
          case ConnectCommand.seek:
            if (value != null) {
              await player.seek(
                  Duration(milliseconds: value.toInt().clamp(0, 1 << 31)));
            }
          case ConnectCommand.volume:
            if (value != null) await player.setVolume(value.toDouble());
          case ConnectCommand.shuffle:
            await player.toggleShuffle();
          case ConnectCommand.repeat:
            await player.toggleRepeat();
          case ConnectCommand.playQueue:
            final transfer = ConnectTransfer.tryParse(data);
            if (transfer == null || transfer.scope != scope) return;
            final tracks = [
              for (final m in transfer.tracks) trackFromConnectJson(m),
            ];
            if (data['shuffle'] == true) {
              await player.playShuffledQueue(tracks);
            } else {
              await player.playQueue(tracks, startIndex: transfer.index);
            }
          case ConnectCommand.queueAdd:
            final track = _track(data);
            if (track != null) await player.addToQueue(track);
          case ConnectCommand.queueNext:
            final track = _track(data);
            if (track != null) await player.addNextInQueue(track);
          case ConnectCommand.queueRemove:
            if (value != null) player.removeFromQueue(value.toInt());
          case ConnectCommand.queueMove:
            final from = data['from'];
            final to = data['to'];
            if (from is int && to is int) player.reorderQueue(from, to);
          case ConnectCommand.queueClear:
            player.clearQueue();
        }
      });

  @override
  Future<void> pauseLocal() => player.runLocally(player.pause);
}
