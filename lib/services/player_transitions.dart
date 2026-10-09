part of 'player_controller.dart';

/// Paso de una pista a otra: fin de pista, precarga, fundido cruzado y vigilancia.
mixin _PlayerTransitions on _PlayerBase {
  // ---------------------------------------------------------------------------
  // Avance de la cola
  // ---------------------------------------------------------------------------

  /// Posición (en `_order`) siguiente a [afterPos], respetando el modo repetir.
  /// `null` si no hay siguiente y no hay repetición de toda la cola.
  int? _nextOrderPos(int afterPos) {
    var n = afterPos + 1;
    if (n >= _order.length) {
      return (_repeatMode == LoopMode.all && _order.isNotEmpty) ? 0 : null;
    }
    return n;
  }

  @override
  void _onCompleted() {
    _fadeGen++; // invalida rampas/pasos pendientes
    if (_sleepEndsAtEndOfTrack) {
      _sleepEndsAtEndOfTrack = false;
      cancelSleepTimer();
      try {
        if (_karaokeMode && _karaokePlayer != null) {
          unawaited(_karaokePlayer!.pause());
        } else {
          unawaited(_lead.pause());
        }
      } catch (_) {}
      notifyListeners();
      return;
    }
    if (_repeatMode == LoopMode.one) {
      if (_karaokeMode && _karaokePlayer != null) {
        unawaited(_karaokePlayer!.seek(Duration.zero));
        unawaited(_karaokePlayer!.play());
      } else {
        unawaited(_lead.seek(Duration.zero));
        unawaited(_lead.play());
        _ensureWatchdog();
      }
      // Reload waveform for the same track (since it's repeating)
      _loadCurrentTrackWaveform();
      notifyListeners();
      return;
    }
    // Handoff: el reproductor de fundido ya estaba sonando la siguiente.
    if (_fading && _fadeTargetPos >= 0) {
      _finishHandoff();
      return;
    }
    // Avance normal (sin fundido): limpiar cualquier pre-carga a medias.
    _preloaded = false;
    _fadeTargetPos = -1;
    unawaited(_fade.stop());
    final next = _nextOrderPos(_pos);
    if (next == null) {
      notifyListeners(); // fin de cola, se queda en "completed"
      return;
    }
    _pos = next;
    if (_karaokeMode && _karaokePlayer != null) {
      final t = currentTrack;
      if (t != null) {
        final url = _service.getPlaybackStreamUrl(t.id,
            quality: _settings.effectiveQuality);
        unawaited(_applyKaraokeVolume());
        unawaited(_karaokePlayer!.open(mk.Media(url), play: true));
        _recordRecent(t);
        _resetPlayTracking();
        // Load waveform for the new track
        _loadCurrentTrackWaveform();
      }
    } else {
      unawaited(_loadCurrentAndPlay(_lead));
      _recordRecent(currentTrack!);
      _resetPlayTracking();
      // Load waveform for the new track (done inside _loadCurrentAndPlay)
    }
    _prepareNextForSkip();
    notifyListeners();
  }

  /// Cambia el rol A/B: el reproductor de fundido pasa a ser el lead (ya venía
  /// sonando la siguiente canción a todo volumen) y el viejo lead queda mudo.
  void _finishHandoff() {
    final oldLead = _lead;
    final newLead = _fade;
    final target = _fadeTargetPos;
    _fading = false;
    _preloaded = false;
    _fadeTargetPos = -1;
    _useA = !_useA;
    _pos = target;
    unawaited(oldLead.stop());
    unawaited(oldLead.setVolume(_volume));
    if (_useA) {
      _gainB = null;
    } else {
      _gainA = null;
    }
    final newLeadVol = _computeEffectivePlayerVolume(
      baseVolume: _volume,
      crossfadeFactor: 1.0,
      gainResult: _leadGain,
    );
    unawaited(newLead.setVolume(newLeadVol));
    // Si la canción entrante era más corta que el fundido, el fade pudo
    // completarse antes del handoff: reanudarla desde el principio.
    if (!newLead.playing) unawaited(newLead.play());
    _recordRecent(currentTrack!);
    _resetPlayTracking();
    _loadCurrentTrackWaveform();
    _prepareNextForSkip();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Crossfade
  // ---------------------------------------------------------------------------

  Duration? get _crossfade =>
      (_hifiPlan?.allowCrossfade ?? true) ? _settings.crossfade : null;

  @override
  void _ensureWatchdog() {
    _watchdog ??= Timer.periodic(
        const Duration(milliseconds: 200), (_) => _watchdogTick());
  }

  @override
  void _prepareNextForSkip() {
    if (_karaokeMode || _fading || _preloaded || _pos < 0) return;
    final next = _nextOrderPos(_pos);
    if (next == null || _preparedNextPos == next) return;

    final token = ++_preparedNextGen;
    _preparedNextPos = -1;
    final track = _queue[_order[next]];
    unawaited(_prepareNextOnFade(track, next, token));
  }

  Future<void> _prepareNextOnFade(Track track, int nextPos, int token) async {
    try {
      await _fade.stop();
      if (token != _preparedNextGen) return;
      _applyReplayGainForTrack(onPlayerA: !_useA, track: track);
      final prepVol = _computeEffectivePlayerVolume(
        baseVolume: _volume,
        crossfadeFactor: 1.0,
        gainResult: _fadeGain,
      );
      await _fade.setVolume(prepVol);
      await _fade.setAudioSource(_sourceFor(track));
      if (token == _preparedNextGen) {
        _preparedNextPos = nextPos;
      }
    } catch (_) {
      if (token == _preparedNextGen) _preparedNextPos = -1;
    }
  }

  Future<bool> _playPreparedNext(int nextPos) async {
    if (_preparedNextPos != nextPos || _karaokeMode) return false;

    final oldLead = _lead;
    final newLead = _fade;
    _preparedNextPos = -1;
    _preparedNextGen++;
    _fadeGen++;
    _fading = false;
    _preloaded = false;
    _fadeTargetPos = -1;
    _useA = !_useA;
    _pos = nextPos;

    try {
      await oldLead.stop();
      unawaited(oldLead.setVolume(_volume));
      if (_useA) {
        _gainB = null;
      } else {
        _gainA = null;
      }
      final newLeadVol = _computeEffectivePlayerVolume(
        baseVolume: _volume,
        crossfadeFactor: 1.0,
        gainResult: _leadGain,
      );
      await newLead.setVolume(newLeadVol);
      unawaited(newLead.play().catchError((_) {}));
      unawaited(_loadCurrentTrackWaveform());
      _prepareNextForSkip();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Duración conocida de la canción actual (dato del stream o, si aún no se
  /// cargó, los metadatos del servidor).
  @override
  Duration? _remainingToPlay() {
    final dur = _lead.duration ?? PlayerController._trackDuration(currentTrack);
    if (dur == null || dur <= Duration.zero) return null;
    final rem = dur - _lead.position;
    return rem.isNegative ? Duration.zero : rem;
  }

  void _watchdogTick() {
    // En pausa/idle no hace falta despertar la CPU cada 200 ms: tras ~5 s sin
    // reproducir ni fundido en curso el timer se detiene (se rearma al reproducir).
    if (!_lead.playing && !_fading && !_preloaded) {
      if (++_watchdogIdleTicks >= 25) {
        _watchdog?.cancel();
        _watchdog = null;
        _watchdogIdleTicks = 0;
      }
      return;
    }
    _watchdogIdleTicks = 0;
    if (_lead.playing && _pos >= 0) {
      _checkPlayQualification(_lead.position, _lead.duration);
    }
    final crossfade = _crossfade;
    final repeatOne = _repeatMode == LoopMode.one;
    // Cambios de configuración en caliente: anular un fundido/a medio preparar.
    if ((crossfade ?? Duration.zero) <= Duration.zero ||
        repeatOne ||
        _sleepEndsAtEndOfTrack) {
      if (_fading || _preloaded) _cancelFade();
      return;
    }
    if (!_lead.playing || _pos < 0) return;
    final next = _nextOrderPos(_pos);
    if (next == null) return;
    final remaining = _remainingToPlay();
    if (remaining == null) return;
    if (_fading) return;
    // Fase de pre-carga: dar a mpv margen para bufferizar la siguiente canción
    // antes de que sea audible (a volumen 0).
    if (!_preloaded && remaining <= crossfade! + PlayerController._preRoll) {
      unawaited(_preloadNext(next));
      return;
    }
    // Fase de rampa: solapamiento audible.
    if (_preloaded && remaining <= crossfade!) {
      unawaited(_beginFadeRamp(next));
      return;
    }
    // Eliminación de silencios: si ya pasamos el final útil, avanzar a la siguiente canción.
    if (_settings.silenceRemovalEnabled && _usefulEnd != null) {
      final pos = _lead.position;
      if (pos >= _usefulEnd!) {
        // Evitar saltar múltiples veces en el mismo tick
        _usefulEnd = null;
        skipNext();
        return;
      }
    }
  }

  Future<void> _preloadNext(int nextPos) async {
    final token = _fadeGen;
    // Esta preparación pasa a ser un crossfade audible, por lo que sustituye
    // la fuente silenciosa que se había reservado para el botón siguiente.
    _preparedNextGen++;
    _preparedNextPos = -1;
    _preloaded = true;
    _fadeTargetPos = nextPos;
    final track = _queue[_order[nextPos]];
    try {
      await _fade.stop();
      if (token != _fadeGen) return;
      _applyReplayGainForTrack(onPlayerA: !_useA, track: track);
      await _fade.setVolume(0);
      await _fade.setAudioSource(_sourceFor(track));
      unawaited(_fade.play().catchError((_) {}));
      if (token != _fadeGen) return; // cancelado durante la carga
    } catch (_) {
      // Carga fallida (offline...): reintentar más tarde.
      if (token == _fadeGen) {
        _preloaded = false;
        _fadeTargetPos = -1;
      }
    }
  }

  Future<void> _beginFadeRamp(int nextPos) async {
    final crossfade = _crossfade;
    if (crossfade == null || crossfade <= Duration.zero) return;
    final token = ++_fadeGen;
    _fading = true;
    final lead = _lead;
    final other = _fade;
    final remaining = _remainingToPlay();
    var fadeDur = crossfade;
    if (remaining != null && remaining < crossfade) fadeDur = remaining;
    if (fadeDur < const Duration(milliseconds: 50)) return;

    try {
      // Cobertura: si la pre-carga no llegó a hacerse, cargar ahora.
      if (!_preloaded) {
        await other.stop();
        _applyReplayGainForTrack(
            onPlayerA: !_useA, track: _queue[_order[nextPos]]);
        await other.setAudioSource(_sourceFor(_queue[_order[nextPos]]));
        unawaited(other.play().catchError((_) {}));
      }
      if (token != _fadeGen) return;
      final steps = (fadeDur.inMilliseconds / 50).round().clamp(1, 2000);
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (token != _fadeGen || !_fading) return;
        final pct = i / steps;
        final leadVol = _computeEffectivePlayerVolume(
          baseVolume: _volume,
          crossfadeFactor: 1.0 - pct,
          gainResult: _leadGain,
        );
        final otherVol = _computeEffectivePlayerVolume(
          baseVolume: _volume,
          crossfadeFactor: pct,
          gainResult: _fadeGain,
        );
        unawaited(lead.setVolume(leadVol));
        unawaited(other.setVolume(otherVol));
      }
    } catch (_) {
      // Si el fundido falla, volver al corte seco (el completed hará el avance).
      if (token == _fadeGen) _cancelFade();
    }
  }

  /// Cancela cualquier fundido/pre-carga en curso y restaura el volumen.
  @override
  void _cancelFade() {
    _fadeGen++;
    _preparedNextGen++;
    _preparedNextPos = -1;
    _fading = false;
    _preloaded = false;
    _fadeTargetPos = -1;
    unawaited(_fade.stop());
    if (_useA) {
      _gainB = null;
    } else {
      _gainA = null;
    }
    final leadVol = _computeEffectivePlayerVolume(
      baseVolume: _volume,
      crossfadeFactor: 1.0,
      gainResult: _leadGain,
    );
    unawaited(_lead.setVolume(leadVol));
  }
}
