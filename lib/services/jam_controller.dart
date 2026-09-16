import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/jam_models.dart';
import 'jam_guest_service.dart';
import 'jam_host_service.dart';
import 'navidrome_service.dart';
import 'player_controller.dart';

/// Controlador principal de sesiones Jam.
/// Actúa como puente entre los servicios de red ([JamHostService], [JamGuestService])
/// y el reproductor de audio ([PlayerController]).
class JamController extends ChangeNotifier {
  final PlayerController _player;
  final NavidromeService _navidrome;

  final JamHostService _hostService = JamHostService();
  final JamGuestService _guestService = JamGuestService();

  JamRole _role = JamRole.none;
  JamSessionState? _session;
  JamParticipant? _localParticipant;

  List<DiscoveredJamSession> _discoveredSessions = [];
  bool _isScanningRadar = false;

  // Cola de items con trazabilidad (solo en Host)
  final List<JamQueueItem> _hostJamQueue = [];
  JamParticipant? _currentTrackAddedBy;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _playerPositionSub;
  Timer? _hostSyncHeartbeat;

  JamController(this._player, this._navidrome) {
    _initHostCallbacks();
    _initGuestCallbacks();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  JamRole get role => _role;
  JamSessionState? get session => _session;
  JamParticipant? get localParticipant => _localParticipant;
  List<JamParticipant> get participants => _session?.participants ?? [];
  List<JamQueueItem> get jamQueue => _session?.queue ?? [];
  JamMode get mode => _session?.mode ?? JamMode.partySpeaker;
  bool get isHost => _role == JamRole.host;
  bool get isGuest => _role == JamRole.guest;
  bool get inJam => _role != JamRole.none;
  List<DiscoveredJamSession> get discoveredSessions => _discoveredSessions;
  bool get isScanningRadar => _isScanningRadar;
  String? get currentCodeFormatted =>
      _hostService.pinCode?.formatted ??
      (_session?.pinCode.isNotEmpty == true
          ? '${_session!.pinCode.substring(0, 3)}-${_session!.pinCode.substring(3)}'
          : null);
  String? get qrUri => _hostService.qrDataUri;
  String? get hostIp => _hostService.hostIp;
  int get port => _hostService.port;
  bool get allowGuestControls => _session?.allowGuestControls ?? true;
  JamParticipant? get currentTrackAddedBy => _currentTrackAddedBy;

  // ---------------------------------------------------------------------------
  // Inicialización de Callbacks del Host
  // ---------------------------------------------------------------------------
  void _initHostCallbacks() {
    _hostService.onJoinRequested = (participant, socket) async {
      _session = _session?.copyWith(
        participants: [..._session!.participants, participant],
      );
      // Enviar respuesta afirmativa con el estado inicial
      _hostService.sendToClient(participant.id, {
        'op': 'join_response',
        'accepted': true,
        'assignedParticipant': participant.toJson(),
        'state': _session?.toJson(),
      });
      _hostService.broadcastSessionState(_session!);
      notifyListeners();
      return true;
    };

    _hostService.onTrackAddRequested = (track, participant, playNext) {
      final queueItem = JamQueueItem(
        id: 'item_${DateTime.now().millisecondsSinceEpoch}_${_hostJamQueue.length}',
        track: track,
        addedBy: participant,
        addedAt: DateTime.now(),
      );

      if (playNext) {
        _hostJamQueue.insert(0, queueItem);
        _player.addNextInQueue(track);
      } else {
        _hostJamQueue.add(queueItem);
        _player.addToQueue(track);
      }

      _syncHostState();
      _hostService.broadcastSessionState(_session!);
      notifyListeners();
    };

    _hostService.onTrackRemoveRequested = (queueItemId, participant) {
      final idx = _hostJamQueue.indexWhere((it) => it.id == queueItemId);
      if (idx >= 0) {
        _hostJamQueue.removeAt(idx);
        _player.removeFromQueue(idx);
        _syncHostState();
        _hostService.broadcastSessionState(_session!);
        notifyListeners();
      }
    };

    _hostService.onQueueReorderRequested = (oldIndex, newIndex, participant) {
      if (oldIndex >= 0 &&
          oldIndex < _hostJamQueue.length &&
          newIndex >= 0 &&
          newIndex < _hostJamQueue.length) {
        final item = _hostJamQueue.removeAt(oldIndex);
        _hostJamQueue.insert(newIndex, item);
        _player.reorderQueue(oldIndex, newIndex);
        _syncHostState();
        _hostService.broadcastSessionState(_session!);
        notifyListeners();
      }
    };

    _hostService.onPlaybackControlRequested =
        (action, positionMs, participant) async {
      switch (action) {
        case 'toggle':
        case 'play':
        case 'pause':
          await _player.togglePlay();
          break;
        case 'skip_next':
          await _player.skipNext();
          break;
        case 'skip_previous':
          await _player.skipPrevious();
          break;
        case 'seek':
          if (positionMs != null) {
            await _player.seek(Duration(milliseconds: positionMs));
          }
          break;
      }
      _syncHostPlayback();
    };

    _hostService.onParticipantLeft = (participant) {
      if (_session != null) {
        final updated = _session!.participants
            .where((p) => p.id != participant.id)
            .toList();
        _session = _session!.copyWith(participants: updated);
        notifyListeners();
      }
    };
  }

  // ---------------------------------------------------------------------------
  // Inicialización de Callbacks del Guest
  // ---------------------------------------------------------------------------
  void _initGuestCallbacks() {
    _guestService.onStateSync = (state) {
      _session = state;
      _currentTrackAddedBy = state.currentTrackAddedBy;
      _syncGuestAudioIfApplicable(
        track: state.currentTrack,
        isPlaying: state.isPlaying,
        positionMs: state.positionMs,
        serverTs: state.updatedAtMs,
      );
      notifyListeners();
    };

    _guestService.onPlaybackUpdated =
        (track, addedBy, isPlaying, positionMs, serverTs) {
      if (_session != null) {
        _session = _session!.copyWith(
          currentTrack: track,
          currentTrackAddedBy: addedBy,
          isPlaying: isPlaying,
          positionMs: positionMs,
          updatedAtMs: serverTs,
        );
      }
      _currentTrackAddedBy = addedBy;
      _syncGuestAudioIfApplicable(
        track: track,
        isPlaying: isPlaying,
        positionMs: positionMs,
        serverTs: serverTs,
      );
      notifyListeners();
    };

    _guestService.onQueueUpdated = (queue) {
      if (_session != null) {
        _session = _session!.copyWith(queue: queue);
        notifyListeners();
      }
    };

    _guestService.onKicked = (reason) {
      leaveOrEndSession();
    };

    _guestService.onSessionClosed = (reason) {
      leaveOrEndSession();
    };
  }

  // ---------------------------------------------------------------------------
  // Acciones de Anfitrión (Host)
  // ---------------------------------------------------------------------------

  Future<void> startHostSession({
    JamMode mode = JamMode.partySpeaker,
    bool allowGuestControls = true,
    String? customName,
  }) async {
    await leaveOrEndSession();

    final pinCode = JamCode.generate();
    final sessionId = 'jam_${DateTime.now().millisecondsSinceEpoch}';
    final hostName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : _navidrome.username ?? _getDefaultDeviceName();

    _localParticipant = JamParticipant(
      id: 'host_local',
      name: hostName,
      avatarColorValue: 0xFFA855F7, // Neon Purple
      isHost: true,
      joinedAt: DateTime.now(),
      canControlPlayback: true,
      canManageQueue: true,
    );

    _hostJamQueue.clear();
    _currentTrackAddedBy = _localParticipant;

    await _hostService.start(
      sessionId: sessionId,
      pinCode: pinCode,
      hostName: hostName,
      mode: mode,
      allowGuestControls: allowGuestControls,
    );

    _role = JamRole.host;
    _syncHostState();

    // Publicar la sesión en el servidor Navidrome para oyentes remotos
    if (_session != null) {
      _navidrome.publishServerJam(_session!);
    }

    // Suscribirse a cambios en PlayerController
    _player.addListener(_onPlayerChangedAsHost);

    // Heartbeat periódico para sincronización precisa
    _hostSyncHeartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_role == JamRole.host && _hostService.isRunning) {
        _syncHostPlayback();
      }
    });

    notifyListeners();
  }

  void _onPlayerChangedAsHost() {
    if (_role != JamRole.host) return;

    final curTrack = _player.currentTrack;
    _hostService.updateTrackMetadata(
      title: curTrack?.title,
      artist: curTrack?.artist,
      albumArtUrl: curTrack?.albumArtUrl,
    );

    _syncHostState();
  }

  void _syncHostState() {
    final curTrack = _player.currentTrack;
    _session = JamSessionState(
      sessionId: _hostService.sessionId ?? '',
      pinCode: _hostService.pinCode?.value ?? '',
      hostName: _localParticipant?.name ?? 'Host',
      hostIp: _hostService.hostIp ?? '',
      port: _hostService.port,
      mode: _hostService.mode,
      currentTrack: curTrack,
      currentTrackAddedBy: _currentTrackAddedBy,
      isPlaying: _player.playing,
      positionMs: _player.position.inMilliseconds,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      queue: List.of(_hostJamQueue),
      participants: [_localParticipant!, ..._hostService.participants],
      allowGuestControls: _hostService.allowGuestControls,
    );
  }

  void _syncHostPlayback() {
    if (_role != JamRole.host) return;
    _hostService.broadcastPlaybackUpdate(
      track: _player.currentTrack,
      addedBy: _currentTrackAddedBy,
      isPlaying: _player.playing,
      positionMs: _player.position.inMilliseconds,
    );
  }

  // ---------------------------------------------------------------------------
  // Acciones de Invitado (Guest)
  // ---------------------------------------------------------------------------

  Future<bool> joinSession({
    required String host,
    required int port,
    required String pin,
    String? customName,
    int? customColor,
  }) async {
    await leaveOrEndSession();

    final name = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : _navidrome.username ?? _getDefaultDeviceName();
    final color = customColor ?? 0xFF10B981; // Neon Emerald

    final success = await _guestService.connect(
      host: host,
      port: port,
      pin: pin,
      name: name,
      avatarColorValue: color,
    );

    if (success) {
      _role = JamRole.guest;
      _localParticipant = _guestService.localParticipant ??
          JamParticipant(
            id: 'guest_local',
            name: name,
            avatarColorValue: color,
            isHost: false,
            joinedAt: DateTime.now(),
          );
      _session = _guestService.sessionState;
      notifyListeners();
      return true;
    } else {
      _role = JamRole.none;
      notifyListeners();
      return false;
    }
  }

  Future<void> scanRadar() async {
    _isScanningRadar = true;
    notifyListeners();

    try {
      // Escaneo dual: LAN (UDP Broadcast) + Servidor Navidrome (Comunidad Remota)
      final results = await Future.wait([
        _guestService.scanRadar(),
        _navidrome.getServerActiveJams(),
      ]);

      final lanResults = results[0];
      final serverResults = results[1];

      final Map<String, DiscoveredJamSession> map = {};

      for (final s in lanResults) {
        final key = '${s.host}:${s.port}:${s.pin}';
        map[key] = s;
      }

      for (final s in serverResults) {
        final key = '${s.host}:${s.port}:${s.pin}';
        if (!map.containsKey(key)) {
          map[key] = s;
        }
      }

      _discoveredSessions = map.values.toList();
    } catch (e) {
      debugPrint('JamController.scanRadar error: $e');
    } finally {
      _isScanningRadar = false;
      notifyListeners();
    }
  }

  Future<bool> joinDiscovered(
    DiscoveredJamSession disc, {
    String? customName,
    int? customColor,
  }) async {
    return joinSession(
      host: disc.host,
      port: disc.port,
      pin: disc.pin,
      customName: customName,
      customColor: customColor,
    );
  }

  Future<bool> joinByQr(
    String uri, {
    String? customName,
    int? customColor,
  }) async {
    final data = JamQrData.fromUri(uri);
    if (data == null) return false;
    return joinSession(
      host: data.host,
      port: data.port,
      pin: data.code,
      customName: customName,
      customColor: customColor,
    );
  }

  Future<bool> joinByPin(
    String pin, {
    String? customName,
    int? customColor,
  }) async {
    _isScanningRadar = true;
    notifyListeners();

    try {
      // 1. Intentar descubrir vía radar LAN
      var session = await _guestService.findByPin(pin);

      // 2. Si no se encontró en LAN, buscar en el servidor Navidrome
      if (session == null) {
        final serverJams = await _navidrome.getServerActiveJams();
        final clean = pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        final matches = serverJams.where((s) => s.pin.toUpperCase() == clean);
        if (matches.isNotEmpty) {
          session = matches.first;
        }
      }

      if (session != null) {
        return await joinDiscovered(session,
            customName: customName, customColor: customColor);
      }
      return false;
    } finally {
      _isScanningRadar = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización de Audio para Invitados (Escucha Sincronizada)
  // ---------------------------------------------------------------------------

  void _syncGuestAudioIfApplicable({
    Track? track,
    required bool isPlaying,
    required int positionMs,
    required int serverTs,
  }) async {
    if (_role != JamRole.guest || _session == null) return;

    // Solo reproducir si estamos en modo Escucha Sincronizada
    if (_session!.mode == JamMode.synchronizedListening) {
      if (track == null) {
        _player.clearQueue();
        return;
      }

      // Si la canción actual es diferente, cargar y reproducir
      if (_player.currentTrack?.id != track.id) {
        await _player.playQueue([track], startIndex: 0);
      }

      // Compensación de latencia de red
      final now = DateTime.now().millisecondsSinceEpoch;
      final transitDelayMs = (now - serverTs).clamp(0, 5000);
      final targetPositionMs =
          positionMs + (isPlaying ? transitDelayMs : 0);

      final currentPosMs = _player.position.inMilliseconds;
      final drift = (targetPositionMs - currentPosMs).abs();

      if (drift > 450) {
        await _player.seek(Duration(milliseconds: targetPositionMs));
      }

      if (isPlaying && !_player.playing) {
        await _player.togglePlay();
      } else if (!isPlaying && _player.playing) {
        await _player.togglePlay();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Acciones Compartidas (Cola y Reproducción)
  // ---------------------------------------------------------------------------

  void addTrackToJam(Track track, {bool playNext = false}) {
    if (!inJam) return;

    if (isHost) {
      final queueItem = JamQueueItem(
        id: 'item_${DateTime.now().millisecondsSinceEpoch}_${_hostJamQueue.length}',
        track: track,
        addedBy: _localParticipant,
        addedAt: DateTime.now(),
      );

      if (playNext) {
        _hostJamQueue.insert(0, queueItem);
        _player.addNextInQueue(track);
      } else {
        _hostJamQueue.add(queueItem);
        _player.addToQueue(track);
      }

      _syncHostState();
      _hostService.broadcastSessionState(_session!);
      notifyListeners();
    } else if (isGuest) {
      _guestService.addToQueue(track, playNext: playNext);
    }
  }

  void removeTrackFromJam(String queueItemId, {int? orderIndex}) {
    if (!inJam) return;

    if (isHost) {
      final idx = _hostJamQueue.indexWhere((it) => it.id == queueItemId);
      if (idx >= 0) {
        _hostJamQueue.removeAt(idx);
        _player.removeFromQueue(orderIndex ?? idx);
        _syncHostState();
        _hostService.broadcastSessionState(_session!);
        notifyListeners();
      }
    } else if (isGuest) {
      _guestService.removeFromQueue(queueItemId);
    }
  }

  void reorderJamQueue(int oldIndex, int newIndex) {
    if (!inJam) return;

    if (isHost) {
      if (oldIndex >= 0 &&
          oldIndex < _hostJamQueue.length &&
          newIndex >= 0 &&
          newIndex < _hostJamQueue.length) {
        final item = _hostJamQueue.removeAt(oldIndex);
        _hostJamQueue.insert(newIndex, item);
        _player.reorderQueue(oldIndex, newIndex);
        _syncHostState();
        _hostService.broadcastSessionState(_session!);
        notifyListeners();
      }
    } else if (isGuest) {
      _guestService.reorderQueue(oldIndex, newIndex);
    }
  }

  void playbackAction(String action, {Duration? position}) async {
    if (!inJam) return;

    if (isHost) {
      switch (action) {
        case 'toggle':
        case 'play':
        case 'pause':
          await _player.togglePlay();
          break;
        case 'skip_next':
          await _player.skipNext();
          break;
        case 'skip_previous':
          await _player.skipPrevious();
          break;
        case 'seek':
          if (position != null) await _player.seek(position);
          break;
      }
      _syncHostPlayback();
    } else if (isGuest) {
      _guestService.sendPlaybackControl(
        action,
        positionMs: position?.inMilliseconds,
      );
    }
  }

  void updateJamSettings({JamMode? mode, bool? allowGuestControls}) {
    if (!isHost) return;

    _hostService.updateSettings(
      mode: mode,
      allowGuestControls: allowGuestControls,
    );

    if (_session != null) {
      _session = _session!.copyWith(
        mode: mode ?? _session!.mode,
        allowGuestControls: allowGuestControls ?? _session!.allowGuestControls,
      );
      _hostService.broadcastSessionState(_session!);
      notifyListeners();
    }
  }

  void kickParticipant(String participantId) {
    if (!isHost) return;
    _hostService.kickParticipant(participantId);
    if (_session != null) {
      final updated =
          _session!.participants.where((p) => p.id != participantId).toList();
      _session = _session!.copyWith(participants: updated);
      notifyListeners();
    }
  }

  Future<void> leaveOrEndSession() async {
    _hostSyncHeartbeat?.cancel();
    _hostSyncHeartbeat = null;

    _player.removeListener(_onPlayerChangedAsHost);

    if (_role == JamRole.host) {
      await _hostService.stop();
    } else if (_role == JamRole.guest) {
      await _guestService.disconnect();
    }

    _role = JamRole.none;
    _session = null;
    _localParticipant = null;
    _hostJamQueue.clear();
    _currentTrackAddedBy = null;
    notifyListeners();
  }

  String _getDefaultDeviceName() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'Dispositivo';
  }

  @override
  void dispose() {
    _hostSyncHeartbeat?.cancel();
    _player.removeListener(_onPlayerChangedAsHost);
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _hostService.stop();
    _guestService.disconnect();
    super.dispose();
  }
}
