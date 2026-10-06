import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/jam_models.dart';
import 'jam_guest_service.dart';
import 'jam_host_service.dart';
import 'jam_tls_identity.dart';
import 'navidrome_service.dart';
import 'player_controller.dart';
import 'remote_jam_service.dart';
import 'settings_controller.dart';

/// Controlador principal de sesiones Jam.
/// Actúa como puente entre los servicios de red ([JamHostService], [JamGuestService], [RemoteJamService])
/// y el reproductor de audio ([PlayerController]).
class JamController extends ChangeNotifier {
  final PlayerController _player;
  final NavidromeService _navidrome;

  final JamHostService _hostService = JamHostService();
  final JamGuestService _guestService = JamGuestService();
  final RemoteJamService _remoteService = RemoteJamService();

  JamRole _role = JamRole.none;
  JamSessionState? _session;
  JamParticipant? _localParticipant;
  final List<JamParticipant> _remoteParticipants = [];
  final Set<String> _kickedRemoteNames = {};

  List<DiscoveredJamSession> _discoveredSessions = [];
  bool _isScanningRadar = false;

  /// Motivo legible del último [joinSession] fallido, para mostrar en UI.
  String? lastJoinError;

  /// Motivo legible del último fallo de acción colaborativa, para mostrar en UI.
  String? lastActionError;

  // Cola de items con trazabilidad (solo en Host)
  final List<JamQueueItem> _hostJamQueue = [];
  final Map<String, JamParticipant?> _trackAddedBy = {};
  JamParticipant? _currentTrackAddedBy;
  int _queueRevision = 0;

  int _lastSyncServerTimestamp = 0;
  int _syncGeneration = 0;

  bool _remoteCreating = false;
  int _remoteCreateFailures = 0;
  DateTime? _nextRemoteCreateAt;

  Timer? _hostSyncHeartbeat;
  Timer? _hostPublishTimer;

  final SettingsController? _settings;

  /// Endpoint remoto vigente ya validado (host/puerto para anunciar salas).
  JamServerEndpoint get _remoteEndpoint =>
      JamServerEndpoint.parse(_remoteService.endpoint);

  JamController(this._player, this._navidrome, {SettingsController? settings})
      : _settings = settings {
    _applyServerUrl();
    _settings?.addListener(_applyServerUrl);
    _initHostCallbacks();
    _initGuestCallbacks();
    _initRemoteCallbacks();
    debugPrint(
      '[JAM] JamController init: id=${identityHashCode(this)} '
      'rev=${_session?.queueRevision ?? 0} qLen=${_session?.queue.length ?? 0} '
      'trackId=${_session?.currentTrack?.id} '
      'canCtrl=${_localParticipant?.canControlPlayback ?? false} '
      'canQueue=${_localParticipant?.canManageQueue ?? false}',
    );
  }

