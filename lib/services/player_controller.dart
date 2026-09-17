import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';
import 'settings_controller.dart';

enum MostPlayedItemType { track, playlist }

/// Un contenido reproducido desde Scrotify. Las playlists y las canciones se
/// registran por separado para que escuchar una playlist no infle el contador
/// de cada una de sus canciones.
class MostPlayedItem {
  final MostPlayedItemType type;
  final String id;
  final int playCount;
  final DateTime lastPlayedAt;
  final Track? track;
  final Playlist? playlist;

  const MostPlayedItem._({
    required this.type,
    required this.id,
    required this.playCount,
    required this.lastPlayedAt,
    this.track,
    this.playlist,
  });

  factory MostPlayedItem.track(
    Track track, {
    int playCount = 1,
    DateTime? lastPlayedAt,
  }) =>
      MostPlayedItem._(
        type: MostPlayedItemType.track,
        id: track.id,
        playCount: playCount,
        lastPlayedAt: lastPlayedAt ?? DateTime.now(),
        track: track,
      );

  factory MostPlayedItem.playlist(
    Playlist playlist, {
    int playCount = 1,
    DateTime? lastPlayedAt,
  }) =>
      MostPlayedItem._(
        type: MostPlayedItemType.playlist,
        id: playlist.id,
        playCount: playCount,
        lastPlayedAt: lastPlayedAt ?? DateTime.now(),
        playlist: playlist,
      );
}

/// Estado global de reproducción. Persiste entre pantallas y alimenta el
/// panel de control persistente (barra inferior).
///
/// El audio se reproduce con dos [AudioPlayer] A/B (`_a`/`_b`): uno conduce
/// ("lead") y es el que alimenta los streams que ve la UI; el otro queda
/// dormido hasta que hace falta un crossfade. Para fundir con solapamiento,
/// antes de que la canción actual termine, el reproductor secundario ("fade")
/// empieza a sonar la siguiente a volumen 0 y se cruzan los volúmenes: el lead
/// baja de `_volume` → 0 mientras el fade sube 0 → `_volume`. Al completarse la
/// canción actual se rota el rol (`_useA = !_useA`) y el fade pasa a ser el lead.
///
/// just_audio 0.9.x no trae `CrossfadeAudioSource`, así que el avance de la
/// cola es manual: `_order` es el orden de reproducción (índices de `_queue`,
/// barajados si el shuffle está activo) y `_pos` la posición en ese orden.
class PlayerController extends ChangeNotifier {
  final NavidromeService _service;
  final SettingsController _settings;

  // Última calidad efectiva aplicada, para recargar la canción en curso solo
  // cuando la calidad realmente cambió (p. ej. al pasar de WiFi a móvil).
  AudioQuality _lastAppliedQuality = AudioQuality.lossless;
  // Último "volumen inicial" aplicado; evita re-aplicarlo en cada cambio de
  // ajustes (lo que rompería la rampa del crossfade y el volumen manual).
  double _lastAppliedVolume = 0.7;

  final AudioPlayer _a = AudioPlayer();
  final AudioPlayer _b = AudioPlayer();
  bool _useA = true;

  // --- Modo Karaoke / Eliminación de voz (solo Desktop via media_kit) ---
  mk.Player? _karaokePlayer;
  StreamSubscription? _karaokePosSub;
  StreamSubscription? _karaokeDurSub;
  StreamSubscription? _karaokePlaySub;
  StreamSubscription? _karaokeBufSub;
  StreamSubscription? _karaokeCompSub;
  bool _karaokeMode = false;
  bool _vocalReduction = true;
  final StreamController<Duration> _karaokePositionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _karaokeDurationController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _karaokePlayerStateController =
      StreamController<PlayerState>.broadcast();

  /// Indica si la plataforma actual soporta el filtro de reducción de voz (Linux/Windows/macOS).
  static bool get isVocalReductionSupported {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  }

  /// True si el modo Karaoke con reproductor directo está activo.
  bool get karaokeMode => _karaokeMode;

