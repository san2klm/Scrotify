part of 'jam_controller.dart';

/// Reacciones, chat y capacidades del servidor central.
mixin _JamSocial on _JamBase {
  List<JamReaction> get activeReactions => _reactions.active();

  List<JamChatMessage> get chatMessages => _chat.items;

  /// Reacciones/chat disponibles: en LAN siempre; en nube según el relay.
  bool get reactionsAvailable => inJam && (_onLan || _cloudCaps.reactions);

  bool get chatAvailable =>
      inJam && _chatEnabledForRoom && (_onLan || _cloudCaps.chat);

  bool get chatSupported => inJam && (_onLan || _cloudCaps.chat);

  bool get chatRoomEnabled => _chatEnabledForRoom;

  bool get _onLan => isHost ? _hostService.isRunning : _guestService.isConnected;

  @override
  void _receiveReaction(String from, String emoji) {
    if (!kJamReactions.contains(emoji)) return;
    _reactions.add(JamReaction(from, emoji, DateTime.now()));
    _reactionSweep?.cancel();
    _reactionSweep = Timer(kJamReactionLife + const Duration(milliseconds: 100), notifyListeners);
    notifyListeners();
  }

  @override
  void _receiveChat(String from, String text, {bool mine = false}) {
    final clean = sanitizeChatText(text);
    if (clean == null) return;
    _chat.add(JamChatMessage(from, clean, DateTime.now(), mine: mine));
    notifyListeners();
  }

  void sendReaction(String emoji) {
    if (!reactionsAvailable || !kJamReactions.contains(emoji)) return;
    final me = _localParticipant?.name ?? '';
    _receiveReaction(me, emoji);
    if (isHost) {
      _hostService.broadcastMessage({'op': 'reaction', 'from': me, 'emoji': emoji});
      if (_remoteService.isConnected) _remoteService.sendReaction(emoji);
    } else if (_guestService.isConnected) {
      _guestService.sendReaction(emoji);
    } else if (_remoteService.isConnected) {
      _remoteService.sendReaction(emoji);
    }
  }

  void sendChat(String raw) {
    final text = sanitizeChatText(raw);
    if (text == null || !chatAvailable) return;
    final me = _localParticipant?.name ?? '';
    _receiveChat(me, text, mine: true);
    if (isHost) {
      _hostService.broadcastMessage({
        'op': 'chat',
        'from': me,
        'text': text,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      if (_remoteService.isConnected) _remoteService.sendChat(text);
    } else if (_guestService.isConnected) {
      _guestService.sendChat(text);
    } else if (_remoteService.isConnected) {
      _remoteService.sendChat(text);
    }
  }

  /// El anfitrión activa/desactiva el chat de su sala.
  void setChatEnabled(bool enabled) {
    if (!isHost) return;
    _chatEnabledForRoom = enabled;
    _hostService.chatEnabled = enabled;
    if (_remoteService.isConnected) _remoteService.setChatEnabled(enabled);
    notifyListeners();
  }

  /// Lo que el relay configurado declara que ofrece. Hasta que responde (o si
  /// es un relay antiguo) vale [JamCapabilities.legacy].
  JamCapabilities get cloudCapabilities => _cloudCaps;

  /// Consulta de nuevo las funciones del relay (p. ej. al abrir el diálogo).
  Future<void> refreshCloudCapabilities() => _loadCloudCapabilities();

  @override
  Future<void> _loadCloudCapabilities() async {
    final endpoint = _remoteService.endpoint;
    final caps = await RemoteJamService.fetchCapabilities(endpoint);
    if (caps == null) {
      // Relay antiguo o sin red: se conserva lo ya sabido de ese mismo relay,
      // pero lo de otro relay no vale.
      if (_cloudCapsEndpoint == endpoint) return;
      _cloudCaps = JamCapabilities.legacy;
    } else {
      _cloudCaps = caps;
    }
    _cloudCapsEndpoint = endpoint;
    notifyListeners();
  }
}