  void _applyServerUrl() {
    final url = _settings?.jamServerUrl;
    if (url != null && url != _remoteService.endpoint) {
      _remoteService.setEndpoint(url);
    }
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  JamRole get role => _role;
  JamSessionState? get session => _session;
  JamParticipant? get localParticipant => _localParticipant;
  List<JamParticipant> get participants => _session?.participants ?? [];
  List<JamQueueItem> get jamQueue => _session?.queue ?? [];
  List<JamQueueItem> get queue => jamQueue;
  bool isTrackInJamQueue(String trackId) =>
      jamQueue.any((qi) => qi.track.id == trackId);
  JamMode get mode => _session?.mode ?? JamMode.synchronizedListening;
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
  JamConnectionState get connectionState => _guestService.connectionState;
  int get queueRevision =>
      isGuest ? _guestService.queueRevision : _queueRevision;
  String? get lastError =>
      lastActionError ?? lastJoinError ?? _guestService.lastError;

  // ---------------------------------------------------------------------------
  // Inicialización de Callbacks del Host
  // ---------------------------------------------------------------------------
  void _initHostCallbacks() {
    _hostService.getCurrentSessionState = () => _session!;

    _hostService.onJoinRequested = (participant, socket) async {
      if (!isHost || _session == null) return false;
      _syncHostState();
      // JamHostService owns the one join_response + one canonical snapshot
      // sent to the joining socket. Existing guests only need the participant
      // update, and must not cause a duplicate sync for the new guest.
      _hostService.broadcastSessionState(
        _session!,
        excludeParticipantId: participant.id,
      );
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
    _trackAddedBy[track.id] = addedBy;
    if (playNext) {
      _hostJamQueue.insert(0, queueItem);
      await _player.addNextInQueue(track);
    } else {
      _hostJamQueue.add(queueItem);
      await _player.addToQueue(track);
    }

    _queueRevision++;
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
    if (!_hostJamQueue.any((qi) => qi.track.id == item.track.id)) {
      _trackAddedBy.remove(item.track.id);
    }
    _player.removeFromQueue(playerIndex);
    _queueRevision++;
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

    final playerOffset =
        _player.currentOrderPos >= 0 ? _player.currentOrderPos + 1 : 0;
    final realOld = playerOffset + oldIndex;
    final realNew = playerOffset + newIndex;
    if (realOld < 0 ||
        realOld >= _player.orderedQueue.length ||
        realNew < 0 ||
        realNew >= _player.orderedQueue.length) {
      return;
    }
    _player.reorderQueue(realOld, realNew);
    _queueRevision++;
    _rebuildHostQueueFromPlayer();
    _publishHostState();
  }

  int _playerOrderIndexForQueueItem(int queueIndex, JamQueueItem item) {
    final playerOffset =
        _player.currentOrderPos >= 0 ? _player.currentOrderPos + 1 : 0;
    final expected = playerOffset + queueIndex;
    final ordered = _player.orderedQueue;
    if (expected >= 0 &&
        expected < ordered.length &&
        (identical(ordered[expected], item.track) ||
            ordered[expected].id == item.track.id)) {
      return expected;
    }
    return ordered.indexWhere(
      (track) => identical(track, item.track) || track.id == item.track.id,
    );
  }

  /// Reconcilia la cola compartida con la cola efectiva del reproductor. El
  /// reproductor conserva la pista actual; la Jam sólo publica las siguientes.
  void _rebuildHostQueueFromPlayer() {
    if (!isHost || _localParticipant == null) return;

    final ordered = _player.orderedQueue;
    final currentOrderPos = _player.currentOrderPos;
    final current = _player.currentTrack;
    if (current != null) {
      _currentTrackAddedBy = _trackAddedBy[current.id] ?? _localParticipant;
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

      final addedBy = _trackAddedBy[track.id] ?? _localParticipant;
      _trackAddedBy[track.id] = addedBy;
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

  void _publishToNavidromeIfPublic() {
    if (!isHost || _session == null || !_session!.isPublic) return;
    unawaited(_navidrome.publishServerJam(_session!));
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
    _guestService.onConnectionStateChanged = (_) => notifyListeners();

    _guestService.onError = (message) {
      lastActionError = message;
      notifyListeners();
    };

    _guestService.onStateSync = (state) {
      _session = state;
      _currentTrackAddedBy = state.currentTrackAddedBy;
      _syncGuestAudioIfApplicable(
        track: state.currentTrack,
        isPlaying: state.isPlaying,
        positionMs: state.positionMs,
        serverTs: state.updatedAtMs,
      );
      debugPrint(
        '[JAM] JamController.onStateSync: id=${identityHashCode(this)} '
        'rev=${_session?.queueRevision ?? 0} qLen=${_session?.queue.length ?? 0} '
        'trackId=${_session?.currentTrack?.id} '
        'canCtrl=${_localParticipant?.canControlPlayback ?? false} '
        'canQueue=${_localParticipant?.canManageQueue ?? false}',
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
      debugPrint(
        '[JAM] JamController.onPlaybackUpdated: id=${identityHashCode(this)} '
        'rev=${_session?.queueRevision ?? 0} qLen=${_session?.queue.length ?? 0} '
        'trackId=${_session?.currentTrack?.id} '
        'canCtrl=${_localParticipant?.canControlPlayback ?? false} '
        'canQueue=${_localParticipant?.canManageQueue ?? false}',
      );
      notifyListeners();
    };

    _guestService.onQueueUpdated = (queue) {
      if (_session != null) {
        _session = _session!.copyWith(queue: queue);
        debugPrint(
          '[JAM] JamController.onQueueUpdated: id=${identityHashCode(this)} '
          'rev=${_session?.queueRevision ?? 0} qLen=${_session?.queue.length ?? 0} '
          'trackId=${_session?.currentTrack?.id} '
          'canCtrl=${_localParticipant?.canControlPlayback ?? false} '
          'canQueue=${_localParticipant?.canManageQueue ?? false}',
        );
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
  // Inicialización de Callbacks del Servidor Remoto (Cloud Jam)
  // ---------------------------------------------------------------------------
  void _initRemoteCallbacks() {
    _remoteService.onGuestJoined = (guestName, totalParticipants) {
      if (!isHost || _session == null) return;
      if (_kickedRemoteNames.contains(guestName.trim().toLowerCase())) {
        debugPrint('JamController: Expulsando invitado bloqueado: $guestName');
        _remoteService.kickGuest(guestName);
        return;
      }
      debugPrint(
          'JamController: Invitado remoto unido: $guestName ($totalParticipants)');
      final exists = _remoteParticipants.any((p) => p.name == guestName);
      if (!exists) {
        final newParticipant = JamParticipant(
          id: 'remote_${DateTime.now().microsecondsSinceEpoch}',
          name: guestName,
          avatarColorValue: 0xFF3B82F6,
          isHost: false,
          joinedAt: DateTime.now(),
          canControlPlayback: _session!.allowGuestControls,
          canManageQueue: _session!.allowGuestQueueManage,
        );
        _remoteParticipants.add(newParticipant);
        _syncHostState();
        _publishHostState();
        notifyListeners();
      }
    };

    _remoteService.onGuestAction = (fromGuest, actionType, payload) async {
      if (!isHost) return;
      debugPrint('JamController: Acción remota de $fromGuest: $actionType');
      final p = _remoteParticipants.firstWhere(
        (item) => item.name == fromGuest,
        orElse: () => JamParticipant(
          id: 'remote_guest',
          name: fromGuest,
          avatarColorValue: 0xFF3B82F6,
          isHost: false,
          joinedAt: DateTime.now(),
          canControlPlayback: _session?.allowGuestControls ?? true,
          canManageQueue: _session?.allowGuestQueueManage ?? true,
        ),
      );

      switch (actionType) {
        case 'playback_control':
          final canControl =
              (_session?.allowGuestControls ?? true) && p.canControlPlayback;
          if (canControl) {
            final action =
                payload is Map ? payload['action']?.toString() : null;
            final pos = payload is Map && payload['position'] != null
                ? Duration(milliseconds: (payload['position'] as num).toInt())
                : null;
            if (action != null) {
              await _applyPlaybackAction(action, position: pos);
            }
          }
          break;

        case 'queue_add':
          final canManage =
              (_session?.allowGuestQueueManage ?? true) && p.canManageQueue;
          if (canManage) {
            if (payload is Map) {
              final trackMap = payload['track'];
              final playNext = payload['playNext'] == true;
              if (trackMap is Map) {
                final track = Track.fromJson(Map<String, dynamic>.from(trackMap));
                await _addTrackAsHost(track, p, playNext: playNext);
              } else if (payload['trackId'] != null) {
                final trackId = payload['trackId'].toString();
                try {
                  final tracks = await _navidrome.getTracks(limit: 500);
                  final found = tracks.firstWhere((t) => t.id == trackId);
                  await _addTrackAsHost(found, p, playNext: playNext);
                } catch (_) {}
              }
            }
          }
          break;

        case 'queue_remove':
          final canManage =
              (_session?.allowGuestQueueManage ?? true) && p.canManageQueue;
          if (canManage) {
            final queueItemId =
                payload is Map ? payload['queueItemId']?.toString() : null;
            if (queueItemId != null) {
              _removeTrackAsHost(queueItemId);
            }
          }
          break;

        case 'queue_reorder':
          final canManage =
              (_session?.allowGuestQueueManage ?? true) && p.canManageQueue;
          if (canManage) {
            if (payload is Map) {
              final oldIdx = (payload['oldIndex'] as num?)?.toInt() ?? 0;
              final newIdx = (payload['newIndex'] as num?)?.toInt() ?? 0;
              _reorderQueueAsHost(oldIdx, newIdx);
            }
          }
          break;
      }
    };

    _remoteService.onError = (message) {
      lastActionError = message;
      notifyListeners();
    };

    _remoteService.onStateSync = (state) {
      if (!isGuest) return;
      _applyRemoteStateSync(state);
    };

    _remoteService.onRoomClosed = (reason) {
      if (isGuest) {
        leaveOrEndSession();
      }
    };
  }

  void _applyRemoteStateSync(Map<String, dynamic> state) {
    final trackId = state['trackId'] as String?;
    final positionMs = (state['position'] as num?)?.toInt() ?? 0;
    final isPlaying = state['isPlaying'] == true;
    final title = state['title'] as String?;
    final artist = state['artist'] as String?;
    final album = state['album'] as String?;
    final albumArtUrl = state['albumArtUrl'] as String?;
    final duration = state['duration']?.toString() ?? '0';
    final modeName = state['mode'] as String? ?? JamMode.partySpeaker.name;
    final mode = JamMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => JamMode.partySpeaker,
    );
    final allowControls = state['allowGuestControls'] ?? true;
    final allowQueue = state['allowGuestQueueManage'] ?? true;

    final rawQueue = state['queue'];
    final List<JamQueueItem> queue = [];
    if (rawQueue is List) {
      for (var i = 0; i < rawQueue.length; i++) {
        final item = rawQueue[i];
        if (item is Map) {
          try {
            queue.add(JamQueueItem.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        } else if (item is String && item.isNotEmpty) {
          queue.add(JamQueueItem(
            id: 'remote_q_${i}_$item',
            track: Track(
              id: item,
              title: 'Canción $item',
              artist: '',
              album: '',
              duration: '0',
            ),
            addedAt: DateTime.now(),
          ));
        }
      }
    }

    if (_localParticipant != null) {
      _localParticipant = _localParticipant!.copyWith(
        canControlPlayback: allowControls == true,
        canManageQueue: allowQueue == true,
      );
    }

    Track? currentTrack;
    if (trackId != null && trackId.isNotEmpty) {
      currentTrack = Track(
        id: trackId,
        title: title ?? 'Desconocido',
        artist: artist ?? 'Artista',
        album: album ?? '',
        albumArtUrl: albumArtUrl,
        duration: duration,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_session == null) {
      _session = JamSessionState(
        sessionId: 'remote_${_remoteService.pin}',
        pinCode: _remoteService.pin ?? '',
        hostName: state['hostName'] as String? ?? 'Anfitrión',
        hostIp: _remoteEndpoint.host,
        port: _remoteEndpoint.port,
        mode: mode,
        currentTrack: currentTrack,
        isPlaying: isPlaying,
        positionMs: positionMs,
        updatedAtMs: now,
        queue: queue,
        participants: [
          JamParticipant(
            id: 'remote_host',
            name: state['hostName'] as String? ?? 'Anfitrión',
            avatarColorValue: 0xFFA855F7,
            isHost: true,
            joinedAt: DateTime.now(),
          ),
          if (_localParticipant != null) _localParticipant!,
        ],
        allowGuestControls: allowControls,
        allowGuestQueueManage: allowQueue,
      );
    } else {
      _session = _session!.copyWith(
        currentTrack: currentTrack,
        isPlaying: isPlaying,
        positionMs: positionMs,
        updatedAtMs: now,
        mode: mode,
        queue: rawQueue != null ? queue : _session!.queue,
        allowGuestControls: allowControls,
        allowGuestQueueManage: allowQueue,
      );
    }

    _syncGuestAudioIfApplicable(
      track: currentTrack,
      isPlaying: isPlaying,
      positionMs: positionMs,
      serverTs: now,
    );

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Acciones de Anfitrión (Host)
  // ---------------------------------------------------------------------------

  Future<void> startHostSession({
    JamMode mode = JamMode.synchronizedListening,
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
    _remoteParticipants.clear();
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

    // Publicar sala en el servidor WebSocket central (jam.templo.cloud)
    await _createRemoteRoom();

    _publishToNavidromeIfPublic();

    // Suscribirse a cambios en PlayerController
    _player.addListener(_onPlayerChangedAsHost);

    // Heartbeat periódico para sincronización precisa
    _hostSyncHeartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_role == JamRole.host && _hostService.isRunning) {
        _syncHostPlayback();
        unawaited(_createRemoteRoom(retry: true));
      }
    });

    // El anuncio remoto expira, por lo que se renueva mientras el host exista.
    _hostPublishTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _publishToNavidromeIfPublic();
    });

    notifyListeners();
  }

  Map<String, dynamic> _remoteStatePayload() {
    final curTrack = _player.currentTrack;
    return {
      'trackId': curTrack?.id,
      'position': _player.position.inMilliseconds,
      'isPlaying': _player.playing,
      'queue': _hostJamQueue.map((item) => item.toJson()).toList(),
      'title': curTrack?.title,
      'artist': curTrack?.artist,
      'album': curTrack?.album,
      'albumArtUrl': sanitizeArtUrl(curTrack?.albumArtUrl),
      'duration': int.tryParse(curTrack?.duration ?? '') ?? 0,
      'mode': _hostService.mode.name,
      'allowGuestControls': _hostService.allowGuestControls,
      'allowGuestQueueManage': _hostService.allowGuestQueueManage,
    };
  }

  /// Registra la sala en el servidor central. Con [retry] sólo actúa si la
  /// conexión se perdió, espaciando los intentos con retroceso exponencial.
  Future<void> _createRemoteRoom({bool retry = false}) async {
    final pin = _hostService.pinCode?.value;
    if (!isHost || pin == null || _remoteCreating) return;
    if (retry) {
      if (_remoteService.isConnected) return;
      final next = _nextRemoteCreateAt;
      if (next != null && DateTime.now().isBefore(next)) return;
    }

    _remoteCreating = true;
    try {
      final ok = await _remoteService.createRoom(
        pin: pin,
        hostName: _localParticipant?.name ?? 'Host',
        initialState: _remoteStatePayload(),
      );
      debugPrint('JamController: Creación en servidor remoto: $ok');
      if (!isHost || _hostService.pinCode?.value != pin) {
        // La sesión terminó mientras se conectaba: no dejar la sala huérfana.
        await _remoteService.disconnect();
        return;
      }
      _remoteCreateFailures = ok ? 0 : _remoteCreateFailures + 1;
      final delaySeconds = 5 * (1 << _remoteCreateFailures.clamp(0, 5));
      _nextRemoteCreateAt = DateTime.now().add(Duration(seconds: delaySeconds));
    } finally {
      _remoteCreating = false;
    }
  }

  void _onPlayerChangedAsHost() {
    if (_role != JamRole.host) return;

    final curTrack = _player.currentTrack;
    _hostService.updateTrackMetadata(
      title: curTrack?.title,
      artist: curTrack?.artist,
      albumArtUrl: sanitizeArtUrl(curTrack?.albumArtUrl),
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
      participants: [
        _localParticipant!,
        ..._hostService.participants,
        ..._remoteParticipants,
      ],
      allowGuestControls: _hostService.allowGuestControls,
      allowGuestQueueManage: _hostService.allowGuestQueueManage,
      remoteHost: fallbackIp,
      remotePort: fallbackIp != null ? _hostService.port : null,
      isPublic: _hostService.isPublic,
      maxParticipants: _hostService.maxParticipants,
      initialPlaylistId: _hostService.initialPlaylistId,
      queueRevision: _queueRevision,
    );
  }

  void _syncHostPlayback() {
    if (_role != JamRole.host) return;
    final curTrack = _player.currentTrack;
    final pos = _player.position.inMilliseconds;
    final playing = _player.playing;

    _hostService.broadcastPlaybackUpdate(
      track: curTrack,
      addedBy: _currentTrackAddedBy,
      isPlaying: playing,
      positionMs: pos,
    );

    if (_remoteService.isConnected) {
      _remoteService.updateState(_remoteStatePayload());
    }
  }

  void _publishHostState({bool includePlayback = false}) {
    if (!isHost) return;
    _syncHostState();
    if (_session == null) return;
    _hostService.broadcastQueueUpdate(
      _hostJamQueue,
      queueRevision: _queueRevision,
    );
    _hostService.broadcastSessionState(_session!);
    if (includePlayback) _syncHostPlayback();
    _publishToNavidromeIfPublic();

    if (_remoteService.isConnected) {
      _remoteService.updateState(_remoteStatePayload());
    }

    notifyListeners();
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
    String? tlsFingerprint,
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
    if (!JamTlsIdentity.isValidFingerprint(tlsFingerprint)) {
      lastJoinError =
          'Esta Jam LAN no ofrece una identidad TLS verificable. Actualizá al anfitrión o usá una Jam remota WSS.';
      return false;
    }

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
        tlsFingerprint: tlsFingerprint!,
      );
      if (success) break;
      lastJoinError = _guestService.lastError;
    }

    if (!success) {
      // Si fallaron los candidatos LAN, intentar servidor central remoto
      success = await joinRemoteSession(
        pin: normalizedPin,
        customName: name,
        customColor: color,
      );
    }

    if (success) {
      lastJoinError = null;
      _localParticipant = _guestService.localParticipant ??
          _localParticipant ??
          JamParticipant(
            id: 'guest_local',
            name: name,
            avatarColorValue: color,
            isHost: false,
            joinedAt: DateTime.now(),
          );
      _session ??= _guestService.sessionState;
      debugPrint(
        '[JAM] JamController.joinSession: id=${identityHashCode(this)} '
        'rev=${_session?.queueRevision ?? 0} qLen=${_session?.queue.length ?? 0} '
        'trackId=${_session?.currentTrack?.id} '
        'canCtrl=${_localParticipant?.canControlPlayback ?? false} '
        'canQueue=${_localParticipant?.canManageQueue ?? false}',
      );
      notifyListeners();
      return true;
    } else {
      _role = JamRole.none;
      _localParticipant = null;
      _session = null;
      lastJoinError ??= 'No se pudo conectar a la sesión Jam.';
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
      // Escaneo triple: LAN (UDP Broadcast) + Servidor Navidrome + Servidor Central Jam (Cloud)
      final results = await Future.wait([
        _guestService.scanRadar(),
        _navidrome.getServerActiveJams(),
        _remoteService.getActiveRooms(),
      ]);

      final lanResults = results[0];
      final serverResults = results[1];
      final remoteResults = results[2];

      final Map<String, DiscoveredJamSession> map = {};

      // 1. Agregar salas del servidor central remoto (servidor configurado en Ajustes)
      for (final s in remoteResults) {
        final clean = s.pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (clean.isNotEmpty) {
          map[clean] = s;
        }
      }

      // 2. Agregar anuncios de Navidrome
      for (final s in serverResults) {
        final clean = s.pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (clean.isNotEmpty && !map.containsKey(clean)) {
          map[clean] = s;
        }
      }

      // 3. Si la sala está en la red local (LAN), preferir LAN por menor latencia
      for (final s in lanResults) {
        final clean = s.pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (clean.isNotEmpty) {
          map[clean] = s;
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
    final remoteHost = _remoteEndpoint.host;
    if (disc.host == remoteHost ||
        disc.port == 443 ||
        disc.remoteHost == remoteHost) {
      return joinRemoteSession(
        pin: disc.pin,
        customName: customName,
        customColor: customColor,
      );
    }
    // UDP discovery is intentionally unauthenticated. It can advertise a
    // session but cannot supply a trustworthy certificate pin, so LAN joining
    // remains QR-only until discovery messages have their own signed protocol.
    lastJoinError =
        'La Jam LAN fue descubierta, pero para unirse de forma segura escaneá el QR del anfitrión.';
    notifyListeners();
    return false;
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
      tlsFingerprint: data.tlsFingerprint,
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

      String? lanWarning;
      if (session != null) {
        final ok = await joinDiscovered(session,
            customName: customName, customColor: customColor);
        if (ok) return true;
        lanWarning = lastJoinError;
      }

      // 3. Conectar a través del servidor central WebSocket configurado en Ajustes
      final remoteOk = await joinRemoteSession(
        pin: pin,
        customName: customName,
        customColor: customColor,
      );
      if (!remoteOk && lanWarning != null) {
        lastJoinError = lanWarning;
        notifyListeners();
      }
      return remoteOk;
    } finally {
      _isScanningRadar = false;
      notifyListeners();
    }
  }

  /// Conecta directamente a una sesión remota alojada en el servidor central WebSocket.
  Future<bool> joinRemoteSession({
    required String pin,
    String? customName,
    int? customColor,
    String? customEndpoint,
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

    _role = JamRole.guest;
    _localParticipant = JamParticipant(
      id: 'guest_remote',
      name: name,
      avatarColorValue: color,
      isHost: false,
      joinedAt: DateTime.now(),
    );

    final state = await _remoteService.joinRoom(
      pin: normalizedPin,
      guestName: name,
      customEndpoint: customEndpoint,
    );

    if (state != null) {
      lastJoinError = null;
      _applyRemoteStateSync(state);
      notifyListeners();
      return true;
    } else {
      _role = JamRole.none;
      _localParticipant = null;
      _session = null;
      lastJoinError ??= _remoteService.lastError ??
          'No se encontró la sala Jam en el servidor central.';
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización de Audio para Invitados (Escucha Sincronizada)
  // ---------------------------------------------------------------------------

  Future<void> _syncGuestAudioIfApplicable({
    Track? track,
    required bool isPlaying,
    required int positionMs,
    required int serverTs,
  }) async {
    if (_role != JamRole.guest || _session == null) return;

    // Solo reproducir si estamos en modo Escucha Sincronizada
    if (_session!.mode == JamMode.synchronizedListening) {
      if (serverTs < _lastSyncServerTimestamp) {
        return;
      }
      _lastSyncServerTimestamp = serverTs;
      // Each update invalidates any earlier async playback operation. This is
      // deliberately incremented per frame, not merely when leaving a session.
      final currentGen = ++_syncGeneration;

      if (track == null) {
        _player.clearQueue();
        return;
      }

      // Si la canción actual es diferente, cargar y reproducir
      if (_player.currentTrack?.id != track.id) {
        await _player.playQueue([track], startIndex: 0);
        if (_syncGeneration != currentGen || _role != JamRole.guest) return;
      }

      // Compensación de latencia de red
      final now = DateTime.now().millisecondsSinceEpoch;
      final transitDelayMs = (now - serverTs).clamp(0, 5000);
      final targetPositionMs = positionMs + (isPlaying ? transitDelayMs : 0);

      final currentPosMs = _player.position.inMilliseconds;
      final drift = (targetPositionMs - currentPosMs).abs();

      if (drift > 450) {
        await _player.seek(Duration(milliseconds: targetPositionMs));
        if (_syncGeneration != currentGen || _role != JamRole.guest) return;
      }

      if (isPlaying && !_player.playing) {
        await _player.togglePlay();
        if (_syncGeneration != currentGen || _role != JamRole.guest) return;
      } else if (!isPlaying && _player.playing) {
        await _player.togglePlay();
        if (_syncGeneration != currentGen || _role != JamRole.guest) return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Acciones Compartidas (Cola y Reproducción)
  // ---------------------------------------------------------------------------

  Future<void> addTrackToJam(Track track, {bool playNext = false}) async {
    if (!inJam) return;
    _clearActionError();

    if (isHost) {
      await _addTrackAsHost(track, _localParticipant, playNext: playNext);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.addToQueue(track, playNext: playNext);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('queue_add', {
          'track': {
            'id': track.id,
            'title': track.title,
            'artist': track.artist,
            'album': track.album,
            'albumArtUrl': sanitizeArtUrl(track.albumArtUrl),
            'duration': track.duration,
          },
          'playNext': playNext,
        });
      } else {
        _reportActionError('No hay conexión activa con el anfitrión Jam.');
      }
    }
  }

  void removeTrackFromJam(String queueItemId, {int? orderIndex}) {
    if (!inJam) return;
    _clearActionError();

    if (isHost) {
      _removeTrackAsHost(queueItemId);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.removeFromQueue(queueItemId);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('queue_remove', {
          'queueItemId': queueItemId,
        });
      } else {
        _reportActionError('No hay conexión activa con el anfitrión Jam.');
      }
    }
  }

  void reorderJamQueue(int oldIndex, int newIndex) {
    if (!inJam) return;
    _clearActionError();

    if (isHost) {
      _reorderQueueAsHost(oldIndex, newIndex);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.reorderQueue(oldIndex, newIndex);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('queue_reorder', {
          'oldIndex': oldIndex,
          'newIndex': newIndex,
        });
      } else {
        _reportActionError('No hay conexión activa con el anfitrión Jam.');
      }
    }
  }

  Future<void> playbackAction(String action, {Duration? position}) async {
    if (!inJam) return;
    _clearActionError();

    if (isHost) {
      await _applyPlaybackAction(action, position: position);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.sendPlaybackControl(
          action,
          positionMs: position?.inMilliseconds,
        );
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('playback_control', {
          'action': action,
          'position': position?.inMilliseconds,
        });
      } else {
        _reportActionError('No hay conexión activa con el anfitrión Jam.');
      }
    }
  }

  void _clearActionError() {
    if (lastActionError == null) return;
    lastActionError = null;
    notifyListeners();
  }

  void _reportActionError(String message) {
    lastActionError = message;
    notifyListeners();
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

    if (allowGuestControls != null || allowGuestQueueManage != null) {
      for (var i = 0; i < _remoteParticipants.length; i++) {
        _remoteParticipants[i] = _remoteParticipants[i].copyWith(
          canControlPlayback:
              allowGuestControls ?? _remoteParticipants[i].canControlPlayback,
          canManageQueue:
              allowGuestQueueManage ?? _remoteParticipants[i].canManageQueue,
        );
      }
    }

    _syncHostState();
    if (_session != null) {
      _hostService.broadcastSessionState(_session!);
      if (_remoteService.isConnected) {
        _remoteService.updateState({
          'mode': _session!.mode.name,
          'allowGuestControls': _session!.allowGuestControls,
          'allowGuestQueueManage': _session!.allowGuestQueueManage,
        });
      }
    }
    _publishToNavidromeIfPublic();
    notifyListeners();
  }

  void kickParticipant(String participantId) {
    if (!isHost) return;
    // 1. Expulsar de la sesión local (LAN)
    _hostService.kickParticipant(participantId);

    // 2. Expulsar de la sesión remota (Cloud Jam)
    final remoteIdx =
        _remoteParticipants.indexWhere((p) => p.id == participantId);
    if (remoteIdx != -1) {
      final remoteP = _remoteParticipants[remoteIdx];
      _kickedRemoteNames.add(remoteP.name.trim().toLowerCase());
      _remoteService.kickGuest(remoteP.name);
      _remoteParticipants.removeAt(remoteIdx);
    }

    _syncHostState();
    _publishHostState();
    if (_session != null) _hostService.broadcastSessionState(_session!);
    notifyListeners();
  }

  Future<void> leaveOrEndSession() async {
    _syncGeneration++;
    _lastSyncServerTimestamp = 0;
    _hostSyncHeartbeat?.cancel();
    _hostSyncHeartbeat = null;
    _hostPublishTimer?.cancel();
    _hostPublishTimer = null;

    _player.removeListener(_onPlayerChangedAsHost);
    _remoteCreateFailures = 0;
    _nextRemoteCreateAt = null;

    if (_role == JamRole.host) {
      await _hostService.stop();
      await _remoteService.disconnect();
    } else if (_role == JamRole.guest) {
      await _guestService.disconnect();
      await _remoteService.disconnect();
    }

    _role = JamRole.none;
    _session = null;
    _localParticipant = null;
    _hostJamQueue.clear();
    _trackAddedBy.clear();
    _remoteParticipants.clear();
    _kickedRemoteNames.clear();
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
    _settings?.removeListener(_applyServerUrl);
    _syncGeneration++;
    _lastSyncServerTimestamp = 0;
    _hostSyncHeartbeat?.cancel();
    _hostPublishTimer?.cancel();
    _player.removeListener(_onPlayerChangedAsHost);
    _hostService.stop();
    _guestService.disconnect();
    super.dispose();
  }
}
