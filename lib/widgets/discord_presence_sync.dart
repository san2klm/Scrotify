import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/discord_presence.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/settings_controller.dart';

/// Mantiene Discord Rich Presence alineado con la pista que suena, si el
/// usuario lo activó y puso su Application ID. Solo escritorio.
class DiscordPresenceSync extends StatefulWidget {
  const DiscordPresenceSync({super.key, required this.child});

  final Widget child;

  @override
  State<DiscordPresenceSync> createState() => _DiscordPresenceSyncState();
}

class _DiscordPresenceSyncState extends State<DiscordPresenceSync> {
  DiscordRichPresence? _presence;
  String _clientId = '';
  String? _lastKey;
  bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    unawaited(_presence?.stop());
    super.dispose();
  }

  void _sync({
    required bool enabled,
    required String clientId,
    required Track? track,
    required bool playing,
    required Duration position,
  }) {
    if (!enabled || clientId.isEmpty) {
      if (_presence != null) {
        unawaited(_presence!.stop());
        _presence = null;
        _lastKey = null;
      }
      return;
    }
    if (_presence == null || _clientId != clientId) {
      unawaited(_presence?.stop());
      _presence = DiscordRichPresence(clientId: clientId);
      _clientId = clientId;
      _lastKey = null;
    }
    final key = '${track?.id}|$playing';
    if (key == _lastKey) return;
    _lastKey = key;
    unawaited(_presence!.update(track, playing: playing, position: position));
  }

  @override
  Widget build(BuildContext context) {
    if (_desktop) {
      final settings = context.watch<SettingsController>();
      final enabled = settings.discordPresence;
      final clientId = settings.discordClientId.trim();
      final player = context.read<PlayerController>();
      final track =
          context.select<PlayerController, Track?>((p) => p.currentTrack);
      final playing = context.select<PlayerController, bool>((p) => p.playing);
      final position = enabled ? player.position : Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync(
            enabled: enabled,
            clientId: clientId,
            track: track,
            playing: playing,
            position: position,
          ));
    }
    return widget.child;
  }
}
