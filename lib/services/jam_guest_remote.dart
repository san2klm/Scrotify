part of 'jam_controller.dart';

/// Invitado y servidor central: historial del invitado, callbacks de red y sincronización del estado.
mixin _JamGuestRemote on _JamBase {
  // ---------------------------------------------------------------------------
  // Inicialización de Callbacks del Guest
  // ---------------------------------------------------------------------------
  /// Alimenta el historial del invitado con el estado que acaba de llegar.
  void _observeGuestHistory() {
    final session = _session;
    if (_role != JamRole.guest || session == null) return;
    _guestHistory.rememberQueue(session.queue);
    _guestHistory.observe(
      track: session.currentTrack,
      addedBy: session.currentTrackAddedBy,
      positionMs: session.positionMs,
    );
  }

  /// Empieza un historial nuevo al entrar en una sala como invitado.
  @override
  void _startGuestHistory(String name) {
    _history.clear();
    _guestHistory.reset();
    _historyOwnerName = name;
  }

  void _initGuestCallbacks() {
    _guestService.onConnectionStateChanged = (_) => notifyListeners();

    _guestService.onError = (message) {
      lastActionError = message;
      notifyListeners();
    };

    _guestService.onStateSync = (state) {
      _session = state;
      _currentTrackAddedBy = state.currentTrackAddedBy;
      _observeGuestHistory();
      _scheduleQueueResolve();
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
      _observeGuestHistory();
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
        _guestHistory.rememberQueue(queue);
        _scheduleQueueResolve();
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

    _guestService.onNextTrackHint = _handleNextHint;
    _guestService.onReaction = _receiveReaction;
    _guestService.onChat = (from, text, ts) => _receiveChat(from, text);

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
    _remoteService.onHostChanged = (youAreHost, hostName, state, guests) {
      unawaited(_handleRemoteHostChanged(youAreHost, hostName, guests));
    };
    _remoteService.onReaction = _receiveReaction;
    _remoteService.onChat = (from, text, ts) => _receiveChat(from, text);
    _remoteService.onChatState = (enabled) {
      _chatEnabledForRoom = enabled;
      notifyListeners();
    };
    _remoteService.onHostAway = (failoverMs) {
      if (!isGuest) return;
      lastActionError =
          'El anfitrión se desconectó; si no vuelve en ${(failoverMs / 1000).round()} s la sala cambiará de anfitrión.';
      notifyListeners();
    };
    _remoteService.onHostBack = () {
      if (lastActionError?.startsWith('El anfitrión se desconectó') ?? false) {
        lastActionError = null;
        notifyListeners();
      }
    };

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
                final track =
                    Track.fromJson(Map<String, dynamic>.from(trackMap));
                await _addTrackAsHost(track, p, playNext: playNext);
              } else if (payload['trackId'] != null) {
                final trackId = payload['trackId'].toString();
                try {
                  final tracks = await _navidrome.getTracks(limit: 500);
                  final found = tracks.firstWhere((t) => t.id == trackId);
                  await _addTrackAsHost(found, p, playNext: playNext);
                } catch (e) {
                  debugPrint(
                      'JamController: no se pudo añadir la canción pedida por un invitado: $e');
                }
              }
            }
          }
          break;

        case 'vote':
          if (payload is Map && payload['itemId'] is String) {
            final value = (payload['value'] as num?)?.toInt() ?? 0;
            _handleVote(payload['itemId'] as String, value.clamp(-1, 1), p.id);
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

    // Caída silenciosa del relé: avisar y dejar que el servicio reconecte.
    _remoteService.onConnectionLost = () {
      lastActionError =
          'Se perdió la conexión con el servidor CrotoLink central. Reconectando…';
      notifyListeners();
    };
    _remoteService.onReconnecting = (reconnecting) {
      if (!reconnecting && _remoteService.isConnected) {
        lastActionError = null;
        notifyListeners();
      }
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

  @override
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
          } catch (e) {
            debugPrint('JamController: elemento de cola ilegible: $e');
          }
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
        mbid: state['mbid'] as String?,
        isrc: state['isrc'] as String?,
        trackNumber: (state['trackNumber'] as num?)?.toInt(),
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
        queueMode: JamQueueMode.fromName(state['queueMode'] as String?),
        fairTurnsPerPerson:
            ((state['fairTurnsPerPerson'] as num?)?.toInt() ?? 1).clamp(1, 10),
        requireApproval: state['requireApproval'] == true,
        pendingRequests: parseJamRequests(state['pendingRequests']),
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
        queueMode: JamQueueMode.fromName(state['queueMode'] as String?),
        fairTurnsPerPerson:
            ((state['fairTurnsPerPerson'] as num?)?.toInt() ?? 1).clamp(1, 10),
        requireApproval: state['requireApproval'] == true,
        pendingRequests: parseJamRequests(state['pendingRequests']),
      );
    }

    _observeGuestHistory();
    _scheduleQueueResolve();
    final refTs = (state['refTs'] as num?)?.toInt();
    final useRef = refTs != null && _remoteService.clock.isReady;
    _syncGuestAudioIfApplicable(
      track: currentTrack,
      isPlaying: isPlaying,
      positionMs: positionMs,
      serverTs: useRef ? refTs : now,
      tsIsLocal: !useRef,
    );

    final hint = state['nextHint'];
    if (hint is Map && hint['track'] is Map) {
      try {
        _handleNextHint(
          Track.fromJson(Map<String, dynamic>.from(hint['track'] as Map)),
          (hint['startAtMs'] as num?)?.toInt() ?? 0,
        );
      } catch (e) {
        debugPrint('JamController: aviso de pista siguiente ilegible: $e');
      }
    }

    notifyListeners();
  }
}
