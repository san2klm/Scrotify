part of 'player_controller.dart';

/// Temporizador de apagado: cuenta atrás, fin de pista y fundido final.
mixin _PlayerSleepTimer on _PlayerBase {
  /// True si hay un apagado automático programado.
  bool get hasSleepTimer => _sleepEndsAt != null || _sleepEndsAtEndOfTrack;

  /// True si el apagado automático está configurado para el fin de la canción actual.
  bool get isSleepTimerEndOfTrack => _sleepEndsAtEndOfTrack;

  /// Hora a la que se pausará la reproducción, o null si no hay timer de duración fija.
  DateTime? get sleepEndsAt => _sleepEndsAt;

  /// Tiempo restante para el apagado, o null si no hay timer.
  Duration? get sleepRemaining {
    if (_sleepEndsAtEndOfTrack) {
      final rem = _remainingToPlay();
      if (rem != null && !rem.isNegative) return rem;
      return null;
    }
    final end = _sleepEndsAt;
    if (end == null) return null;
    final rem = end.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

  /// Texto corto para mostrar en la UI, p. ej. "Apagar en 15 min" o "Fin de la canción".
  String get sleepLabel {
    if (!hasSleepTimer) return 'Desactivado';
    if (_sleepEndsAtEndOfTrack) {
      final rem = _remainingToPlay();
      if (rem != null && !rem.isNegative) {
        final m = rem.inMinutes;
        final s = (rem.inSeconds % 60).toString().padLeft(2, '0');
        return 'Fin de la canción ($m:$s)';
      }
      return 'Fin de la canción';
    }
    final rem = sleepRemaining;
    if (rem == null) return 'Desactivado';
    final mins = rem.inMinutes;
    if (mins < 1) return 'Apagar en menos de 1 min';
    if (mins >= 60) {
      final h = rem.inHours;
      final m = rem.inMinutes % 60;
      return m == 0 ? 'Apagar en $h h' : 'Apagar en $h h $m min';
    }
    return 'Apagar en $mins min';
  }

  /// Programa el apagado automático tras [duration]: pausa la reproducción.
  void setSleepTimer(Duration duration) {
    cancelSleepTimer(silent: true);
    _sleepEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      await _executeSleepFadeAndPause();
    });
    // Avisa a la UI para refrescar el tiempo restante.
    _sleepTicker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_sleepEndsAt == null && !_sleepEndsAtEndOfTrack) return;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Programa el apagado automático para cuando finalice la canción actual.
  void setSleepTimerEndOfTrack() {
    cancelSleepTimer(silent: true);
    _sleepEndsAtEndOfTrack = true;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_sleepEndsAtEndOfTrack) return;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _executeSleepFadeAndPause() async {
    _cancelFade();

    // Efecto Fade Out: bajar volumen gradualmente en los últimos segundos
    double startVol = _volume;
    int steps = 20;
    for (int i = 0; i < steps; i++) {
      double currentVol = _computeEffectivePlayerVolume(
        baseVolume: startVol * (1 - (i / steps)),
        crossfadeFactor: 1.0,
        gainResult: _leadGain,
      );
      await _lead.setVolume(currentVol);
      await Future.delayed(const Duration(milliseconds: 250));
    }

    try {
      if (_karaokeMode && _karaokePlayer != null) {
        await _karaokePlayer!.pause();
      } else {
        await _lead.pause();
      }
    } catch (_) {}

    // Restaurar volumen original para la próxima vez que se reproduzca algo
    final restoredVol = _computeEffectivePlayerVolume(
      baseVolume: startVol,
      crossfadeFactor: 1.0,
      gainResult: _leadGain,
    );
    await _lead.setVolume(restoredVol);
    cancelSleepTimer();
  }

  /// Cancela el apagado automático programado, si lo hay.
  @override
  void cancelSleepTimer({bool silent = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepEndsAt = null;
    _sleepEndsAtEndOfTrack = false;
    if (!silent) notifyListeners();
  }
}
