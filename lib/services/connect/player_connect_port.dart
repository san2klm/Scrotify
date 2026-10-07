import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../navidrome_service.dart';
import '../player_controller.dart';
import '../secure_storage.dart';
import 'connect_protocol.dart';
import 'connect_service.dart';

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

/// Conecta `ConnectService` con el reproductor real.
class PlayerConnectPort extends ChangeNotifier implements ConnectPlayerPort {
  PlayerConnectPort(this.player, this.service) {
    player.addListener(notifyListeners);
  }

  /// Máximo de canciones que viajan al transferir (el mensaje cifrado tiene
  /// un tope de 64 KB en el servidor).
  static const maxTransferTracks = 40;

  final PlayerController player;
  final NavidromeService service;

  @override
  void dispose() {
    player.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  String? get scope => service.serverScope;

  static Map<String, dynamic> _json(Track t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'duration': t.duration,
        'albumArtUrl': t.albumArtUrl,
        'suffix': t.suffix,
        'artistId': t.artistId,
        'albumId': t.albumId,
        'genre': t.genre,
        'trackNumber': t.trackNumber,
        'samplingRate': t.samplingRate,
        'bitDepth': t.bitDepth,
      };

  @override
  Map<String, dynamic>? snapshot() {
    final track = player.currentTrack;
    if (track == null) return null;
    final seconds = int.tryParse(track.duration) ?? 0;
    return {
      'scope': scope,
      'track': _json(track),
      'playing': player.playing,
      'positionMs': player.position.inMilliseconds,
      'durationMs': player.duration?.inMilliseconds ?? seconds * 1000,
      'volume': player.volume,
    };
  }

  @override
  ConnectTransfer? exportTransfer() {
    final scope = this.scope;
    final track = player.currentTrack;
    if (scope == null || track == null) return null;
    final upcoming = player.orderedQueue
        .skip(max(0, player.currentOrderPos))
        .take(maxTransferTracks)
        .toList();
    return ConnectTransfer(
      scope: scope,
      tracks: [for (final t in upcoming) _json(t)],
      index: 0,
      positionMs: player.position.inMilliseconds,
      playing: player.playing,
    );
  }

  @override
  Future<void> adopt(ConnectTransfer transfer) async {
    final tracks = [
      for (final m in transfer.tracks)
        Track.fromJson(m, albumArtUrl: m['albumArtUrl'] as String?),
    ];
    await player.playQueue(tracks, startIndex: transfer.index);
    if (transfer.positionMs > 0) {
      await player.seek(Duration(milliseconds: transfer.positionMs));
    }
    if (!transfer.playing) await player.pause();
  }

  @override
  Future<void> apply(String command, num? value) async {
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
          await player
              .seek(Duration(milliseconds: value.toInt().clamp(0, 1 << 31)));
        }
      case ConnectCommand.volume:
        if (value != null) await player.setVolume(value.toDouble());
    }
  }

  @override
  Future<void> pauseLocal() => player.pause();
}
