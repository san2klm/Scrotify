part of 'player_controller.dart';

/// Cola: reproducir, añadir, quitar, reordenar, aleatorio y repetición.
mixin _PlayerQueue on _PlayerBase {
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    Playlist? sourcePlaylist,
  }) async {
    if (tracks.isEmpty) return;
    if (_mirror) {
      _remote!.playQueue(tracks, startIndex);
      return;
    }
    _cancelFade();
    _sourcePlaylist = sourcePlaylist;
    _queue = List.of(tracks);
    final n = tracks.length;
    _order = List.generate(n, (i) => i);
    final start = startIndex < n ? startIndex : n - 1;
    _pos = start;
    if (_shuffleEnabled) {
      _order = _randomOrderKeeping(start, n);
    }
    if (!await _startCurrentTrack()) return;
    notifyListeners();
  }

  /// Carga y reproduce la pista actual desde `playQueue`/`add*`.
  ///
  /// Devuelve `false` si falló la carga (p. ej. sin red) o si otra petición la
  /// reemplazó mientras tanto; en ambos casos la cola queda consistente y la UI
  /// se refresca, en vez de quedar a medias sin `notifyListeners`.
  Future<bool> _startCurrentTrack() async {
    final gen = ++_loadGen;
    try {
      await _loadTrackOn(_lead, _currentIndex);
    } catch (e) {
      debugPrint('PlayerController: no se pudo cargar la pista: $e');
      if (gen == _loadGen) notifyListeners();
      return false;
    }
    if (gen != _loadGen) return false;
    unawaited(_lead.play().catchError((_) {}));
    _recordRecent(currentTrack!);
    _resetPlayTracking();
    unawaited(_loadCurrentTrackWaveform());
    _prepareNextForSkip();
    _ensureWatchdog();
    return true;
  }

  /// Inicia una cola con un tema inicial elegido al azar y deja activo el
  /// orden aleatorio. Así el botón "shuffle" no cae siempre en la primera
  /// canción de una playlist.
  Future<void> playShuffledQueue(
    List<Track> tracks, {
    Playlist? sourcePlaylist,
  }) async {
    if (tracks.isEmpty) return;
    if (_mirror) {
      _remote!.playQueue(tracks, _rand.nextInt(tracks.length), shuffle: true);
      return;
    }
    _shuffleEnabled = true;
    await playQueue(
      tracks,
      startIndex: _rand.nextInt(tracks.length),
      sourcePlaylist: sourcePlaylist,
    );
  }

  /// Añade una pista al final de la cola de reproducción.
  /// Si no hay nada reproduciéndose, empieza a reproducirla.
  Future<void> addToQueue(Track track) => addAllToQueue([track]);

  /// Añade varias pistas, en orden, al final de la cola. Si no hay nada
  /// reproduciéndose, empieza por la primera.
  Future<void> addAllToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_mirror) {
      for (final track in tracks) {
        _remote!.addToQueue(track);
      }
      return;
    }
    for (final track in tracks) {
      _queue.add(track);
      _order.add(_queue.length - 1);
    }
    if (_pos == -1) {
      _pos = 0;
      if (!await _startCurrentTrack()) return;
    } else {
      // Si la cola estaba en su última pista, la añadida pasa a ser la siguiente.
      _cancelFade();
      _prepareNextForSkip();
    }
    notifyListeners();
  }

  /// Inserta una pista para sonar a continuación de la canción actual.
  Future<void> addNextInQueue(Track track) async {
    if (_mirror) return _remote!.addNext(track);
    _queue.add(track);
    final newRealIndex = _queue.length - 1;
    if (_pos >= 0 && _pos < _order.length) {
      _order.insert(_pos + 1, newRealIndex);
      // La siguiente pista cambió: descartar la que estaba precargada.
      _cancelFade();
      _prepareNextForSkip();
    } else {
      _order.add(newRealIndex);
    }
    if (_pos == -1) {
      _pos = 0;
      if (!await _startCurrentTrack()) return;
    }
    notifyListeners();
  }

  /// Elimina una pista de la cola en la posición del orden dado.
  void removeFromQueue(int orderIndex) {
    if (_mirror) return _remote!.removeFromQueue(orderIndex);
    if (orderIndex < 0 || orderIndex >= _order.length) return;
    if (orderIndex == _pos) return; // No eliminar la canción que está sonando
    final realIndex = _order.removeAt(orderIndex);
    // Compactar `_queue`: si no, el aleatorio resucitaría pistas quitadas.
    _queue.removeAt(realIndex);
    for (var i = 0; i < _order.length; i++) {
      if (_order[i] > realIndex) _order[i]--;
    }
    if (orderIndex < _pos) {
      _pos--;
    }
    // También invalida la pista preparada: al modificar la cola podría haber
    // dejado de ser la siguiente.
    _cancelFade();
    _prepareNextForSkip();
    notifyListeners();
  }

  /// Reordena las pistas pendientes de la cola.
  void reorderQueue(int oldOrderIndex, int newOrderIndex) {
    if (_mirror) return _remote!.reorderQueue(oldOrderIndex, newOrderIndex);
    if (oldOrderIndex < 0 || oldOrderIndex >= _order.length) return;
    if (newOrderIndex < 0 || newOrderIndex >= _order.length) return;
    if (oldOrderIndex == newOrderIndex) return;

    final item = _order.removeAt(oldOrderIndex);
    _order.insert(newOrderIndex, item);

    if (_pos == oldOrderIndex) {
      _pos = newOrderIndex;
    } else if (oldOrderIndex < _pos && newOrderIndex >= _pos) {
      _pos--;
    } else if (oldOrderIndex > _pos && newOrderIndex <= _pos) {
      _pos++;
    }

    _cancelFade();
    _prepareNextForSkip();
    notifyListeners();
  }

  /// Limpia la cola y detiene la reproducción.
  @override
  void clearQueue() {
    if (_mirror) return _remote!.clearQueue();
    _cancelFade();
    _queue.clear();
    _order.clear();
    _pos = -1;
    _sourcePlaylist = null;
    _lead.stop();
    if (_karaokePlayer != null) {
      unawaited(_karaokePlayer!.pause());
    }
    _waveformData = null;
    _isWaveformLoading = false;
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    if (_mirror) return _remote!.toggleShuffle();
    _shuffleEnabled = !_shuffleEnabled;
    final n = _queue.length;
    if (n == 0) return;
    if (_shuffleEnabled) {
      final keep = _currentIndex;
      _order = _randomOrderKeeping(keep, n);
      // La pista actual queda en la posición `keep` del nuevo orden.
      if (keep >= 0) _pos = keep;
    } else {
      _pos = _currentIndex;
      _order = List.generate(n, (i) => i);
    }
    _cancelFade();
    _prepareNextForSkip();
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    if (_mirror) return _remote!.toggleRepeat();
    _repeatMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    // Repetir-uno no admite crossfade: anular uno que hubiera en curso.
    if (_repeatMode == LoopMode.one) _cancelFade();
    notifyListeners();
  }
}
