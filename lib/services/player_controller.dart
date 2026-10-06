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
import 'listening_stats_service.dart';
import 'waveform_service.dart';
import 'audio_waveform_service.dart';
import 'scrotify_audio_handler.dart';

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
  String? Function(String trackId)? localFileResolver;
  final NavidromeService _service;
  final SettingsController _settings;
  final WaveformService _waveformService = AudioWaveformService();
  final ListeningStatsService? _statsService;

  String? _currentlyTrackedId;
  bool _currentTrackPlayCounted = false;

  WaveformData? _waveformData; // Current waveform data (audio real)
  bool _isWaveformLoading = false; // Loading state
  int _waveformGen = 0; // token anti race-condition por cambio rápido

  // Última calidad efectiva aplicada, para recargar la canción en curso solo
  // cuando la calidad realmente cambió (p. ej. al pasar de WiFi a móvil).
  AudioQuality _lastAppliedQuality = AudioQuality.lossless;
  // Último "volumen inicial" aplicado; evita re-aplicarlo en cada cambio de
  double _lastAppliedVolume = 0.7;

  final AudioPlayer _a;
  final AudioPlayer _b;
  bool _useA = true;

  ReplayGainResult? _gainA;
  ReplayGainResult? _gainB;
  ReplayGainResult? _karaokeGain;

  ReplayGainMode _lastAppliedReplayGainMode = ReplayGainMode.off;
  double _lastAppliedReplayGainPreamp = 0.0;
  bool _lastAppliedReplayGainPreventClipping = true;

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
  Playlist? get sourcePlaylist => _sourcePlaylist;
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
  int _watchdogIdleTicks = 0;
  int _fadeGen = 0; // token: cada cancelación/cambio de objetivo lo invalida
  bool _preloaded = false;
  bool _fading = false;
  int _fadeTargetPos = -1;
  // La siguiente pista se prepara aunque el crossfade esté desactivado. Así el
  // botón «siguiente» puede cambiar de reproductor sin volver a abrir el
  // stream desde cero.
  int _preparedNextPos = -1;
  int _preparedNextGen = 0;
  int _loadGen = 0;
  static const Duration _preRoll = Duration(seconds: 3);

  // --- Smart Mix & Silence Removal ---
  static const double _silenceThreshold = 0.01;
  Duration? _usefulStart;
  Duration? _usefulEnd;
  // --- Sleep timer ---
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepEndsAt;
  bool _sleepEndsAtEndOfTrack = false;

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
  void cancelSleepTimer({bool silent = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepEndsAt = null;
    _sleepEndsAtEndOfTrack = false;
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

  // Waveform handling
  WaveformData? get waveformData => _waveformData;
  bool get isWaveformLoading => _isWaveformLoading;

  /// Load waveform for the current track from the REAL audio.
  ///
  /// Descarga el stream real (vía NavidromeService.getStreamUrl), lo
  /// decodifica a PCM y calcula RMS/peak por ventana. El trackId solo es
  /// clave de caché. Incluye protección anti race-condition para cambios
  /// rápidos de canción.
  Future<void> _loadCurrentTrackWaveform() async {
    final track = currentTrack;
    if (track == null) return;

    final gen = ++_waveformGen;
    _isWaveformLoading = true;
    notifyListeners();

    try {
      final duration = _trackDuration(track) ?? _lead.duration ?? Duration.zero;
      if (duration.inMilliseconds <= 0) {
        if (gen == _waveformGen && currentTrack?.id == track.id) {
          _waveformData = null;
        }
        return;
      }
      String streamUrl;
      try {
        streamUrl = _service.getStreamUrl(track.id,
            quality: _settings.effectiveQuality);
      } catch (_) {
        return; // Sin URL (offline): sin waveform, nunca sintética.
      }
      final data =
          await _waveformService.getWaveform(track.id, streamUrl, duration);
      // Solo aplicar si seguimos en la misma pista y generación.
      if (gen != _waveformGen || currentTrack?.id != track.id) return;
      _waveformData = data;
      // Silence removal: compute useful start/end if enabled
      if (_settings.silenceRemovalEnabled) {
        _computeSilenceBounds(data);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading real waveform: $e');
      }
      if (gen == _waveformGen && currentTrack?.id == track.id) {
        _waveformData = null; // Sin datos: estado neutro, nunca sintético.
      }
    } finally {
      if (gen == _waveformGen && currentTrack?.id == track.id) {
        _isWaveformLoading = false;
        notifyListeners();
      }
    }
  }

  void _computeSilenceBounds(WaveformData data) {
    final amps = data.amplitudes;
    if (amps.isEmpty) {
      _usefulStart = null;
      _usefulEnd = null;
      return;
    }
    final totalMs = data.duration.inMilliseconds;
    int firstIdx = -1;
    int lastIdx = -1;
    for (int i = 0; i < amps.length; i++) {
      if (amps[i] > _silenceThreshold) {
        if (firstIdx == -1) firstIdx = i;
        lastIdx = i;
      }
    }
    if (firstIdx == -1) {
      _usefulStart = null;
      _usefulEnd = null;
      return;
    }
    final binMs = totalMs / amps.length;
    _usefulStart = Duration(milliseconds: (firstIdx * binMs).round());
    _usefulEnd = Duration(milliseconds: ((lastIdx + 1) * binMs).round());
  }

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

  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  /// Velocidad de reproducción (la usa Jam para corregir deriva suavemente).
  /// Se aplica a ambos reproductores A/B; si el motor no la soporta, se ignora.
  Future<void> setPlaybackSpeed(double speed) async {
    final v = speed.clamp(0.5, 2.0).toDouble();
    if (v == _playbackSpeed) return;
    _playbackSpeed = v;
    for (final p in [_a, _b]) {
      try {
        await p.setSpeed(v);
      } catch (e) {
        debugPrint('PlayerController.setPlaybackSpeed no soportado: $e');
      }
    }
  }

  bool get gapless => _settings.gapless;
  ProcessingState get processingState => _karaokeMode
      ? (_karaokePlayer != null && (_karaokePlayer?.state.buffering ?? false)
          ? ProcessingState.buffering
          : ProcessingState.ready)
      : _lead.processingState;

  ScrotifyAudioHandler? _audioHandler;
  ScrotifyAudioHandler? get audioHandler => _audioHandler;

  void setAudioHandler(ScrotifyAudioHandler? handler) {
    if (identical(_audioHandler, handler)) return;
    _audioHandler?.detachPlayerController();
    _audioHandler = handler;
    _audioHandler?.attachPlayerController(this);
  }

  PlayerController(
    NavidromeService service,
    SettingsController settings, {
    ListeningStatsService? statsService,
    ScrotifyAudioHandler? audioHandler,
    AudioPlayer? playerA,
    AudioPlayer? playerB,
    AndroidLoudnessEnhancer? loudnessEnhancerA,
    AndroidLoudnessEnhancer? loudnessEnhancerB,
  }) : this._internal(
          service,
          settings,
          statsService,
          audioHandler,
          playerA,
          playerB,
        );

  PlayerController._internal(
    this._service,
    this._settings,
    this._statsService,
    this._audioHandler,
    AudioPlayer? playerA,
    AudioPlayer? playerB,
  )   : _a = playerA ?? _createPlayer(),
        _b = playerB ?? _createPlayer() {
    _listenPlayers();
    _loadHistory();
    _service.addListener(_onServiceChanged);
    _onServiceChanged();
    _lastAppliedQuality = _settings.effectiveQuality;
    _volume = _settings.initialVolume;
    _lastAppliedVolume = _settings.initialVolume;
    _lastAppliedReplayGainMode = _settings.replayGainMode;
    _lastAppliedReplayGainPreamp = _settings.replayGainPreamp;
    _lastAppliedReplayGainPreventClipping = _settings.replayGainPreventClipping;
    _settings.addListener(_onSettingsChanged);
    _audioHandler?.attachPlayerController(this);
  }

  static AudioPlayer _createPlayer() {
    return AudioPlayer();
  }

  /// Resultado efectivo de ReplayGain para la canción en reproducción audible.
  ReplayGainResult? get currentReplayGain {
    if (_karaokeMode && _karaokePlayer != null) {
      if (currentTrack == null) return null;
      return _karaokeGain ?? _computeTrackReplayGain(currentTrack);
    }
    return _leadGain;
  }

  ReplayGainResult? get _leadGain => _useA ? _gainA : _gainB;
  ReplayGainResult? get _fadeGain => _useA ? _gainB : _gainA;

  ReplayGainResult _computeTrackReplayGain(Track? track) {
    return computeReplayGain(
      replayGain: track?.replayGain,
      mode: _settings.replayGainMode,
      preampDb: _settings.replayGainPreamp,
      preventClipping: _settings.replayGainPreventClipping,
    );
  }

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
  double _computeEffectivePlayerVolume({
    required double baseVolume,
    required double crossfadeFactor,
    required ReplayGainResult? gainResult,
  }) {
    final mult = gainResult?.multiplier ?? 1.0;
    return (baseVolume * crossfadeFactor * mult).clamp(0.0, 1.0);
  }

  /// Calcula el volumen efectivo para el reproductor Karaoke (media_kit, 0..100).
  /// Preserva `_volume` del usuario intacto (0..1) y aplica el multiplicador de
  /// atenuación pura (multiplier <= 1.0) sin exceder el rango [0.0, 100.0].
  @visibleForTesting
  static double computeEffectiveKaraokeVolume({
    required double baseVolume,
    required ReplayGainResult? gainResult,
  }) {
    final mult = (gainResult?.multiplier ?? 1.0).clamp(0.0, 1.0);
    return (baseVolume.clamp(0.0, 1.0) * 100.0 * mult).clamp(0.0, 100.0);
  }

  double _computeEffectiveKaraokeVolume({
    required double baseVolume,
    required ReplayGainResult? gainResult,
  }) =>
      computeEffectiveKaraokeVolume(
        baseVolume: baseVolume,
        gainResult: gainResult,
      );

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

  void _listenPlayers() {
    _a.playerStateStream.listen((s) => _onPlayerState(_a, s));
    _b.playerStateStream.listen((s) => _onPlayerState(_b, s));
    _a.positionStream.listen((pos) => _onPositionChanged(_a, pos));
    _b.positionStream.listen((pos) => _onPositionChanged(_b, pos));
  }

  void _onPositionChanged(AudioPlayer player, Duration pos) {
    if (!identical(player, _lead) || !player.playing) return;
    final last = _lastNowPlayingAt;
    if (last != null &&
        DateTime.now().difference(last) > const Duration(minutes: 2)) {
      _reportNowPlaying();
    }
    _checkPlayQualification(pos, player.duration);
  }

  void _onPlayerState(AudioPlayer p, PlayerState state) {
    // Solo el lead alimenta la UI; el reproductor de fundido se gestiona aparte.
    if (!identical(p, _lead)) return;
    notifyListeners();
    if (state.processingState == ProcessingState.completed) {
      _checkPlayQualification(_lead.position, _lead.duration, completed: true);
      _onCompleted();
    }
  }

  void _checkPlayQualification(Duration pos, Duration? dur,
      {bool completed = false}) {
    final track = currentTrack;
    if (track == null) return;

    if (_currentlyTrackedId != track.id) {
      _currentlyTrackedId = track.id;
      _currentTrackPlayCounted = false;
    }

    if (_currentTrackPlayCounted) return;

    final effectiveDur = dur ?? _trackDuration(track);

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

    if (_sourcePlaylist != null) {
      _recordPlaylistPlay(_sourcePlaylist!);
    } else {
      _recordTrackPlay(track);
    }
  }

  void _resetPlayTracking() {
    _currentlyTrackedId = currentTrack?.id;
    _currentTrackPlayCounted = false;
    _reportNowPlaying();
  }

  DateTime? _lastNowPlayingAt;

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
    try {
      final dir = await getApplicationDocumentsDirectory();
      final session = _mostPlayedSession;
      File file;
      if (session != null) {
        final scoped = File('${dir.path}/${_historyFileName(session)}');
        if (await scoped.exists()) {
          file = scoped;
        } else {
          file = File('${dir.path}/recently_played.json');
        }
      } else {
        file = File('${dir.path}/recently_played.json');
      }

      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        _recentlyPlayed =
            list.map((j) => _trackFromJson(j as Map<String, dynamic>)).toList();
        notifyListeners();
      } else {
        _recentlyPlayed = [];
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore — el historial es una conveniencia, no algo crítico.
    }
  }

  Future<void> _saveHistory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final session = _mostPlayedSession;
      final fileName =
          session != null ? _historyFileName(session) : 'recently_played.json';
      final file = File('${dir.path}/$fileName');
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
        if (t.artistId != null) 'artistId': t.artistId,
        if (t.albumId != null) 'albumId': t.albumId,
        if (t.replayGain != null) 'replayGain': t.replayGain!.toJson(),
      };

  static Track _trackFromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? 'Unknown',
        artist: (j['artist'] as String?) ?? 'Unknown',
        album: (j['album'] as String?) ?? 'Unknown',
        duration: (j['duration'] as String?) ?? '',
        albumArtUrl: j['albumArtUrl'] as String?,
        playCount: (j['playCount'] as num?)?.toInt() ?? 0,
        artistId: j['artistId'] as String?,
        albumId: j['albumId'] as String?,
        replayGain: j['replayGain'] is Map
            ? ReplayGainMetadata.fromJson(
                (j['replayGain'] as Map).cast<String, dynamic>())
            : null,
      );

  // ---------------------------------------------------------------------------
  // Carga de fuentes
  // ---------------------------------------------------------------------------

  AudioSource _sourceFor(Track t) {
    final path = localFileResolver?.call(t.id);
    return AudioSource.uri(path != null
        ? Uri.file(path)
        : Uri.parse(
            _service.getStreamUrl(t.id, quality: _settings.effectiveQuality)));
  }

  Future<void> _loadTrackOn(AudioPlayer p, int realIndex) async {
    final track = _queue[realIndex];
    final isPlayerA = identical(p, _a);
    _applyReplayGainForTrack(onPlayerA: isPlayerA, track: track);
    await p.setAudioSource(_sourceFor(track));
    final gainResult = isPlayerA ? _gainA : _gainB;
    final targetVol = _computeEffectivePlayerVolume(
      baseVolume: _volume,
      crossfadeFactor: 1.0,
      gainResult: gainResult,
    );
    await p.setVolume(targetVol);
  }

  Future<void> _loadCurrentAndPlay(AudioPlayer p) async {
    final gen = ++_loadGen;
    try {
      final index = _currentIndex;
      if (index < 0 || index >= _queue.length) return;
      await _loadTrackOn(p, index);
      if (gen != _loadGen) return;
      if (_settings.silenceRemovalEnabled && _usefulStart != null) {
        await p.seek(_usefulStart!);
      }
      if (gen != _loadGen) return;
      unawaited(p.play().catchError((_) {}));
      // Load waveform after starting playback
      _loadCurrentTrackWaveform();
    } catch (_) {
      // Si la carga falla (p. ej. sin conexión), no se mata la sesión.
    }
  }

  // ---------------------------------------------------------------------------
  // Orden de reproducción (shuffle)
  // ---------------------------------------------------------------------------

  /// Orden aleatorio de `n` elementos que mantiene el índice [keepIndex] en su
  /// posición natural (la canción tocada sigue siendo la actual). Smart Mix:
  /// evita repetir artista en los últimos 2 slots.
  List<int> _randomOrderKeeping(int keepIndex, int n) {
    final rest = <int>[];
    for (var i = 0; i < n; i++) {
      if (i == keepIndex) continue;
      rest.add(i);
    }
    rest.shuffle(_rand);

    if (_settings.isSmartMixEnabled && n > 3) {
      String? getArtistKey(int idx) {
        if (idx < 0 || idx >= _queue.length) return null;
        final t = _queue[idx];
        if (t.artistId != null && t.artistId!.isNotEmpty) return t.artistId;
        if (t.artist.isNotEmpty) return t.artist.trim().toLowerCase();
        return null;
      }

      final pool = List<int>.from(rest);
      final arranged = <int>[];
      final recentArtists = <String>[];
      final currentArtist = getArtistKey(keepIndex);
      if (currentArtist != null) {
        recentArtists.add(currentArtist);
      }

      while (pool.isNotEmpty) {
        int candIdx = pool.indexWhere((idx) {
          final a = getArtistKey(idx);
          return a == null || !recentArtists.contains(a);
        });

        if (candIdx == -1) {
          candIdx = 0;
        }

        final chosen = pool.removeAt(candIdx);
        arranged.add(chosen);
        final a = getArtistKey(chosen);
        if (a != null) {
          recentArtists.add(a);
          if (recentArtists.length > 2) {
            recentArtists.removeAt(0);
          }
        }
      }
      rest
        ..clear()
        ..addAll(arranged);
    }

    rest.insert(keepIndex, keepIndex);
    return rest;
  }

  @visibleForTesting
  List<int> randomOrderKeepingForTesting(int keepIndex, int n) =>
      _randomOrderKeeping(keepIndex, n);

  @visibleForTesting
  void setQueueForTesting(List<Track> tracks) {
    _queue = List.of(tracks);
  }

  @visibleForTesting
  Duration? get usefulStartForTesting => _usefulStart;

  @visibleForTesting
  Duration? get usefulEndForTesting => _usefulEnd;

  @visibleForTesting
  void computeSilenceBoundsForTesting(WaveformData data) =>
      _computeSilenceBounds(data);

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
    unawaited(_lead.play().catchError((_) {}));
    _recordRecent(currentTrack!);
    _resetPlayTracking();
    _loadCurrentTrackWaveform();
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
      unawaited(_lead.play().catchError((_) {}));
      _recordRecent(currentTrack!);
      _resetPlayTracking();
      _loadCurrentTrackWaveform();
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
      unawaited(_lead.play().catchError((_) {}));
      _recordRecent(currentTrack!);
      _resetPlayTracking();
      _loadCurrentTrackWaveform();
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
    if (_karaokePlayer != null) {
      unawaited(_karaokePlayer!.pause());
    }
    _waveformData = null;
    _isWaveformLoading = false;
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
        final url =
            _service.getStreamUrl(t.id, quality: _settings.effectiveQuality);
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
      _loadCurrentTrackWaveform();
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
    if (!_preloaded && remaining <= crossfade! + _preRoll) {
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
      unawaited(_lead.play());
      _ensureWatchdog();
    }
    notifyListeners();
  }

  Future<void> play() async {
    if (!playing) await togglePlay();
  }

  Future<void> pause() async {
    if (playing) await togglePlay();
  }

  Future<void> skipNext() async {
    final next = _nextOrderPos(_pos);
    if (next == null) return;
    if (await _playPreparedNext(next)) {
      _recordRecent(currentTrack!);
      _resetPlayTracking();
      _loadCurrentTrackWaveform(); // Load waveform for the next track
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
        await _applyKaraokeVolume();
        await _karaokePlayer!.open(mk.Media(url), play: true);
        _recordRecent(t);
        _resetPlayTracking();
        _loadCurrentTrackWaveform();
      }
    } else {
      await _loadCurrentAndPlay(_lead);
      _recordRecent(currentTrack!);
      _resetPlayTracking();
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
          await _applyKaraokeVolume();
          await _karaokePlayer!.open(mk.Media(url), play: true);
          _recordRecent(t);
          _resetPlayTracking();
          _loadCurrentTrackWaveform();
        }
      } else {
        await _loadCurrentAndPlay(_lead);
        _recordRecent(currentTrack!);
        _resetPlayTracking();
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
    _audioHandler?.updatePosition(target);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    if (_karaokeMode && _karaokePlayer != null) {
      await _applyKaraokeVolume();
    } else {
      // Durante un fundido la rampa converge a `_volume`; no clobberear el cruce.
      if (!_fading) {
        final leadVol = _computeEffectivePlayerVolume(
          baseVolume: _volume,
          crossfadeFactor: 1.0,
          gainResult: _leadGain,
        );
        await _lead.setVolume(leadVol);
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
        final url =
            _service.getStreamUrl(t.id, quality: _settings.effectiveQuality);
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

  @override
  void dispose() {
    _audioHandler?.detachPlayerController();
    _audioHandler = null;
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
