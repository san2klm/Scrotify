part of 'player_controller.dart';

/// Reproducciones cualificadas, recientes y más escuchadas (historial persistido).
mixin _PlayerStats on _PlayerBase {
  @override
  void _checkPlayQualification(Duration pos, Duration? dur,
      {bool completed = false}) {
    final track = currentTrack;
    if (track == null) return;

    if (_currentlyTrackedId != track.id) {
      _currentlyTrackedId = track.id;
      _currentTrackPlayCounted = false;
    }

    if (_currentTrackPlayCounted) return;

    final effectiveDur = dur ?? PlayerController._trackDuration(track);

    if (ListeningStatsService.qualifiesForPlayCount(
      position: pos,
      duration: effectiveDur,
      completed: completed,
    )) {
      _currentTrackPlayCounted = true;
      _recordQualifiedPlay(track, effectiveDur ?? pos);
    }
  }

  void _recordQualifiedPlay(Track track, Duration dur) {
    _statsService?.recordPlay(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      genre: track.genre,
      durationSeconds: dur.inSeconds > 0 ? dur.inSeconds : 0,
      serverScope: _currentMostPlayedSession,
    );

    // El servidor siempre recibe la escucha; la estadística local de la
    // playlist va aparte.
    unawaited(_service.scrobble(track.id));
    if (_sourcePlaylist != null) {
      _recordPlaylistPlay(_sourcePlaylist!);
    } else {
      _recordTrackPlay(track);
    }
  }

  @override
  void _resetPlayTracking() {
    _currentlyTrackedId = currentTrack?.id;
    _currentTrackPlayCounted = false;
    _reportNowPlaying();
  }

  /// "Ahora sonando" para los demás usuarios del servidor (se renueva cada
  /// ~2 min mientras suena, porque Navidrome lo hace caducar).
  void _reportNowPlaying() {
    final track = currentTrack;
    if (track == null) return;
    _lastNowPlayingAt = DateTime.now();
    unawaited(_service.reportNowPlaying(track.id));
  }

  // ---------------------------------------------------------------------------
  // Historial de escuchas recientes
  // ---------------------------------------------------------------------------
  @override
  void _recordRecent(Track track) {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 50) {
      _recentlyPlayed.removeRange(50, _recentlyPlayed.length);
    }
    _saveHistory();
  }

  String _historyFileName(String session) {
    final encoded = base64Url.encode(utf8.encode(session)).replaceAll('=', '');
    return 'recently_played_$encoded.json';
  }

  Future<void> _loadHistory() async {
    final gen = ++_historyGen;
    try {
      final dir = await getAppDataDirectory();
      final session = _mostPlayedSession;
      // Con sesión solo cuenta el archivo del perfil: el global es de otro
      // servidor o usuario y no debe mezclarse.
      final file = File(session != null
          ? '${dir.path}/${_historyFileName(session)}'
          : '${dir.path}/recently_played.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        if (gen != _historyGen) return; // cambió el perfil mientras se leía
        final list = jsonDecode(content) as List;
        _recentlyPlayed = list
            .map((j) =>
                PlayerController._trackFromJson(j as Map<String, dynamic>))
            .toList();
        notifyListeners();
      } else {
        if (gen != _historyGen) return;
        _recentlyPlayed = [];
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore — el historial es una conveniencia, no algo crítico.
    }
  }

  /// Escritura atómica (`.tmp` + rename) y en orden: una instantánea vieja
  /// nunca pisa a una nueva. El contenido se captura al llamar.
  Future<void> _saveHistory() {
    final session = _mostPlayedSession;
    final contents =
        jsonEncode(_recentlyPlayed.map(PlayerController._trackToJson).toList());
    _historyWrite = _historyWrite.catchError((Object _) {}).then((_) async {
      try {
        final dir = await getAppDataDirectory();
        final fileName = session != null
            ? _historyFileName(session)
            : 'recently_played.json';
        final file = File('${dir.path}/$fileName');
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(contents, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint(
            'PlayerController: no se pudo guardar el historial reciente: $e');
      }
    });
    return _historyWrite;
  }

  // ---------------------------------------------------------------------------
  // Contadores de reproducciones
  // ---------------------------------------------------------------------------
  String _mostPlayedKey(MostPlayedItemType type, String id) =>
      '${type.name}:$id';

  void _recordTrackPlay(Track track) {
    if (_sourcePlaylist != null) return;
    _incrementMostPlayed(MostPlayedItem.track(track));
  }

  /// Integra los contadores de Navidrome al abrir la biblioteca en este
  /// dispositivo. El máximo evita que una respuesta desactualizada reduzca una
  /// reproducción que acabamos de registrar localmente.
  void syncServerPlayCounts(Iterable<Track> tracks) {
    var changed = false;
    for (final track in tracks) {
      if (track.playCount <= 0) continue;
      final key = _mostPlayedKey(MostPlayedItemType.track, track.id);
      final previous = _mostPlayedByKey[key];
      if (previous != null && previous.playCount >= track.playCount) continue;
      _mostPlayedByKey[key] = MostPlayedItem.track(
        track,
        playCount: track.playCount,
        lastPlayedAt: previous?.lastPlayedAt,
      );
      changed = true;
    }
    if (!changed) return;
    _saveMostPlayed();
    notifyListeners();
  }

  void _recordPlaylistPlay(Playlist playlist) {
    _incrementMostPlayed(MostPlayedItem.playlist(playlist));
  }

  void _incrementMostPlayed(MostPlayedItem item) {
    final key = _mostPlayedKey(item.type, item.id);
    final previous = _mostPlayedByKey[key];
    _mostPlayedByKey[key] = item.type == MostPlayedItemType.track
        ? MostPlayedItem.track(
            item.track!,
            playCount: (previous?.playCount ?? 0) + 1,
          )
        : MostPlayedItem.playlist(
            item.playlist!,
            playCount: (previous?.playCount ?? 0) + 1,
          );
    _saveMostPlayed();
  }

  Future<void> _loadMostPlayed() async {
    final session = _mostPlayedSession;
    if (session == null) return;
    final loadGeneration = ++_mostPlayedLoadGeneration;
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/${_mostPlayedFileName(session)}');
      if (!await file.exists()) return;
      final values = jsonDecode(await file.readAsString()) as List;
      final loaded = <String, MostPlayedItem>{};
      for (final value in values) {
        final data = value as Map<String, dynamic>;
        final item = PlayerController._mostPlayedFromJson(data);
        if (item != null) {
          loaded[_mostPlayedKey(item.type, item.id)] = item;
        }
      }
      if (loadGeneration != _mostPlayedLoadGeneration ||
          session != _mostPlayedSession) {
        return;
      }
      _mostPlayedByKey
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } catch (_) {
      // Las estadísticas son locales y no deben impedir la reproducción.
    }
  }

  Future<void> _saveMostPlayed() async {
    final session = _mostPlayedSession;
    if (session == null) return;
    final values = _mostPlayedByKey.values
        .map(PlayerController._mostPlayedToJson)
        .toList();
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/${_mostPlayedFileName(session)}');
      await file.writeAsString(jsonEncode(values));
    } catch (e) {
      debugPrint('PlayerController: no se pudo guardar lo más escuchado: $e');
    }
  }

  String? get _currentMostPlayedSession {
    final url = _service.serverUrl;
    final username = _service.username;
    if (url == null || username == null) return null;
    return '$url|$username';
  }

  String _mostPlayedFileName(String session) {
    final encoded = base64Url.encode(utf8.encode(session)).replaceAll('=', '');
    return 'most_played_$encoded.json';
  }

  void _onServiceChanged() {
    final session = _currentMostPlayedSession;
    _statsService?.setServerScope(session);
    if (session == _mostPlayedSession) return;

    final oldSession = _mostPlayedSession;
    _mostPlayedSession = session;
    _mostPlayedLoadGeneration++;
    _mostPlayedByKey.clear();
    _sourcePlaylist = null;

    if (oldSession != null && session != oldSession) {
      clearQueue();
      _recentlyPlayed.clear();
    }

    if (session != null) {
      _loadMostPlayed();
      _loadHistory();
    } else {
      _loadHistory();
    }
    notifyListeners();
  }
}
