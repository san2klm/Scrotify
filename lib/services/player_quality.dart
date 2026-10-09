part of 'player_controller.dart';

/// Alta fidelidad y calidad de transmisión: plan Hi-Fi y recarga al cambiar de calidad.
mixin _PlayerQuality on _PlayerBase {
  /// Plan de fidelidad vigente (`null` hasta que el coordinador lo calcule).
  HifiPlan? get hifiPlan => _hifiPlan;

  /// En Bit-perfect el volumen digital queda fijo al 100 %.
  bool get volumeLocked => _hifiPlan?.lockVolumeAt100 ?? false;

  /// Aplica un [HifiPlan]: origen del stream, volumen, crossfade, ReplayGain y
  /// salida nativa. Lo llama `HifiCoordinator` al cambiar el modo o la red.
  Future<void> applyHifi(HifiPlan plan) async {
    final previous = _hifiPlan;
    _hifiPlan = plan;

    // Origen del stream: el archivo original en Alta fidelidad/Bit-perfect.
    final streamBefore = _service.hifiStream?.toQuery();
    _service.hifiStream =
        plan.mode == AudioFidelityMode.standard ? null : plan.stream;
    final streamChanged =
        !mapEquals(streamBefore, _service.hifiStream?.toQuery());

    // Volumen digital fijo (y recuperación del anterior al salir).
    if (plan.lockVolumeAt100 && previous?.lockVolumeAt100 != true) {
      _volumeBeforeLock = _volume;
      _volume = 1.0;
    } else if (!plan.lockVolumeAt100 && previous?.lockVolumeAt100 == true) {
      _volume = _volumeBeforeLock ?? _volume;
      _volumeBeforeLock = null;
    }

    if (!plan.allowCrossfade && (_fading || _preloaded)) _cancelFade();
    _reapplyReplayGainToCurrentPlayers(); // vuelve a calcular volumen y ganancia

    if (plan.requestAndroidBitPerfect) {
      final track = currentTrack;
      if (track != null) unawaited(_requestHifiOutputFor(track));
    } else if (previous?.requestAndroidBitPerfect == true) {
      unawaited(HifiNative.disableAndroidBitPerfect());
    }

    // Cambió el origen del audio: recarga la pista en curso sin perder la posición.
    if (streamChanged && _currentIndex >= 0) await _reloadAtQuality();
    notifyListeners();
  }

  /// Bit-perfect (Android 14+) e iOS necesitan la frecuencia/profundidad de cada pista.
  Future<void> _requestHifiOutputFor(Track track) async {
    final plan = _hifiPlan;
    if (plan == null) return;
    if (plan.requestAndroidBitPerfect) {
      await HifiNative.enableAndroidBitPerfect(
        sampleRate: track.samplingRate ?? 44100,
        bitDepth: track.bitDepth ?? 16,
      );
    }
    final rate = track.samplingRate;
    if (plan.matchIosSampleRate && rate != null) {
      await HifiNative.setIosPreferredSampleRate(rate);
    }
  }

  void _onSettingsChanged() {
    final q = _settings.effectiveQuality;
    if (q != _lastAppliedQuality) {
      _lastAppliedQuality = q;
      unawaited(_reloadAtQuality());
    }
    // El "volumen inicial" se aplica solo si el propio ajuste cambió (evita que
    // arrastrar el slider de crossfade u otros ajustes resetee el volumen).
    if (_settings.initialVolume != _lastAppliedVolume) {
      _lastAppliedVolume = _settings.initialVolume;
      if (volumeLocked) {
        // Se recordará al salir de Bit-perfect.
        _volumeBeforeLock = _settings.initialVolume;
        return;
      }
      _volume = _settings.initialVolume;
      if (_karaokeMode && _karaokePlayer != null) {
        unawaited(_applyKaraokeVolume());
      } else if (!_fading) {
        final leadVol = _computeEffectivePlayerVolume(
          baseVolume: _volume,
          crossfadeFactor: 1.0,
          gainResult: _leadGain,
        );
        unawaited(_lead.setVolume(leadVol));
      }
    }
    final rgMode = _settings.replayGainMode;
    final rgPreamp = _settings.replayGainPreamp;
    final rgPreventClipping = _settings.replayGainPreventClipping;
    if (rgMode != _lastAppliedReplayGainMode ||
        rgPreamp != _lastAppliedReplayGainPreamp ||
        rgPreventClipping != _lastAppliedReplayGainPreventClipping) {
      _lastAppliedReplayGainMode = rgMode;
      _lastAppliedReplayGainPreamp = rgPreamp;
      _lastAppliedReplayGainPreventClipping = rgPreventClipping;
      _reapplyReplayGainToCurrentPlayers();
    }
  }

  /// Recarga la canción en curso con la calidad nueva preservando la posición
  /// y el estado de reproducción. Deja de sonar un instante (cambio de fuente).
  Future<void> _reloadAtQuality() async {
    if (_currentIndex < 0) return;
    _cancelFade();
    if (_karaokeMode && _karaokePlayer != null) {
      final t = currentTrack;
      if (t != null) {
        final pos = _karaokePlayer!.state.position;
        final wasPlaying = _karaokePlayer!.state.playing;
        final url = _service.getPlaybackStreamUrl(t.id,
            quality: _settings.effectiveQuality);
        await _applyKaraokeVolume();
        await _karaokePlayer!.open(mk.Media(url), play: wasPlaying);
        if (pos > Duration.zero) {
          await _karaokePlayer!.seek(pos);
        }
      }
      notifyListeners();
      return;
    }
    final player = _lead;
    final wasPlaying = player.playing;
    final position = player.position;
    try {
      final track = _queue[_currentIndex];
      _applyReplayGainForTrack(onPlayerA: _useA, track: track);
      await player.stop();
      await player.setAudioSource(_sourceFor(track));
      final leadVol = _computeEffectivePlayerVolume(
        baseVolume: _volume,
        crossfadeFactor: 1.0,
        gainResult: _leadGain,
      );
      await player.setVolume(leadVol);
      if (position > Duration.zero) await player.seek(position);
      if (wasPlaying) unawaited(player.play().catchError((_) {}));
    } catch (_) {
      // Si la recarga falla (p. ej. sin conexión), no matamos la sesión.
    }
    notifyListeners();
  }
}
