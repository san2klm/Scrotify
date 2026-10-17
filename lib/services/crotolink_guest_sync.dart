part of 'crotolink_controller.dart';

/// Invitado: sincronizar el audio con el anfitrión y precargar la siguiente pista.
mixin _CrotoLinkGuestSync on _CrotoLinkBase {
  // ---------------------------------------------------------------------------
  // Sincronización de Audio para Invitados (Escucha Sincronizada)
  // ---------------------------------------------------------------------------

  /// Reloj de referencia activo: el host en LAN o el relay en nube.
  ClockOffsetEstimator get _activeClock =>
      _guestService.isConnected ? _guestService.clock : _remoteService.clock;

  /// [serverTs] está en la hora de referencia (host/relay) salvo que
  /// [tsIsLocal] indique que ya es hora local (hosts antiguos sin sello).
  @override
  Future<void> _syncGuestAudioIfApplicable({
    Track? track,
    required bool isPlaying,
    required int positionMs,
    required int serverTs,
    bool tsIsLocal = false,
  }) async {
    if (_role != CrotoLinkRole.guest || _session == null) return;

    // Solo reproducir si estamos en modo Escucha Sincronizada
    if (_session!.mode == CrotoLinkMode.synchronizedListening) {
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

      // Emparejar con MI biblioteca (servidores distintos). Un error de red
      // degrada al comportamiento anterior (usar la pista tal cual).
      var playable = track;
      try {
        final resolution = await _resolver.resolve(track);
        if (_syncGeneration != currentGen || _role != CrotoLinkRole.guest) {
          return;
        }
        if (!resolution.isAvailable) {
          unavailableNotice =
              '«${track.title}» no está en tu biblioteca; se omite en tu dispositivo.';
          if (_player.playing) await _player.togglePlay();
          notifyListeners();
          return;
        }
        playable = resolution.track!;
        if (unavailableNotice != null) {
          unavailableNotice = null;
          notifyListeners();
        }
      } catch (e) {
        debugPrint(
            'CrotoLinkController: resolver no disponible ($e); uso la pista tal cual');
      }

      // Si la canción actual es diferente, cargar y reproducir
      if (_player.currentTrack?.id != playable.id) {
        await _player.playQueue([playable], startIndex: 0);
        if (_syncGeneration != currentGen || _role != CrotoLinkRole.guest) {
          return;
        }
      }

      // Compensación de latencia con el offset estimado respecto al reloj de
      // referencia. Sin muestras (o hora ya local) degrada al cálculo previo;
      // el clamp se mantiene como salvaguarda.
      final now = DateTime.now().millisecondsSinceEpoch;
      final clock = _activeClock;
      final sentLocal =
          tsIsLocal || !clock.isReady ? serverTs : clock.toLocal(serverTs);
      final transitDelayMs = (now - sentLocal).clamp(0, 5000);
      final targetPositionMs = positionMs + (isPlaying ? transitDelayMs : 0);

      final drift = targetPositionMs - _player.position.inMilliseconds;
      final decision = decideDriftCorrection(
        drift,
        currentSpeed: _player.playbackSpeed,
      );
      switch (decision.action) {
        case CrotoLinkDriftAction.seek:
          await _player.setPlaybackSpeed(1.0);
          await _player.seek(Duration(milliseconds: targetPositionMs));
          if (_syncGeneration != currentGen || _role != CrotoLinkRole.guest) {
            return;
          }
        case CrotoLinkDriftAction.nudge:
          if (isPlaying) {
            await _player.setPlaybackSpeed(decision.speed);
          } else {
            await _player.setPlaybackSpeed(1.0);
          }
        case CrotoLinkDriftAction.none:
          await _player.setPlaybackSpeed(1.0);
      }

      if (isPlaying && !_player.playing) {
        await _player.togglePlay();
        if (_syncGeneration != currentGen || _role != CrotoLinkRole.guest) {
          return;
        }
      } else if (!isPlaying && _player.playing) {
        await _player.togglePlay();
        if (_syncGeneration != currentGen || _role != CrotoLinkRole.guest) {
          return;
        }
      }
    }
  }

  /// Pista siguiente a punto de empezar: el invitado la precarga añadiéndola
  /// justo tras la actual para que el motor A/B la prepare y el cambio sea
  /// continuo. Si el host cambia de otra forma, el sync normal recarga.
  @override
  void _handleNextHint(Track next, int startAtServerMs) {
    if (_role != CrotoLinkRole.guest ||
        _session?.mode != CrotoLinkMode.synchronizedListening) {
      return;
    }
    if (_hintPreloadedTrackId == next.id) return;
    final ordered = _player.orderedQueue;
    final pos = _player.currentOrderPos;
    if (pos < 0) return;
    if (pos + 1 < ordered.length && ordered[pos + 1].id == next.id) {
      _hintPreloadedTrackId = next.id;
      return;
    }
    _hintPreloadedTrackId = next.id;
    unawaited(() async {
      var playable = next;
      try {
        final r = await _resolver.resolve(next);
        if (!r.isAvailable) return; // no existe aquí: no se precarga
        playable = r.track!;
      } catch (e) {
        debugPrint(
            'CrotoLinkController: no se pudo resolver la pista siguiente para precargarla: $e');
      }
      if (_role == CrotoLinkRole.guest) await _player.addNextInQueue(playable);
    }());
  }

  /// Pista siguiente si faltan ≤10 s para terminar la actual.
  @override
  ({Track track, int startAtLocalMs})? _nextTrackHint() {
    final duration = _player.duration;
    final current = _player.currentTrack;
    if (duration == null || current == null || !_player.playing) return null;
    final remaining = duration - _player.position;
    if (remaining <= Duration.zero || remaining > const Duration(seconds: 10)) {
      return null;
    }
    final ordered = _player.orderedQueue;
    final pos = _player.currentOrderPos;
    if (pos < 0 || pos + 1 >= ordered.length) return null;
    return (
      track: ordered[pos + 1],
      startAtLocalMs:
          DateTime.now().millisecondsSinceEpoch + remaining.inMilliseconds,
    );
  }

  @override
  Map<String, dynamic> _trackHintJson(Track t) => trackToCrotoLinkJson(t);
}
