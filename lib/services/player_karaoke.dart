part of 'player_controller.dart';

/// Modo karaoke: segundo reproductor y reducción de voz.
mixin _PlayerKaraoke on _PlayerBase {
  // ---------------------------------------------------------------------------
  // Modo Karaoke & Reducción de Voz (Desktop / media_kit)
  // ---------------------------------------------------------------------------

  Future<void> _initKaraokePlayer() async {
    if (_karaokePlayer != null) return;
    final p = mk.Player(
      configuration: const mk.PlayerConfiguration(
        pitch: false,
        title: 'Scrotify Karaoke',
      ),
    );
    _karaokePlayer = p;
    _karaokePosSub = p.stream.position.listen((pos) {
      if (_karaokeMode) {
        _karaokePositionController.add(pos);
        _checkPlayQualification(pos, p.state.duration);
        notifyListeners();
      }
    });
    _karaokeDurSub = p.stream.duration.listen((dur) {
      if (_karaokeMode) {
        _karaokeDurationController.add(dur);
      }
    });
    _karaokePlaySub = p.stream.playing.listen((isPlaying) {
      if (_karaokeMode) {
        _karaokePlayerStateController.add(PlayerState(
          isPlaying,
          ProcessingState.ready,
        ));
        notifyListeners();
      }
    });
    _karaokeBufSub = p.stream.buffering.listen((isBuffering) {
      if (_karaokeMode && isBuffering) {
        _karaokePlayerStateController.add(PlayerState(
          _karaokePlayer?.state.playing ?? false,
          ProcessingState.buffering,
        ));
      }
    });
    _karaokeCompSub = p.stream.completed.listen((completed) {
      if (_karaokeMode && completed) {
        _checkPlayQualification(
          _karaokePlayer?.state.position ?? Duration.zero,
          _karaokePlayer?.state.duration,
          completed: true,
        );
        _onCompleted();
      }
    });
  }

  /// Activa o desactiva el modo Karaoke con reproductor directo con filtro mpv.
  Future<void> setKaraokeMode(bool enable) async {
    if (_karaokeMode == enable) return;
    if (enable && !PlayerController.isVocalReductionSupported) {
      // Si no es soportado, simplemente encendemos la bandera de UI sin cambiar backend.
      _karaokeMode = true;
      notifyListeners();
      return;
    }

    _cancelFade();
    final currentPos = position;
    final wasPlaying = playing;
    final currentTr = currentTrack;

    if (enable) {
      await _lead.pause();
      await _initKaraokePlayer();
      _karaokeMode = true;
      if (currentTr != null) {
        final streamUrl = _service.getPlaybackStreamUrl(currentTr.id,
            quality: _settings.effectiveQuality);
        await _applyVocalFilter(_vocalReduction);
        await _applyKaraokeVolume();
        await _karaokePlayer!.open(mk.Media(streamUrl), play: wasPlaying);
        if (currentPos > Duration.zero) {
          await _karaokePlayer!.seek(currentPos);
        }
      }
    } else {
      Duration pos = Duration.zero;
      if (_karaokePlayer != null) {
        pos = _karaokePlayer!.state.position;
        await _karaokePlayer!.pause();
      }
      _karaokeMode = false;
      _karaokeGain = null;
      if (currentTr != null) {
        await _loadTrackOn(_lead, _currentIndex);
        await _lead.seek(pos);
        if (wasPlaying) {
          unawaited(_lead.play().catchError((_) {}));
          _ensureWatchdog();
        }
      }
    }
    notifyListeners();
  }

  /// Conmuta el filtro reductor de voz (Center-Channel Vocal Removal).
  Future<void> toggleVocalReduction() async {
    _vocalReduction = !_vocalReduction;
    if (_karaokeMode && _karaokePlayer != null) {
      await _applyVocalFilter(_vocalReduction);
    }
    notifyListeners();
  }

  Future<void> _applyVocalFilter(bool enabled) async {
    if (_karaokePlayer == null || !PlayerController.isVocalReductionSupported) return;
    try {
      final platform = _karaokePlayer!.platform;
      if (platform is mk.NativePlayer) {
        if (enabled) {
          // Cadena FFmpeg lavfi optimizada y validada para mpv:
          // 1. stereotools (lr>l-r): cancela el centro estereofónico
          // 2. bandreject (1200Hz, Q=1.5): corte activo en frecuencias vocales
          // 3. equalizers: atenuación de formantes y presencia vocal
          // 4. extrastereo: refuerza los instrumentos en los laterales
          const filter = 'lavfi=[stereotools=mode=lr>l-r:slev=1.4,'
              'bandreject=f=1200:w=1.5:t=q,'
              'equalizer=f=3000:t=q:w=1.5:g=-18,'
              'equalizer=f=300:t=q:w=1.2:g=-10,'
              'extrastereo=m=1.3]';
          await platform.setProperty('af', filter);
        } else {
          await platform.setProperty('af', '');
        }
      }
    } catch (e) {
      debugPrint('Error applying vocal reduction filter: $e');
    }
  }
}