  /// True si el filtro reductor de voz está activo.
  bool get vocalReduction => _vocalReduction;

  /// Reproductor audible en este momento; sus streams son los públicos.
  AudioPlayer get _lead => _useA ? _a : _b;

  /// Reproductor de reserva, usado para el fundido entrante.
  AudioPlayer get _fade => _useA ? _b : _a;

  // Cola de reproducción (índices reales sobre `_queue`).
  List<Track> _queue = [];
  List<int> _order = [];
  int _pos = -1;

  // Historial de escuchas recientes (más reciente primero), persistido y con
  // un máximo de 50 entradas para no crecer indefinidamente.
  List<Track> _recentlyPlayed = [];

  // Reproducciones acumuladas de canciones sueltas y playlists. Se guardan
  // como entradas independientes para que una reproducción de playlist no
  // cuente también como reproducción individual de cada canción.
  final Map<String, MostPlayedItem> _mostPlayedByKey = {};
  Playlist? _sourcePlaylist;
  String? _mostPlayedSession;
  int _mostPlayedLoadGeneration = 0;

  bool _shuffleEnabled = false;
  LoopMode _repeatMode = LoopMode.off;

  /// Volumen nominal del usuario (nivel objetivo de la rampa del crossfade).
  double _volume = 0.7;

  // --- Estado del crossfade ---
  final Random _rand = Random();
  Timer? _watchdog;
  int _fadeGen = 0; // token: cada cancelación/cambio de objetivo lo invalida
  bool _preloaded = false;
  bool _fading = false;
  int _fadeTargetPos = -1;
  // La siguiente pista se prepara aunque el crossfade esté desactivado. Así el
  // botón «siguiente» puede cambiar de reproductor sin volver a abrir el
  // stream desde cero.
  int _preparedNextPos = -1;
  int _preparedNextGen = 0;
  static const Duration _preRoll = Duration(seconds: 3);

  // --- Apagado automático (sleep timer) ---
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepEndsAt;

  /// True si hay un apagado automático programado.
  bool get hasSleepTimer => _sleepEndsAt != null;

  /// Hora a la que se pausará la reproducción, o null si no hay timer.
  DateTime? get sleepEndsAt => _sleepEndsAt;

