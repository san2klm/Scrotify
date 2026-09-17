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

  /// Motivo legible del último [joinSession] fallido, para mostrar en UI.
  String? lastJoinError;

  // Cola de items con trazabilidad (solo en Host)
  final List<JamQueueItem> _hostJamQueue = [];
  final Map<Track, JamParticipant?> _trackAddedBy = {};
  JamParticipant? _currentTrackAddedBy;

  Timer? _hostSyncHeartbeat;
  Timer? _hostPublishTimer;

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
  String? get allHostIpsFormatted => _hostService.allLocalIps.isEmpty
      ? null
      : _hostService.allLocalIps.join(', ');
  String? get currentCodeFormatted =>
      _hostService.pinCode?.formatted ??
      (_session?.pinCode.isNotEmpty == true
          ? '${_session!.pinCode.substring(0, 3)}-${_session!.pinCode.substring(3)}'
          : null);
  String? get qrUri => _hostService.qrDataUri;
  String? get hostIp => _hostService.hostIp;
  int get port => _hostService.port;
  bool get allowGuestControls => _session?.allowGuestControls ?? true;
  bool get allowGuestQueueManage => _session?.allowGuestQueueManage ?? true;
  bool get isPublic => _session?.isPublic ?? true;
  int get maxParticipants => _session?.maxParticipants ?? 0;
  JamParticipant? get currentTrackAddedBy => _currentTrackAddedBy;

  // ---------------------------------------------------------------------------
  // Inicialización de Callbacks del Host
  // ---------------------------------------------------------------------------
  void _initHostCallbacks() {
    _hostService.onJoinRequested = (participant, socket) async {
      if (!isHost || _session == null) return false;
      _syncHostState();
      // Enviar respuesta afirmativa con el estado inicial
      _hostService.sendToClient(participant.id, {
        'op': 'join_response',
        'accepted': true,
        'assignedParticipant': participant.toJson(),
        'state': _session!.toJson(),
      });
      _hostService.broadcastSessionState(_session!);
      notifyListeners();
      return true;
    };

    _hostService.onTrackAddRequested = (track, participant, playNext) {
      unawaited(_addTrackAsHost(track, participant, playNext: playNext));
    };

    _hostService.onTrackRemoveRequested = (queueItemId, participant) {
      _removeTrackAsHost(queueItemId);
    };

    _hostService.onQueueReorderRequested = (oldIndex, newIndex, participant) {
      _reorderQueueAsHost(oldIndex, newIndex);
    };

    _hostService.onPlaybackControlRequested =
        (action, positionMs, participant) async {
      await _applyPlaybackAction(
        action,
        position: positionMs == null
            ? null
            : Duration(milliseconds: positionMs.clamp(0, 24 * 60 * 60 * 1000)),
      );
    };

    _hostService.onParticipantLeft = (participant) {
      if (!isHost) return;
      _syncHostState();
      if (_session != null) _hostService.broadcastSessionState(_session!);
      notifyListeners();
    };
  }

  Future<void> _addTrackAsHost(
    Track track,
    JamParticipant? addedBy, {
    required bool playNext,
  }) async {
    if (!isHost) return;

    final queueItem = JamQueueItem(
      id: 'item_${DateTime.now().microsecondsSinceEpoch}_${_hostJamQueue.length}',
      track: track,
      addedBy: addedBy,
      addedAt: DateTime.now(),
    );
    _trackAddedBy[track] = addedBy;
    if (playNext) {
      _hostJamQueue.insert(0, queueItem);
      await _player.addNextInQueue(track);
    } else {
      _hostJamQueue.add(queueItem);
      await _player.addToQueue(track);
    }

    _rebuildHostQueueFromPlayer();
    _publishHostState(includePlayback: true);
  }

  void _removeTrackAsHost(String queueItemId) {
    if (!isHost) return;
    final queueIndex =
        _hostJamQueue.indexWhere((item) => item.id == queueItemId);
    if (queueIndex < 0) return;

    final item = _hostJamQueue[queueIndex];
    final playerIndex = _playerOrderIndexForQueueItem(queueIndex, item);
    if (playerIndex < 0) return;

    _hostJamQueue.removeAt(queueIndex);
    _trackAddedBy.remove(item.track);
    _player.removeFromQueue(playerIndex);
    _rebuildHostQueueFromPlayer();
    _publishHostState();
  }

  void _reorderQueueAsHost(int oldIndex, int newIndex) {
    if (!isHost ||
        oldIndex < 0 ||
        oldIndex >= _hostJamQueue.length ||
        newIndex < 0 ||
        newIndex >= _hostJamQueue.length ||
        oldIndex == newIndex) {
      return;
    }

    final playerOffset = _player.currentOrderPos + 1;
    if (playerOffset <= 0) return;
    _player.reorderQueue(playerOffset + oldIndex, playerOffset + newIndex);
    _rebuildHostQueueFromPlayer();
    _publishHostState();
  }

  int _playerOrderIndexForQueueItem(int queueIndex, JamQueueItem item) {
    final expected = _player.currentOrderPos + 1 + queueIndex;
    final ordered = _player.orderedQueue;
    if (expected >= 0 &&
        expected < ordered.length &&
        identical(ordered[expected], item.track)) {
      return expected;
    }
    return ordered.indexWhere((track) => identical(track, item.track));
  }

  /// Reconcilia la cola compartida con la cola efectiva del reproductor. El
  /// reproductor conserva la pista actual; la Jam sólo publica las siguientes.
  void _rebuildHostQueueFromPlayer() {
    if (!isHost || _localParticipant == null) return;

    final ordered = _player.orderedQueue;
    final currentOrderPos = _player.currentOrderPos;
    final current = _player.currentTrack;
    if (current != null) {
      _currentTrackAddedBy = _trackAddedBy[current] ?? _localParticipant;
    }

    final futureTracks =
        currentOrderPos >= 0 && currentOrderPos < ordered.length
            ? ordered.skip(currentOrderPos + 1)
            : ordered;
    final remaining = List<JamQueueItem>.of(_hostJamQueue);
    final rebuilt = <JamQueueItem>[];

    for (final track in futureTracks) {
      final exactIndex =
          remaining.indexWhere((item) => identical(item.track, track));
      final matchingIndex = exactIndex >= 0
          ? exactIndex
          : remaining.indexWhere((item) => item.track.id == track.id);
      if (matchingIndex >= 0) {
        rebuilt.add(remaining.removeAt(matchingIndex));
        continue;
      }

      final addedBy = _trackAddedBy[track] ?? _localParticipant;
      _trackAddedBy[track] = addedBy;
      rebuilt.add(JamQueueItem(
        id: 'item_${DateTime.now().microsecondsSinceEpoch}_${rebuilt.length}',
        track: track,
        addedBy: addedBy,
        addedAt: DateTime.now(),
      ));
    }

    _hostJamQueue
      ..clear()
      ..addAll(rebuilt);
  }

  void _publishHostState({bool includePlayback = false}) {
    if (!isHost) return;
    _syncHostState();
    if (_session == null) return;
    _hostService.broadcastQueueUpdate(_hostJamQueue);
    _hostService.broadcastSessionState(_session!);
    if (includePlayback) _syncHostPlayback();
    _publishToNavidromeIfPublic();
    notifyListeners();
  }

  Future<void> _applyPlaybackAction(
    String action, {
    Duration? position,
  }) async {
    if (!isHost) return;

    switch (action) {
      case 'toggle':
        await _player.togglePlay();
        break;
      case 'play':
        if (!_player.playing) await _player.togglePlay();
        break;
      case 'pause':
        if (_player.playing) await _player.togglePlay();
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
    _rebuildHostQueueFromPlayer();
    _publishHostState(includePlayback: true);
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
    bool allowGuestQueueManage = true,
    bool isPublic = true,
    int maxParticipants = 0,
    String? initialPlaylistId,
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
    _trackAddedBy.clear();
    _currentTrackAddedBy = _localParticipant;

    await _hostService.start(
      sessionId: sessionId,
      pinCode: pinCode,
      hostName: hostName,
      mode: mode,
      allowGuestControls: allowGuestControls,
      allowGuestQueueManage: allowGuestQueueManage,
      isPublic: isPublic,
      maxParticipants: maxParticipants,
      initialPlaylistId: initialPlaylistId,
    );

    _role = JamRole.host;
    _rebuildHostQueueFromPlayer();
    _onPlayerChangedAsHost();
    _syncHostState();

    _publishToNavidromeIfPublic();

    // Suscribirse a cambios en PlayerController
    _player.addListener(_onPlayerChangedAsHost);

    // Heartbeat periódico para sincronización precisa
    _hostSyncHeartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_role == JamRole.host && _hostService.isRunning) {
        _syncHostPlayback();
      }
    });

    // El anuncio remoto expira, por lo que se renueva mientras el host exista.
    _hostPublishTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _publishToNavidromeIfPublic();
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

    _rebuildHostQueueFromPlayer();
    _syncHostState();
    if (_session != null) _hostService.broadcastSessionState(_session!);
    _syncHostPlayback();
    _publishToNavidromeIfPublic();
    notifyListeners();
  }

  void _syncHostState() {
    final curTrack = _player.currentTrack;
    final allIps = _hostService.allLocalIps;
    final hostIp = _hostService.hostIp ?? '';
    final fallbackIp =
        allIps.length > 1 ? allIps.firstWhere((ip) => ip != hostIp) : null;
    _session = JamSessionState(
      sessionId: _hostService.sessionId ?? '',
      pinCode: _hostService.pinCode?.value ?? '',
      hostName: _localParticipant?.name ?? 'Host',
      hostIp: hostIp,
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
      allowGuestQueueManage: _hostService.allowGuestQueueManage,
      remoteHost: fallbackIp,
      remotePort: fallbackIp != null ? _hostService.port : null,
      isPublic: _hostService.isPublic,
      maxParticipants: _hostService.maxParticipants,
      initialPlaylistId: _hostService.initialPlaylistId,
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

  void _publishToNavidromeIfPublic() {
    if (!isHost || _session == null || !_session!.isPublic) return;
    unawaited(_navidrome.publishServerJam(_session!));
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
    String? fallbackHost,
    int? fallbackPort,
  }) async {
    await leaveOrEndSession();
    lastJoinError = null;

    String normalizedPin;
    try {
      normalizedPin = JamCode(pin).value;
    } on ArgumentError {
      lastJoinError = 'PIN inválido: debe tener 6 caracteres.';
      return false;
    }

    final name = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : _navidrome.username ?? _getDefaultDeviceName();
    final color = customColor ?? 0xFF10B981; // Neon Emerald

    final candidates = <(String, int)>[
      (host, port),
      if (fallbackHost != null && fallbackPort != null)
        (fallbackHost, fallbackPort),
      if (port != kJamHostPort) (host, kJamHostPort),
    ];
    final seen = <String>{};
    var success = false;

    // El callback de state_sync puede llegar antes de que connect() devuelva.
    // Establecer el rol primero permite que el modo sincronizado cargue audio
    // inmediatamente al aceptar la sesión.
    _role = JamRole.guest;
    _localParticipant = JamParticipant(
      id: 'guest_local',
      name: name,
      avatarColorValue: color,
      isHost: false,
      joinedAt: DateTime.now(),
    );

    for (final candidate in candidates) {
      final candidateHost = candidate.$1.trim();
      final candidatePort = candidate.$2;
      if (candidateHost.isEmpty ||
          candidatePort <= 0 ||
          candidatePort > 65535 ||
          !seen.add('$candidateHost:$candidatePort')) {
        continue;
      }
      success = await _guestService.connect(
        host: candidateHost,
        port: candidatePort,
        pin: normalizedPin,
        name: name,
        avatarColorValue: color,
      );
      if (success) break;
      lastJoinError = _guestService.lastError;
    }

    if (success) {
      lastJoinError = null;
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
      _localParticipant = null;
      _session = null;
      lastJoinError ??= 'No se pudo conectar al host indicado.';
      notifyListeners();
      return false;
    }
  }

  /// Prueba HTTP rápida contra `http://host:port/jam/status`.
  Future<String> testHostReachable(String host, int port) =>
      _guestService.testHostReachable(host, port);

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
        final key = '${s.host}:${s.pin}';
        map[key] = s;
      }

      for (final s in serverResults) {
        final key = '${s.host}:${s.pin}';
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
      fallbackHost: disc.remoteHost,
      fallbackPort: disc.remotePort,
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
      fallbackHost: data.remoteHost,
      fallbackPort: data.remotePort,
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
      final targetPositionMs = positionMs + (isPlaying ? transitDelayMs : 0);

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

  Future<void> addTrackToJam(Track track, {bool playNext = false}) async {
    if (!inJam) return;

    if (isHost) {
      await _addTrackAsHost(track, _localParticipant, playNext: playNext);
    } else if (isGuest) {
      _guestService.addToQueue(track, playNext: playNext);
    }
  }

  void removeTrackFromJam(String queueItemId, {int? orderIndex}) {
    if (!inJam) return;

    if (isHost) {
      _removeTrackAsHost(queueItemId);
    } else if (isGuest) {
      _guestService.removeFromQueue(queueItemId);
    }
  }

  void reorderJamQueue(int oldIndex, int newIndex) {
    if (!inJam) return;

    if (isHost) {
      _reorderQueueAsHost(oldIndex, newIndex);
    } else if (isGuest) {
      _guestService.reorderQueue(oldIndex, newIndex);
    }
  }

  Future<void> playbackAction(String action, {Duration? position}) async {
    if (!inJam) return;

    if (isHost) {
      await _applyPlaybackAction(action, position: position);
    } else if (isGuest) {
      _guestService.sendPlaybackControl(
        action,
        positionMs: position?.inMilliseconds,
      );
    }
  }

  void updateJamSettings({
    JamMode? mode,
    bool? allowGuestControls,
    bool? allowGuestQueueManage,
    bool? isPublic,
    int? maxParticipants,
    String? initialPlaylistId,
  }) {
    if (!isHost) return;

    _hostService.updateSettings(
      mode: mode,
      allowGuestControls: allowGuestControls,
      allowGuestQueueManage: allowGuestQueueManage,
      isPublic: isPublic,
      maxParticipants: maxParticipants,
      initialPlaylistId: initialPlaylistId,
    );

    _syncHostState();
    if (_session != null) _hostService.broadcastSessionState(_session!);
    _publishToNavidromeIfPublic();
    notifyListeners();
  }

  void kickParticipant(String participantId) {
    if (!isHost) return;
    _hostService.kickParticipant(participantId);
    _syncHostState();
    if (_session != null) _hostService.broadcastSessionState(_session!);
    notifyListeners();
  }

  Future<void> leaveOrEndSession() async {
    _hostSyncHeartbeat?.cancel();
    _hostSyncHeartbeat = null;
    _hostPublishTimer?.cancel();
    _hostPublishTimer = null;

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
    _trackAddedBy.clear();
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
    _hostPublishTimer?.cancel();
    _player.removeListener(_onPlayerChangedAsHost);
    _hostService.stop();
    _guestService.disconnect();
    super.dispose();
  }
}
