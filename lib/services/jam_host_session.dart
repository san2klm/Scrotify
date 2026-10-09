part of 'jam_controller.dart';

/// Anfitrión: crear la sala, traspasar el mando, publicar el estado y registrar el historial.
mixin _JamHostSession on _JamBase {
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
    String? roomPassword,
    bool failover = false,
    String? fixedPin,
    String? ownerToken,
    JamQueueMode queueMode = JamQueueMode.free,
    int fairTurnsPerPerson = 1,
    bool requireApproval = false,
  }) async {
    await leaveOrEndSession();
    _queueMode = queueMode;
    _fairTurnsPerPerson = fairTurnsPerPerson.clamp(1, 10);
    _requireApproval = requireApproval || queueMode == JamQueueMode.approval;
    _pendingRequests.clear();
    _votes.clear();
    _pinnedIds.clear();
    _myVotes.clear();
    _history.clear();
    _guestHistory.reset();
    _historyOwnerName = null;
    _lastVotesByTrack.clear();
    _histTrack = null;

    // Sala persistente: PIN fijo (validado con el alfabeto de JamCode).
    JamCode pinCode;
    try {
      pinCode = fixedPin != null && fixedPin.trim().isNotEmpty
          ? JamCode(fixedPin)
          : JamCode.generate();
    } on ArgumentError {
      lastJoinError = 'PIN fijo inválido: 6 caracteres sin 0, 1, I, O.';
      notifyListeners();
      return;
    }
    _remoteService.failoverEnabled = failover;
    unawaited(_loadCloudCapabilities());
    _remoteService.ownerToken = ownerToken?.trim();
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

    // La contraseña solo aplica a salas persistentes (PIN fijo).
    final password = fixedPin?.trim().isNotEmpty == true
        ? roomPassword?.trim()
        : null;
    _hasRoomPassword = password != null && password.isNotEmpty;
    _remoteService.roomPassword = _hasRoomPassword ? password : null;
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
    _hostService.roomPassword = _hasRoomPassword ? password : null;
    _hostService.chatEnabled = true;
    _chatEnabledForRoom = true;

    _role = JamRole.host;
    _rebuildHostQueueFromPlayer();
    _onPlayerChangedAsHost();
    _syncHostState();

    // Publicar sala en el servidor WebSocket central (jam.templo.cloud)
    await _createRemoteRoom();

    _publishToNavidromeIfPublic();

    _startHostLoops();
    notifyListeners();
  }

  /// Escucha al reproductor y arranca heartbeat/anuncios del anfitrión. Lo usa
  /// también un invitado que pasa a anfitrión (transferencia/failover).
  void _startHostLoops() {
    _player.removeListener(_onPlayerChangedAsHost);
    _player.addListener(_onPlayerChangedAsHost);

    // Heartbeat periódico para sincronización precisa
    _hostSyncHeartbeat?.cancel();
    _hostSyncHeartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_role == JamRole.host && _hostService.isRunning) {
        _syncHostPlayback();
        unawaited(_createRemoteRoom(retry: true));
      }
    });

    // El anuncio remoto expira, por lo que se renueva mientras el host exista.
    _hostPublishTimer?.cancel();
    _hostPublishTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _publishToNavidromeIfPublic();
    });
  }

  // ---------------------------------------------------------------------------
  // Continuidad: transferencia de anfitrión (solo salas en la nube)
  // ---------------------------------------------------------------------------

  /// Participantes remotos a los que se puede ceder la sala (tienen ID en el relay).
  List<JamParticipant> get transferableParticipants => isHost
      ? _remoteParticipants
          .where((p) => _remoteService.guestIds.containsKey(p.name))
          .toList()
      : const [];

  /// Cede el anfitrión a [participant]. Solo en la nube; en LAN el host es el
  /// servidor embebido (ver `migrateToCloud`, no disponible aún).
  bool transferHostTo(JamParticipant participant) {
    if (!isHost || !_remoteService.isConnected) {
      _reportActionError('Solo se puede transferir el anfitrión en una sala en la nube.');
      return false;
    }
    final ok = _remoteService.transferHost(participant.name);
    if (!ok) _reportActionError('No se pudo transferir: el invitado no está registrado en el relay.');
    return ok;
  }

  /// Enlace compartible `https://<servidor>/j/<PIN>` (si el relay lo permite).
  String? get shareLink {
    final pin = _hostService.pinCode?.value ?? _session?.pinCode;
    if (pin == null || pin.isEmpty) return null;
    final ep = _remoteEndpoint;
    if (!ep.isValid) return null;
    return ep.httpBase.replace(path: '/j/$pin').toString();
  }

  @override
  Future<void> _handleRemoteHostChanged(
    bool youAreHost,
    String hostName,
    List<Map<String, dynamic>> guests,
  ) async {
    if (youAreHost && isGuest) {
      await _becomeRemoteHost(guests);
    } else if (!youAreHost && isHost) {
      await _demoteToRemoteGuest(hostName);
    } else if (!youAreHost && isGuest && _session != null) {
      _session = _session!.copyWith(hostName: hostName);
      notifyListeners();
    }
  }

  /// Un invitado asume el rol de anfitrión: arranca el servidor LAN con el
  /// mismo PIN, reconstruye la cola desde el último estado y empieza a emitir.
  Future<void> _becomeRemoteHost(List<Map<String, dynamic>> guests) async {
    final prev = _session;
    final pin = _remoteService.pin;
    if (prev == null || pin == null || _localParticipant == null) return;

    _syncGeneration++;
    unawaited(_player.setPlaybackSpeed(1.0));
    final me = _localParticipant!;
    _localParticipant = JamParticipant(
      id: 'host_local',
      name: me.name,
      avatarColorValue: 0xFFA855F7,
      isHost: true,
      joinedAt: DateTime.now(),
    );
    _queueMode = prev.queueMode;
    _fairTurnsPerPerson = prev.fairTurnsPerPerson;
    _requireApproval = prev.requireApproval;
    _pendingRequests.clear();
    _votes.clear();
    _pinnedIds.clear();
    _trackAddedBy.clear();
    _hostJamQueue.clear();
    _remoteParticipants
      ..clear()
      ..addAll([
        for (final g in guests)
          JamParticipant(
            id: 'remote_${g['id']}',
            name: g['name']?.toString() ?? 'Invitado',
            avatarColorValue: 0xFF3B82F6,
            isHost: false,
            joinedAt: DateTime.now(),
            canControlPlayback: prev.allowGuestControls,
            canManageQueue: prev.allowGuestQueueManage,
          ),
      ]);

    // Reproductor: la pista actual y la cola resueltas contra MI biblioteca.
    final wanted = <Track>[
      if (prev.currentTrack != null) prev.currentTrack!,
      ...prev.queue.map((q) => q.track),
    ];
    final local = <Track>[];
    for (final t in wanted) {
      try {
        final r = await _resolver.resolve(t);
        if (r.isAvailable) local.add(r.track!);
      } catch (_) {
        local.add(t);
      }
    }
    if (local.isNotEmpty &&
        (_player.currentTrack == null ||
            _player.currentTrack!.id != local.first.id)) {
      await _player.playQueue(local, startIndex: 0);
      await _player.seek(Duration(milliseconds: prev.positionMs));
      if (!prev.isPlaying && _player.playing) await _player.togglePlay();
    }

    _hostService.roomPassword = null; // el relay conserva la suya
    await _hostService.start(
      sessionId: 'jam_${DateTime.now().millisecondsSinceEpoch}',
      pinCode: JamCode(pin),
      hostName: me.name,
      mode: prev.mode,
      allowGuestControls: prev.allowGuestControls,
      allowGuestQueueManage: prev.allowGuestQueueManage,
      isPublic: prev.isPublic,
      maxParticipants: prev.maxParticipants,
    );
    _role = JamRole.host;
    _currentTrackAddedBy = _localParticipant;
    _rebuildHostQueueFromPlayer();
    _onPlayerChangedAsHost();
    _syncHostState();
    _startHostLoops();
    _publishHostState(includePlayback: true);
    lastActionError = null;
    notifyListeners();
  }

  /// El anfitrión cedió la sala: deja de emitir y pasa a seguir al nuevo.
  Future<void> _demoteToRemoteGuest(String newHostName) async {
    _hostSyncHeartbeat?.cancel();
    _hostSyncHeartbeat = null;
    _hostPublishTimer?.cancel();
    _hostPublishTimer = null;
    _player.removeListener(_onPlayerChangedAsHost);
    _trackHistory(finalize: true);
    await _hostService.stop();
    final prev = _session;
    final me = _localParticipant;
    _role = JamRole.guest;
    _localParticipant = me?.copyWith(
      id: 'guest_remote',
      isHost: false,
      canControlPlayback: prev?.allowGuestControls ?? true,
      canManageQueue: prev?.allowGuestQueueManage ?? true,
    );
    _hostJamQueue.clear();
    _remoteParticipants.clear();
    if (_session != null) _session = _session!.copyWith(hostName: newHostName);
    _lastSyncServerTimestamp = 0;
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
      if (curTrack?.mbid != null) 'mbid': curTrack!.mbid,
      if (curTrack?.isrc != null) 'isrc': curTrack!.isrc,
      if (curTrack?.trackNumber != null) 'trackNumber': curTrack!.trackNumber,
      'mode': _hostService.mode.name,
      'allowGuestControls': _hostService.allowGuestControls,
      'allowGuestQueueManage': _hostService.allowGuestQueueManage,
      'isPublic': isPublic,
      if (_remoteService.clock.isReady)
        'refTs': _remoteService.clock
            .toReference(DateTime.now().millisecondsSinceEpoch),
      'nextHint': () {
        final hint = _nextTrackHint();
        if (hint == null) return null;
        return {
          'track': _trackHintJson(hint.track),
          'startAtMs': _remoteService.clock.toReference(hint.startAtLocalMs),
        };
      }(),
      'queueMode': _queueMode.name,
      'fairTurnsPerPerson': _fairTurnsPerPerson,
      'requireApproval': _requireApproval,
      'pendingRequests':
          _pendingRequests.take(20).map((r) => r.toJson()).toList(),
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
      // Con un hostToken vigente se intenta recuperar la misma sala (el relay
      // la conserva durante hostFailoverMs); si falla se crea de nuevo.
      final resuming = retry && _remoteService.hostToken != null;
      var ok = await _remoteService.createRoom(
        pin: pin,
        hostName: _localParticipant?.name ?? 'Host',
        initialState: _remoteStatePayload(),
        resume: resuming,
        isPublic: isPublic,
      );
      if (resuming && !ok) {
        _remoteService.hostToken = null;
        ok = await _remoteService.createRoom(
          pin: pin,
          hostName: _localParticipant?.name ?? 'Host',
          initialState: _remoteStatePayload(),
          isPublic: isPublic,
        );
      }
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
    _trackHistory();
    _syncHostState();
    if (_session != null) _hostService.broadcastSessionState(_session!);
    _syncHostPlayback();
    _publishToNavidromeIfPublic();
    notifyListeners();
  }

  @override
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
      queueMode: _queueMode,
      fairTurnsPerPerson: _fairTurnsPerPerson,
      requireApproval: _requireApproval,
      pendingRequests: List.of(_pendingRequests),
    );
  }

  /// Registra en el historial la pista que acaba de terminar (si cumple el
  /// umbral) y empieza a seguir la nueva. Con [finalize] cierra la actual.
  void _trackHistory({bool finalize = false}) {
    final cur = finalize ? null : _player.currentTrack;
    if (finalize && _player.position > _histMaxPos) {
      _histMaxPos = _player.position;
    }
    if (_histTrack != null && cur?.id != _histTrack!.id) {
      _history.record(
        _histTrack!,
        _histAddedBy,
        listened: _histMaxPos,
        total: parseTrackDuration(_histTrack!.duration),
        votes: _lastVotesByTrack[_histTrack!.id] ?? 0,
      );
      _histTrack = null;
    }
    if (cur == null) return;
    if (_histTrack == null) {
      _histTrack = cur;
      _histAddedBy = _currentTrackAddedBy;
      _histMaxPos = Duration.zero;
    }
    final pos = _player.position;
    if (pos > _histMaxPos) _histMaxPos = pos;
  }

  void _syncHostPlayback() {
    if (_role != JamRole.host) return;
    _trackHistory();
    final curTrack = _player.currentTrack;
    final pos = _player.position.inMilliseconds;
    final playing = _player.playing;

    final hint = _nextTrackHint();
    if (hint != null && _hintSentForTrackId != curTrack?.id) {
      _hintSentForTrackId = curTrack?.id;
      _hostService.broadcastMessage({
        'op': 'next_track_hint',
        'track': _trackHintJson(hint.track),
        'startAtServerMs': hint.startAtLocalMs,
      });
    } else if (hint == null && _hintSentForTrackId != curTrack?.id) {
      _hintSentForTrackId = null;
    }

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

  @override
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
}
