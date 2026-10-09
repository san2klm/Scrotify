part of 'player_controller.dart';

/// ReplayGain y volumen efectivo de cada reproductor (pista actual, fundido, karaoke).
mixin _PlayerGain on _PlayerBase {
  /// Resultado efectivo de ReplayGain para la canción en reproducción audible.
  ReplayGainResult? get currentReplayGain {
    if (_karaokeMode && _karaokePlayer != null) {
      if (currentTrack == null) return null;
      return _karaokeGain ?? _computeTrackReplayGain(currentTrack);
    }
    return _leadGain;
  }

  @override
  ReplayGainResult? get _leadGain => _useA ? _gainA : _gainB;

  @override
  ReplayGainResult? get _fadeGain => _useA ? _gainB : _gainA;

  ReplayGainResult _computeTrackReplayGain(Track? track) {
    return computeReplayGain(
      replayGain: track?.replayGain,
      // Bit-perfect: ningún procesamiento de volumen.
      mode: (_hifiPlan?.allowReplayGain ?? true)
          ? _settings.replayGainMode
          : ReplayGainMode.off,
      preampDb: _settings.replayGainPreamp,
      preventClipping: _settings.replayGainPreventClipping,
    );
  }

  @override
  void _applyReplayGainForTrack({
    required bool onPlayerA,
    required Track? track,
  }) {
    // Calculador puro de ReplayGain:
    // Puesto que el volumen de just_audio está acotado en [0.0, 1.0], no se fuerza un boost
    // arbitrario en hardware/DSP sin soporte multiplataforma. Solo se aplica atenuación
    // (dB <= 0, multiplier <= 1.0) y cualquier ganancia positiva se marca de forma transparente.
    // El volumen del usuario _volume permanece intacto.
    final res = _computeTrackReplayGain(track);
    if (onPlayerA) {
      _gainA = res;
    } else {
      _gainB = res;
    }
  }

  /// Calcula el volumen efectivo para el AudioPlayer.
  /// _volume del usuario se mantiene intacto; cada llamada a setVolume usa
  /// (baseVolume * crossfadeFactor * calculated multiplier).
  /// En el backend just_audio, ReplayGain es attenuation-only (dB <= 0, multiplier <= 1.0).
  @override
  double _computeEffectivePlayerVolume({
    required double baseVolume,
    required double crossfadeFactor,
    required ReplayGainResult? gainResult,
  }) {
    final mult = gainResult?.multiplier ?? 1.0;
    return (baseVolume * crossfadeFactor * mult).clamp(0.0, 1.0);
  }

  double _computeEffectiveKaraokeVolume({
    required double baseVolume,
    required ReplayGainResult? gainResult,
  }) =>
      PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: baseVolume,
        gainResult: gainResult,
      );

  @override
  Future<void> _applyKaraokeVolume() async {
    if (_karaokePlayer == null) return;
    try {
      final track = currentTrack;
      final gain = track != null ? _computeTrackReplayGain(track) : null;
      _karaokeGain = gain;
      final targetVol = _computeEffectiveKaraokeVolume(
        baseVolume: _volume,
        gainResult: gain,
      );
      await _karaokePlayer!.setVolume(targetVol);
    } catch (e) {
      debugPrint('Error applying karaoke volume / ReplayGain: $e');
    }
  }

  @override
  void _reapplyReplayGainToCurrentPlayers() {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _applyReplayGainForTrack(onPlayerA: _useA, track: currentTrack);
      if (!_fading) {
        final leadVol = _computeEffectivePlayerVolume(
          baseVolume: _volume,
          crossfadeFactor: 1.0,
          gainResult: _leadGain,
        );
        unawaited(_lead.setVolume(leadVol));
      }
    }
    if (_karaokeMode && _karaokePlayer != null) {
      unawaited(_applyKaraokeVolume());
    }
    if (_preparedNextPos >= 0 && _preparedNextPos < _order.length) {
      final nextTrack = _queue[_order[_preparedNextPos]];
      _applyReplayGainForTrack(onPlayerA: !_useA, track: nextTrack);
      if (!_fading) {
        final prepVol = _computeEffectivePlayerVolume(
          baseVolume: _volume,
          crossfadeFactor: 1.0,
          gainResult: _fadeGain,
        );
        unawaited(_fade.setVolume(prepVol));
      }
    }
    notifyListeners();
  }
}
