part of 'jam_controller.dart';

/// Anfitrión: cola de la Jam (alta, modos, votos, aprobación, orden) y acciones de los invitados.
mixin _JamHostQueue on _JamBase {
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

    _hostService.onSocial = (from, emoji, text) {
      if (emoji != null) _receiveReaction(from, emoji);
      if (text != null) _receiveChat(from, text);
    };

    _hostService.onVoteRequested = (itemId, value, participant) {
      _handleVote(itemId, value, participant.id);
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

  @override
  Future<void> _addTrackAsHost(
    Track track,
    JamParticipant? addedBy, {
    required bool playNext,
    bool bypassApproval = false,
  }) async {
    if (!isHost) return;

    // Modo aprobación: las canciones de invitados esperan al visto bueno.
    if (!bypassApproval &&
        addedBy != null &&
        !addedBy.isHost &&
        (_requireApproval || _queueMode == JamQueueMode.approval)) {
      _addPendingRequest(track, addedBy, playNext);
      return;
    }

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
    if (!playNext) _applyQueueModeOrdering();
    _publishHostState(includePlayback: true);
  }

  // ---------------------------------------------------------------------------
  // Modos de cola (host)
  // ---------------------------------------------------------------------------

  JamQueueMode get _orderMode => switch (_queueMode) {
        JamQueueMode.fairTurns => JamQueueMode.fairTurns,
        JamQueueMode.voting => JamQueueMode.voting,
        _ => JamQueueMode.free,
      };

  /// Refleja votos y fijados en los ítems publicados.
  void _refreshItemMeta() {
    for (var i = 0; i < _hostJamQueue.length; i++) {
      final item = _hostJamQueue[i];
      final votes = _votes.total(item.id);
      _lastVotesByTrack[item.track.id] = votes;
      final pinned = _pinnedIds.contains(item.id);
      if (votes != item.votes || pinned != item.pinned) {
        _hostJamQueue[i] = item.copyWith(votes: votes, pinned: pinned);
      }
    }
  }

  /// Reordena la cola del reproductor según el modo, sin tocar la pista
  /// actual (solo mueve ítems pendientes).
  void _applyQueueModeOrdering() {
    if (!isHost) return;
    _refreshItemMeta();
    if (_orderMode == JamQueueMode.free) return;
    final target = orderQueue(_hostJamQueue,
        mode: _orderMode, fairTurnsPerPerson: _fairTurnsPerPerson);
    final moves = reorderMoves(
      _hostJamQueue.map((e) => e.id).toList(),
      target.map((e) => e.id).toList(),
    );
    if (moves.isEmpty) return;
    final offset =
        _player.currentOrderPos >= 0 ? _player.currentOrderPos + 1 : 0;
    for (final (from, to) in moves) {
      _player.reorderQueue(offset + from, offset + to);
    }
    _hostJamQueue
      ..clear()
      ..addAll(target);
    _queueRevision++;
    _rebuildHostQueueFromPlayer();
    _refreshItemMeta();
  }

  void _addPendingRequest(Track track, JamParticipant by, bool playNext) {
    final duplicate = _pendingRequests
        .any((r) => r.requestedById == by.id && r.track.id == track.id);
    if (duplicate || _pendingRequests.length >= JamController._maxPendingRequests) return;
    _pendingRequests.add(JamQueueRequest(
      id: 'req_${DateTime.now().microsecondsSinceEpoch}_${_pendingRequests.length}',
      track: track,
      requestedById: by.id,
      requestedByName: by.name,
      requestedAt: DateTime.now(),
      playNext: playNext,
    ));
    _queueRevision++;
    _publishHostState();
  }

  Future<void> approveRequest(String requestId) async {
    if (!isHost) return;
    final i = _pendingRequests.indexWhere((r) => r.id == requestId);
    if (i < 0) return;
    final r = _pendingRequests.removeAt(i);
    final by = _participantById(r.requestedById) ??
        JamParticipant(
          id: r.requestedById,
          name: r.requestedByName,
          avatarColorValue: 0xFF3B82F6,
          isHost: false,
          joinedAt: DateTime.now(),
        );
    await _addTrackAsHost(r.track, by,
        playNext: r.playNext, bypassApproval: true);
  }

  void rejectRequest(String requestId) {
    if (!isHost) return;
    final before = _pendingRequests.length;
    _pendingRequests.removeWhere((r) => r.id == requestId);
    if (_pendingRequests.length == before) return;
    _queueRevision++;
    _publishHostState();
  }

  Future<void> approveAllRequests() async {
    for (final id in _pendingRequests.map((r) => r.id).toList()) {
      await approveRequest(id);
    }
  }

  JamParticipant? _participantById(String id) {
    for (final p in [..._hostService.participants, ..._remoteParticipants]) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Cambia el modo de cola en vivo. `voting` excluye a `fairTurns`; la
  /// aprobación se combina con cualquier orden.
  void setQueueMode(
    JamQueueMode mode, {
    int? fairTurnsPerPerson,
    bool? requireApproval,
  }) {
    if (!isHost) return;
    _queueMode = mode;
    if (fairTurnsPerPerson != null) {
      _fairTurnsPerPerson = fairTurnsPerPerson.clamp(1, 10);
    }
    if (requireApproval != null) _requireApproval = requireApproval;
    if (mode == JamQueueMode.approval) _requireApproval = true;
    if (!(_requireApproval || mode == JamQueueMode.approval) &&
        _pendingRequests.isNotEmpty) {
      // Se desactivó la aprobación: las pendientes pasan a la cola.
      unawaited(approveAllRequests());
    }
    _applyQueueModeOrdering();
    _queueRevision++;
    _publishHostState();
  }

  void pinQueueItem(String itemId, bool pinned) {
    if (!isHost) return;
    final changed = pinned ? _pinnedIds.add(itemId) : _pinnedIds.remove(itemId);
    if (!changed) return;
    _applyQueueModeOrdering();
    _queueRevision++;
    _publishHostState();
  }

  @override
  void _handleVote(String itemId, int value, String participantId) {
    if (!isHost || _queueMode != JamQueueMode.voting) return;
    if (!_hostJamQueue.any((i) => i.id == itemId)) return;
    if (!_votes.vote(itemId, participantId, value)) return;
    _applyQueueModeOrdering();
    _queueRevision++;
    _publishHostState();
  }

  /// Vota (+1/−1, 0 quita) un ítem de la cola. Funciona como host o invitado.
  void voteOnItem(String itemId, int value) {
    if (!inJam) return;
    _clearActionError();
    final v = value.clamp(-1, 1);
    if (isHost) {
      _handleVote(itemId, v, 'host_local');
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.sendVote(itemId, v);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('vote', {'itemId': itemId, 'value': v});
      } else {
        _reportActionError('No hay conexión activa con el anfitrión Jam.');
        return;
      }
      _myVotes[itemId] = v;
      notifyListeners();
    }
  }

  @override
  void _removeTrackAsHost(String queueItemId) {
    if (!isHost) return;
    final queueIndex =
        _hostJamQueue.indexWhere((item) => item.id == queueItemId);
    if (queueIndex < 0) return;

    final item = _hostJamQueue[queueIndex];
    final playerIndex = _playerOrderIndexForQueueItem(queueIndex, item);
    if (playerIndex < 0) return;

    _hostJamQueue.removeAt(queueIndex);
    _votes.removeItem(item.id);
    _pinnedIds.remove(item.id);
    if (!_hostJamQueue.any((qi) => qi.track.id == item.track.id)) {
      _trackAddedBy.remove(item.track.id);
    }
    _player.removeFromQueue(playerIndex);
    _queueRevision++;
    _rebuildHostQueueFromPlayer();
    _publishHostState();
  }

  @override
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
  @override
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
    _refreshItemMeta();
  }

  @override
  void _publishToNavidromeIfPublic() {
    if (!isHost || _session == null || !_session!.isPublic) return;
    unawaited(_navidrome.publishServerJam(_session!));
  }

  @override
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
}