  /// Tiempo restante para el apagado, o null si no hay timer.
  Duration? get sleepRemaining {
    final end = _sleepEndsAt;
    if (end == null) return null;
    final rem = end.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

  /// Texto corto para mostrar en la UI, p. ej. "Apagar en 15 min".
  String get sleepLabel {
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
      _cancelFade();
      try {
        await _lead.pause();
      } catch (_) {}
      cancelSleepTimer();
    });
    // Avisa a la UI para refrescar el tiempo restante.
    _sleepTicker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_sleepEndsAt == null) return;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Cancela el apagado automático programado, si lo hay.
  void cancelSleepTimer({bool silent = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepEndsAt = null;
    if (!silent) notifyListeners();
  }

  List<Track> get queue => List.unmodifiable(_queue);
  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);
  List<MostPlayedItem> get mostPlayed {
    final items = _mostPlayedByKey.values.toList();
    items.sort((a, b) {
      final byCount = b.playCount.compareTo(a.playCount);
      return byCount != 0 ? byCount : b.lastPlayedAt.compareTo(a.lastPlayedAt);
    });
    return List.unmodifiable(items);
  }

  int get currentOrderPos => _pos;
  List<int> get order => List.unmodifiable(_order);
  List<Track> get orderedQueue => [
        for (final idx in _order)
          if (idx >= 0 && idx < _queue.length) _queue[idx]
      ];

  int get _currentIndex =>
      _pos >= 0 && _pos < _order.length ? _order[_pos] : -1;

  Track? get currentTrack => _currentIndex >= 0 ? _queue[_currentIndex] : null;
  bool get hasTrack => currentTrack != null;

  Stream<PlayerState> get playerStateStream => _karaokeMode
      ? _karaokePlayerStateController.stream
      : _lead.playerStateStream;
  Stream<Duration> get positionStream =>
      _karaokeMode ? _karaokePositionController.stream : _lead.positionStream;
  Stream<Duration?> get durationStream =>
      _karaokeMode ? _karaokeDurationController.stream : _lead.durationStream;
  Stream<double> get volumeStream => _lead.volumeStream;

  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get repeatMode => _repeatMode;
  bool get playing =>
      _karaokeMode ? (_karaokePlayer?.state.playing ?? false) : _lead.playing;
  Duration get position => _karaokeMode
      ? (_karaokePlayer?.state.position ?? Duration.zero)
      : _lead.position;
  Duration? get duration =>
      _karaokeMode ? _karaokePlayer?.state.duration : _lead.duration;
  double get volume => _volume;
  bool get gapless => _settings.gapless;

  PlayerController(this._service, this._settings) {
    _listenPlayers();
    _loadHistory();
    _service.addListener(_onServiceChanged);
    _onServiceChanged();
    _lastAppliedQuality = _settings.effectiveQuality;
    _volume = _settings.initialVolume;
    _lastAppliedVolume = _settings.initialVolume;
    _settings.addListener(_onSettingsChanged);
  }

  void _listenPlayers() {
    _a.playerStateStream.listen((s) => _onPlayerState(_a, s));
    _b.playerStateStream.listen((s) => _onPlayerState(_b, s));
  }

  void _onPlayerState(AudioPlayer p, PlayerState state) {
    // Solo el lead alimenta la UI; el reproductor de fundido se gestiona aparte.
    if (!identical(p, _lead)) return;
    notifyListeners();
    if (state.processingState == ProcessingState.completed) {
      _onCompleted();
    }
  }

  // ---------------------------------------------------------------------------
  // Historial de escuchas recientes
  // ---------------------------------------------------------------------------
  void _recordRecent(Track track) {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 50) {
      _recentlyPlayed.removeRange(50, _recentlyPlayed.length);
    }
    _saveHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/recently_played.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        _recentlyPlayed =
            list.map((j) => _trackFromJson(j as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore — el historial es una conveniencia, no algo crítico.
    }
  }

  Future<void> _saveHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/recently_played.json');
      await file.writeAsString(
          jsonEncode(_recentlyPlayed.map(_trackToJson).toList()));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Contadores de reproducciones
  // ---------------------------------------------------------------------------
  String _mostPlayedKey(MostPlayedItemType type, String id) =>
      '${type.name}:$id';

  void _recordTrackPlay(Track track) {
    if (_sourcePlaylist != null) return;
    _incrementMostPlayed(MostPlayedItem.track(track));
    unawaited(_service.scrobble(track.id));
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
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_mostPlayedFileName(session)}');
      if (!await file.exists()) return;
      final values = jsonDecode(await file.readAsString()) as List;
      final loaded = <String, MostPlayedItem>{};
      for (final value in values) {
        final data = value as Map<String, dynamic>;
        final item = _mostPlayedFromJson(data);
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
    final values = _mostPlayedByKey.values.map(_mostPlayedToJson).toList();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_mostPlayedFileName(session)}');
      await file.writeAsString(jsonEncode(values));
    } catch (_) {}
  }

  String? get _currentMostPlayedSession {
    final url = _service.serverUrl;
    final username = _service.username;
    if (!_service.connected || url == null || username == null) return null;
    return '$url|$username';
  }

  String _mostPlayedFileName(String session) {
    final encoded = base64Url.encode(utf8.encode(session)).replaceAll('=', '');
    return 'most_played_$encoded.json';
  }

  void _onServiceChanged() {
    final session = _currentMostPlayedSession;
    if (session == _mostPlayedSession) return;

    _mostPlayedSession = session;
    _mostPlayedLoadGeneration++;
    _mostPlayedByKey.clear();
    _sourcePlaylist = null;
    if (session != null) {
      _loadMostPlayed();
    }
    notifyListeners();
  }

  static Map<String, dynamic> _mostPlayedToJson(MostPlayedItem item) => {
        'type': item.type.name,
        'id': item.id,
        'playCount': item.playCount,
        'lastPlayedAt': item.lastPlayedAt.toIso8601String(),
        if (item.track != null) 'track': _trackToJson(item.track!),
        if (item.playlist != null)
          'playlist': {
            'id': item.playlist!.id,
            'name': item.playlist!.name,
            'coverArtUrl': item.playlist!.coverArtUrl,
            'songCount': item.playlist!.songCount,
            'duration': item.playlist!.duration,
          },
      };

  static MostPlayedItem? _mostPlayedFromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) return null;
    final count = (json['playCount'] as num?)?.toInt() ?? 0;
    final lastPlayedAt =
        DateTime.tryParse(json['lastPlayedAt'] as String? ?? '');
    if (count <= 0 || lastPlayedAt == null) return null;

    if (type == MostPlayedItemType.track.name && json['track'] is Map) {
      return MostPlayedItem.track(
        _trackFromJson(Map<String, dynamic>.from(json['track'] as Map)),
        playCount: count,
        lastPlayedAt: lastPlayedAt,
      );
    }
    if (type == MostPlayedItemType.playlist.name && json['playlist'] is Map) {
      final playlist = Map<String, dynamic>.from(json['playlist'] as Map);
      return MostPlayedItem.playlist(
        Playlist(
          id: playlist['id'] as String? ?? id,
          name: playlist['name'] as String? ?? 'Playlist',
          coverArtUrl: playlist['coverArtUrl'] as String?,
          songCount: (playlist['songCount'] as num?)?.toInt() ?? 0,
          duration: (playlist['duration'] as num?)?.toInt() ?? 0,
        ),
        playCount: count,
        lastPlayedAt: lastPlayedAt,
      );
    }
    return null;
  }

  static Map<String, dynamic> _trackToJson(Track t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'duration': t.duration,
        'albumArtUrl': t.albumArtUrl,
        'playCount': t.playCount,
      };

  static Track _trackFromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? 'Unknown',
        artist: (j['artist'] as String?) ?? 'Unknown',
        album: (j['album'] as String?) ?? 'Unknown',
        duration: (j['duration'] as String?) ?? '',
        albumArtUrl: j['albumArtUrl'] as String?,
        playCount: (j['playCount'] as num?)?.toInt() ?? 0,
      );

  // ---------------------------------------------------------------------------
  // Carga de fuentes
  // ---------------------------------------------------------------------------

  AudioSource _sourceFor(Track t) => AudioSource.uri(Uri.parse(
      _service.getStreamUrl(t.id, quality: _settings.effectiveQuality)));

  Future<void> _loadTrackOn(AudioPlayer p, int realIndex) async {
    // setAudioSource reemplaza la fuente actual y detiene la anterior. Evitar
    // el stop explícito elimina una espera antes de empezar el buffer nuevo.
    await p.setAudioSource(_sourceFor(_queue[realIndex]));
  }

  Future<void> _loadCurrentAndPlay(AudioPlayer p) async {
    try {
      await _loadTrackOn(p, _currentIndex);
      await p.play();
    } catch (_) {
      // Si la carga falla (p. ej. sin conexión), no se mata la sesión.
    }
  }

  // ---------------------------------------------------------------------------
  // Orden de reproducción (shuffle)
  // ---------------------------------------------------------------------------

  /// Orden aleatorio de `n` elementos que mantiene el índice [keepIndex] en su
  /// posición natural (la canción tocada sigue siendo la actual).
  List<int> _randomOrderKeeping(int keepIndex, int n) {
    final rest = <int>[
      for (var i = 0; i < n; i++)
        if (i != keepIndex) i
    ]..shuffle(_rand);
    rest.insert(keepIndex, keepIndex);
    return rest;
  }

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    Playlist? sourcePlaylist,
  }) async {
    if (tracks.isEmpty) return;
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
    await _loadTrackOn(_lead, _currentIndex);
    await _lead.setVolume(_volume);
    await _lead.play();
    _recordRecent(currentTrack!);
    if (sourcePlaylist != null) {
      _recordPlaylistPlay(sourcePlaylist);
    } else {
      _recordTrackPlay(currentTrack!);
    }
    _prepareNextForSkip();
    _ensureWatchdog();
    notifyListeners();
  }

  /// Inicia una cola con un tema inicial elegido al azar y deja activo el
  /// orden aleatorio. Así el botón "shuffle" no cae siempre en la primera
  /// canción de una playlist.
  Future<void> playShuffledQueue(
    List<Track> tracks, {
    Playlist? sourcePlaylist,
  }) async {
    if (tracks.isEmpty) return;
    _shuffleEnabled = true;
    await playQueue(
      tracks,
      startIndex: _rand.nextInt(tracks.length),
      sourcePlaylist: sourcePlaylist,
    );
  }

  /// Añade una pista al final de la cola de reproducción.
  /// Si no hay nada reproduciéndose, empieza a reproducirla.
  Future<void> addToQueue(Track track) async {
    _queue.add(track);
    final newRealIndex = _queue.length - 1;
    _order.add(newRealIndex);
    if (_pos == -1) {
      _pos = 0;
      await _loadTrackOn(_lead, _currentIndex);
      await _lead.setVolume(_volume);
      await _lead.play();
      _recordRecent(currentTrack!);
      _recordTrackPlay(currentTrack!);
      _prepareNextForSkip();
      _ensureWatchdog();
    }
    notifyListeners();
  }

  /// Inserta una pista para sonar a continuación de la canción actual.
  Future<void> addNextInQueue(Track track) async {
    _queue.add(track);
    final newRealIndex = _queue.length - 1;
    if (_pos >= 0 && _pos < _order.length) {
      _order.insert(_pos + 1, newRealIndex);
    } else {
      _order.add(newRealIndex);
    }
    if (_pos == -1) {
      _pos = 0;
      await _loadTrackOn(_lead, _currentIndex);
      await _lead.setVolume(_volume);
      await _lead.play();
      _recordRecent(currentTrack!);
      _recordTrackPlay(currentTrack!);
      _prepareNextForSkip();
      _ensureWatchdog();
    }
    notifyListeners();
  }

  /// Elimina una pista de la cola en la posición del orden dado.
  void removeFromQueue(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _order.length) return;
    if (orderIndex == _pos) return; // No eliminar la canción que está sonando
    _order.removeAt(orderIndex);
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
  void clearQueue() {
    _cancelFade();
    _queue.clear();
    _order.clear();
    _pos = -1;
    _sourcePlaylist = null;
    _lead.stop();
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    final n = _queue.length;
    if (n == 0) return;
    if (_shuffleEnabled) {
      _order = _randomOrderKeeping(_currentIndex, n);
    } else {
      _pos = _currentIndex;
      _order = List.generate(n, (i) => i);
    }
    _cancelFade();
    _prepareNextForSkip();
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    _repeatMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    // Repetir-uno no admite crossfade: anular uno que hubiera en curso.
    if (_repeatMode == LoopMode.one) _cancelFade();
    notifyListeners();
  }

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

  void _onCompleted() {
    _fadeGen++; // invalida rampas/pasos pendientes
    if (_repeatMode == LoopMode.one) {
      if (_karaokeMode && _karaokePlayer != null) {
        unawaited(_karaokePlayer!.seek(Duration.zero));
        unawaited(_karaokePlayer!.play());
      } else {
        unawaited(_lead.seek(Duration.zero));
        unawaited(_lead.play());
      }
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
        final url =
            _service.getStreamUrl(t.id, quality: _settings.effectiveQuality);
        unawaited(_karaokePlayer!.open(mk.Media(url), play: true));
        _recordRecent(t);
        _recordTrackPlay(t);
      }
    } else {
      unawaited(_loadCurrentAndPlay(_lead));
      _recordRecent(currentTrack!);
      _recordTrackPlay(currentTrack!);
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
    unawaited(newLead.setVolume(_volume));
    // Si la canción entrante era más corta que el fundido, el fade pudo
    // completarse antes del handoff: reanudarla desde el principio.
    if (!newLead.playing) unawaited(newLead.play());
    _recordRecent(currentTrack!);
    _recordTrackPlay(currentTrack!);
    _prepareNextForSkip();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Crossfade
  // ---------------------------------------------------------------------------

  Duration? get _crossfade => _settings.crossfade;

  void _ensureWatchdog() {
    _watchdog ??= Timer.periodic(
        const Duration(milliseconds: 200), (_) => _watchdogTick());
  }

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
      await _fade.setVolume(_volume);
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
      await newLead.setVolume(_volume);
      await newLead.play();
      _prepareNextForSkip();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Duración conocida de la canción actual (dato del stream o, si aún no se
  /// cargó, los metadatos del servidor).
  Duration? _remainingToPlay() {
    final dur = _lead.duration ?? _trackDuration(currentTrack);
    if (dur == null || dur <= Duration.zero) return null;
    final rem = dur - _lead.position;
    return rem.isNegative ? Duration.zero : rem;
  }

  static Duration? _trackDuration(Track? t) {
    final s = int.tryParse(t?.duration ?? '');
    return s == null ? null : Duration(seconds: s);
  }

  void _watchdogTick() {
    final crossfade = _crossfade;
    final repeatOne = _repeatMode == LoopMode.one;
    // Cambios de configuración en caliente: anular un fundido/a medio preparar.
    if ((crossfade ?? Duration.zero) <= Duration.zero || repeatOne) {
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
    if (!_preloaded && remaining <= crossfade! + _preRoll) {
      unawaited(_preloadNext(next));
      return;
    }
    // Fase de rampa: solapamiento audible.
    if (_preloaded && remaining <= crossfade!) {
      unawaited(_beginFadeRamp(next));
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
      await _fade.setVolume(0);
      await _fade.setAudioSource(_sourceFor(track));
      await _fade.play();
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
        await other.setAudioSource(_sourceFor(_queue[_order[nextPos]]));
        await other.play();
      }
      if (token != _fadeGen) return;
      final steps = (fadeDur.inMilliseconds / 50).round().clamp(1, 2000);
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (token != _fadeGen || !_fading) return;
        final pct = i / steps;
        unawaited(lead.setVolume(_volume * (1.0 - pct)));
        unawaited(other.setVolume(_volume * pct));
      }
    } catch (_) {
      // Si el fundido falla, volver al corte seco (el completed hará el avance).
      if (token == _fadeGen) _cancelFade();
    }
  }

  /// Cancela cualquier fundido/pre-carga en curso y restaura el volumen.
  void _cancelFade() {
    _fadeGen++;
    _preparedNextGen++;
    _preparedNextPos = -1;
    _fading = false;
    _preloaded = false;
    _fadeTargetPos = -1;
    unawaited(_fade.stop());
    unawaited(_lead.setVolume(_volume));
  }

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
        _onCompleted();
      }
    });
  }

  /// Activa o desactiva el modo Karaoke con reproductor directo con filtro mpv.
  Future<void> setKaraokeMode(bool enable) async {
    if (_karaokeMode == enable) return;
    if (enable && !isVocalReductionSupported) {
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
        final streamUrl = _service.getStreamUrl(currentTr.id,
            quality: _settings.effectiveQuality);
        await _applyVocalFilter(_vocalReduction);
        await _karaokePlayer!.setVolume((_volume * 100).clamp(0.0, 100.0));
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
      if (currentTr != null) {
        await _loadTrackOn(_lead, _currentIndex);
        await _lead.seek(pos);
        if (wasPlaying) {
          await _lead.play();
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
    if (_karaokePlayer == null || !isVocalReductionSupported) return;
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

  // ---------------------------------------------------------------------------
  // Control de reproducción
  // ---------------------------------------------------------------------------

  Future<void> togglePlay() async {
    if (currentTrack == null) return;
    if (_karaokeMode && _karaokePlayer != null) {
      await _karaokePlayer!.playOrPause();
      notifyListeners();
      return;
    }
    if (_lead.playing) {
      _cancelFade();
      await _lead.pause();
    } else {
      if (_lead.processingState == ProcessingState.completed) {
        await _lead.seek(Duration.zero);
      }
      await _lead.play();
    }
    notifyListeners();
  }

  Future<void> skipNext() async {
    final next = _nextOrderPos(_pos);
    if (next == null) return;
    if (await _playPreparedNext(next)) {
      _recordRecent(currentTrack!);
      _recordTrackPlay(currentTrack!);
      notifyListeners();
      return;
    }

    _cancelFade();
    _pos = next;
    if (_karaokeMode && _karaokePlayer != null) {
      final t = currentTrack;
      if (t != null) {
        final url =
            _service.getStreamUrl(t.id, quality: _settings.effectiveQuality);
        await _karaokePlayer!.open(mk.Media(url), play: true);
        _recordRecent(t);
        _recordTrackPlay(t);
      }
    } else {
      await _loadCurrentAndPlay(_lead);
      _recordRecent(currentTrack!);
      _recordTrackPlay(currentTrack!);
    }
    _prepareNextForSkip();
    notifyListeners();
  }

  Future<void> skipPrevious() async {
    _cancelFade();
    if (position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_pos > 0) {
      _pos--;
      if (_karaokeMode && _karaokePlayer != null) {
        final t = currentTrack;
        if (t != null) {
          final url =
              _service.getStreamUrl(t.id, quality: _settings.effectiveQuality);
          await _karaokePlayer!.open(mk.Media(url), play: true);
          _recordRecent(t);
          _recordTrackPlay(t);
        }
      } else {
        await _loadCurrentAndPlay(_lead);
        _recordRecent(currentTrack!);
        _recordTrackPlay(currentTrack!);
      }
      _prepareNextForSkip();
      notifyListeners();
    }
  }

  Future<void> seek(Duration target) async {
    _cancelFade();
    if (_karaokeMode && _karaokePlayer != null) {
      await _karaokePlayer!.seek(target);
    } else {
      await _lead.seek(target);
    }
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    if (_karaokeMode && _karaokePlayer != null) {
      await _karaokePlayer!.setVolume((_volume * 100).clamp(0.0, 100.0));
    } else {
      // Durante un fundido la rampa converge a `_volume`; no clobberear el cruce.
      if (!_fading) {
        await _lead.setVolume(_volume);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cambios de configuración (calidad, volumen)
  // ---------------------------------------------------------------------------

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
      _volume = _settings.initialVolume;
      if (!_fading) {
        unawaited(_lead.setVolume(_volume));
      }
    }
  }

  /// Recarga la canción en curso con la calidad nueva preservando la posición
  /// y el estado de reproducción. Deja de sonar un instante (cambio de fuente).
  Future<void> _reloadAtQuality() async {
    if (_currentIndex < 0) return;
    _cancelFade();
    final player = _lead;
    final wasPlaying = player.playing;
    final position = player.position;
    try {
      await player.stop();
      await player.setAudioSource(_sourceFor(_queue[_currentIndex]));
      await player.seek(position);
      if (wasPlaying) await player.play();
    } catch (_) {
      // Si la recarga falla (p. ej. sin conexión), no matamos la sesión.
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _karaokePosSub?.cancel();
    _karaokeDurSub?.cancel();
    _karaokePlaySub?.cancel();
    _karaokeBufSub?.cancel();
    _karaokeCompSub?.cancel();
    _karaokePlayer?.dispose();
    _karaokePositionController.close();
    _karaokeDurationController.close();
    _karaokePlayerStateController.close();
    _settings.removeListener(_onSettingsChanged);
    _service.removeListener(_onServiceChanged);
    _a.dispose();
    _b.dispose();
    super.dispose();
  }
}
