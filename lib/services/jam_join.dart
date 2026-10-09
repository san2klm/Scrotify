part of 'jam_controller.dart';

/// Unirse a una sala: LAN, radar, enlace, QR, PIN y servidor central.
mixin _JamJoin on _JamBase {
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
    String? password,
  }) async {
    await leaveOrEndSession();
    lastJoinError = null;
    _guestService.roomPassword = password;

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
    _startGuestHistory(name);
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
        password: password,
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

      String cleanPin(DiscoveredJamSession s) =>
          s.pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final lanPins = {for (final s in lanResults) cleanPin(s)};

      // 2. Agregar anuncios de Navidrome. Un anuncio sobrevive en el chat si
      // el anfitrión se cierra de golpe, así que solo se muestra si la sala
      // responde en la LAN o en el servidor central; si apunta a un servidor
      // central que no podemos consultar, se conserva (no hay forma de saberlo).
      final remoteHost = _remoteEndpoint.host;
      for (final s in serverResults) {
        final clean = cleanPin(s);
        if (clean.isEmpty || map.containsKey(clean)) continue;
        final foreignCloud = s.remoteHost != null && s.remoteHost != remoteHost;
        if (lanPins.contains(clean) || foreignCloud) map[clean] = s;
      }

      // 3. Si la sala está en la red local (LAN), preferir LAN por menor latencia
      for (final s in lanResults) {
        final clean = cleanPin(s);
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
    String? password,
  }) async {
    final remoteHost = _remoteEndpoint.host;
    if (disc.host == remoteHost ||
        disc.port == 443 ||
        disc.remoteHost == remoteHost) {
      return joinRemoteSession(
        pin: disc.pin,
        customName: customName,
        customColor: customColor,
        password: password,
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

  /// Une a una Jam en la nube desde un enlace de invitación (`JamInviteLink`).
  Future<bool> joinByLink(
    String link, {
    String? customName,
    int? customColor,
    String? password,
  }) async {
    final parsed = JamInviteLink.parse(link);
    if (parsed == null) {
      lastJoinError = 'El enlace de invitación no es válido.';
      notifyListeners();
      return false;
    }
    return joinRemoteSession(
      pin: parsed.code,
      customName: customName,
      customColor: customColor,
      customEndpoint: parsed.endpoint,
      password: password,
    );
  }

  Future<bool> joinByQr(
    String uri, {
    String? customName,
    int? customColor,
    String? password,
  }) async {
    if (JamInviteLink.parse(uri) != null) {
      return joinByLink(uri,
          customName: customName, customColor: customColor, password: password);
    }
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
      password: password,
    );
  }

  Future<bool> joinByPin(
    String pin, {
    String? customName,
    int? customColor,
    String? password,
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
            customName: customName,
            customColor: customColor,
            password: password);
        if (ok) return true;
        lanWarning = lastJoinError;
      }

      // 3. Conectar a través del servidor central WebSocket configurado en Ajustes
      final remoteOk = await joinRemoteSession(
        pin: pin,
        customName: customName,
        customColor: customColor,
        password: password,
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
    String? password,
  }) async {
    await leaveOrEndSession();
    lastJoinError = null;
    _remoteService.roomPassword = password;
    unawaited(_loadCloudCapabilities());

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
    _startGuestHistory(name);

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
}
