import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'diagnostics_log.dart' show redactSecrets;
import 'hifi/hifi_native.dart';
import 'hifi/hifi_profiles.dart';
import '../models/crotolink_models.dart' show sanitizeArtUrl;
import 'navidrome_service.dart';
import 'remote_playback.dart';
import 'settings_controller.dart';
import 'listening_stats_service.dart';
import 'waveform_service.dart';
import 'audio_waveform_service.dart';
import 'crotowave_audio_handler.dart';

part 'player_sleep_timer.dart';
part 'player_gain.dart';
part 'player_stats.dart';
part 'player_queue.dart';
part 'player_transitions.dart';
part 'player_karaoke.dart';
part 'player_quality.dart';

enum MostPlayedItemType { track, playlist }

/// Un contenido reproducido desde CrotoWave. Las playlists y las canciones se
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

/// Estado de [PlayerController]. Vive en una clase base para que las áreas del
/// reproductor (en archivos aparte) puedan ser mixins sobre el mismo estado.
abstract class _PlayerBase extends ChangeNotifier {
  String? Function(String trackId)? localFileResolver;

  final WaveformService _waveformService = AudioWaveformService();

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

  /// Descarta cargas de historial de un perfil anterior y serializa escrituras.
  int _historyGen = 0;
  Future<void> _historyWrite = Future.value();

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

  /// Invalida un fundido de apagado en curso al cancelar el temporizador.
  int _sleepFadeGen = 0;

  /// Guardado diferido de la cola en el servidor.
  Timer? _queueSaveTimer;

  /// Pistas que no pasan por `stream.view` (radios de internet): id → URL.
  final Map<String, String> _directStreams = {};

  Duration? _usefulStart;

  Duration? _usefulEnd;

  // --- Sleep timer ---
  Timer? _sleepTimer;

  Timer? _sleepTicker;

  DateTime? _sleepEndsAt;

  bool _sleepEndsAtEndOfTrack = false;

  // ---------------------------------------------------------------------------
  // CrotoWave Connect: modo espejo
  // ---------------------------------------------------------------------------

  RemotePlayback? _remote;

  int _forceLocal = 0;

  String? _mirroredTrackId;

  double _playbackSpeed = 1.0;

  DateTime? _lastNowPlayingAt;

  // ---------------------------------------------------------------------------
  // Cambios de configuración (calidad, volumen)
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Modos de alta fidelidad (Estándar / Alta fidelidad / Bit-perfect)
  // ---------------------------------------------------------------------------

  HifiPlan? _hifiPlan;

  double? _volumeBeforeLock;

  Future<void> _applyKaraokeVolume();
  void _applyReplayGainForTrack({
    required bool onPlayerA,
    required Track? track,
  });
  void _cancelFade();
  void _checkPlayQualification(
    Duration pos,
    Duration? dur, {
    bool completed = false,
  });
  double _computeEffectivePlayerVolume({
    required double baseVolume,
    required double crossfadeFactor,
    required ReplayGainResult? gainResult,
  });
  int get _currentIndex;
  void _ensureWatchdog();
  AudioPlayer get _fade;
  ReplayGainResult? get _fadeGain;
  AudioPlayer get _lead;
  ReplayGainResult? get _leadGain;
  Future<void> _loadCurrentAndPlay(AudioPlayer p);
  Future<void> _loadCurrentTrackWaveform();
  Future<void> _loadTrackOn(AudioPlayer p, int realIndex);
  bool get _mirror;
  void _onCompleted();
  void _prepareNextForSkip();
  List<int> _randomOrderKeeping(int keepIndex, int n);
  void _reapplyReplayGainToCurrentPlayers();
  void _recordRecent(Track track);
  Duration? _remainingToPlay();
  void _resetPlayTracking();
  NavidromeService get _service;
  SettingsController get _settings;
  AudioSource _sourceFor(Track t);
  String _mediaLocationFor(Track t);
  ListeningStatsService? get _statsService;
  void cancelSleepTimer({bool silent = false});
  void clearQueue();
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    Playlist? sourcePlaylist,
  });
  Track? get currentTrack;
  bool get playing;
  Duration get position;
  Future<void> skipNext();
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
class PlayerController extends _PlayerBase
    with
        _PlayerSleepTimer,
        _PlayerGain,
        _PlayerStats,
        _PlayerQueue,
        _PlayerTransitions,
        _PlayerKaraoke,
        _PlayerQuality {
  @override
  final NavidromeService _service;

  @override
  final SettingsController _settings;

  @override
  final ListeningStatsService? _statsService;

  final AudioPlayer _a;

  final AudioPlayer _b;

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
  @override
  AudioPlayer get _lead => _useA ? _a : _b;

  /// Reproductor de reserva, usado para el fundido entrante.
  @override
  AudioPlayer get _fade => _useA ? _b : _a;

  Playlist? get sourcePlaylist => _sourcePlaylist;

  static const Duration _preRoll = Duration(seconds: 3);

  // --- Smart Mix & Silence Removal ---
  static const double _silenceThreshold = 0.01;

  /// Dispositivo remoto controlado (Connect). Mientras esté activo, este
  /// controlador refleja y manda al remoto en lugar de reproducir aquí.
  RemotePlayback? get remote => _remote;

  set remote(RemotePlayback? value) {
    _remote?.removeListener(_onRemoteChanged);
    _remote = value;
    _remote?.addListener(_onRemoteChanged);
  }

  @override
  bool get _mirror => _forceLocal == 0 && (_remote?.active ?? false);

  /// `true` si ahora mismo se está controlando otro dispositivo.
  bool get isMirroring => _mirror;

  /// Ejecuta [action] sobre el reproductor local aunque haya un remoto
  /// controlado (lo usa Connect para transferir y para atender comandos).
  Future<T> runLocally<T>(Future<T> Function() action) async {
    _forceLocal++;
    try {
      return await action();
    } finally {
      _forceLocal--;
    }
  }

  /// Lee estado del reproductor local ignorando el modo espejo.
  T readLocally<T>(T Function() read) {
    _forceLocal++;
    try {
      return read();
    } finally {
      _forceLocal--;
    }
  }

  void _onRemoteChanged() {
    if (_mirror) {
      final id = currentTrack?.id;
      if (id != _mirroredTrackId) {
        _mirroredTrackId = id;
        if (id != null) _loadCurrentTrackWaveform();
      }
    } else {
      _mirroredTrackId = null;
    }
    notifyListeners();
  }

  /// Emite el valor local mientras se reproduce aquí y el del remoto, muestreado,
  /// mientras se controla otro dispositivo (los widgets no tienen que
  /// resuscribirse al cambiar de modo).
  Stream<T> _modal<T>(Stream<T> local, T Function() remoteNow,
      {Duration tick = const Duration(milliseconds: 250)}) {
    late StreamController<T> controller;
    StreamSubscription<T>? sub;
    Timer? timer;
    controller = StreamController<T>(
      onListen: () {
        sub = local.listen((v) {
          if (!_mirror) controller.add(v);
        }, onError: controller.addError);
        timer = Timer.periodic(tick, (_) {
          if (_mirror) controller.add(remoteNow());
        });
        if (_mirror) controller.add(remoteNow());
      },
      onCancel: () {
        timer?.cancel();
        return sub?.cancel();
      },
    );
    return controller.stream;
  }

  List<Track> get queue =>
      _mirror ? List.unmodifiable(_remote!.queue) : List.unmodifiable(_queue);

  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);

  /// Firma barata de [mostPlayed] para `context.select`: la pantalla de inicio
  /// solo se reconstruye cuando cambian los contadores, no con cada cambio de
  /// estado del reproductor (play/pausa, posición, buffering…).
  String get mostPlayedSignature {
    final b = StringBuffer();
    for (final item in _mostPlayedByKey.values) {
      b
        ..write(item.type.name)
        ..write(':')
        ..write(item.id)
        ..write(':')
        ..write(item.playCount)
        ..write(';');
    }
    return b.toString();
  }

  /// Firma de [recentlyPlayed] (ver [mostPlayedSignature]).
  String get recentlyPlayedSignature =>
      _recentlyPlayed.take(12).map((t) => t.id).join(',');

  List<MostPlayedItem> get mostPlayed {
    final items = _mostPlayedByKey.values.toList();
    items.sort((a, b) {
      final byCount = b.playCount.compareTo(a.playCount);
      return byCount != 0 ? byCount : b.lastPlayedAt.compareTo(a.lastPlayedAt);
    });
    return List.unmodifiable(items);
  }

  int get currentOrderPos => _mirror ? _remote!.index : _pos;

  List<int> get order => _mirror
      ? List.generate(_remote!.queue.length, (i) => i)
      : List.unmodifiable(_order);

  List<Track> get orderedQueue => _mirror
      ? List.unmodifiable(_remote!.queue)
      : [
          for (final idx in _order)
            if (idx >= 0 && idx < _queue.length) _queue[idx]
        ];

  @override
  int get _currentIndex =>
      _pos >= 0 && _pos < _order.length ? _order[_pos] : -1;

  @override
  Track? get currentTrack {
    if (_mirror) {
      final i = _remote!.index;
      final q = _remote!.queue;
      return i >= 0 && i < q.length ? q[i] : null;
    }
    return _currentIndex >= 0 ? _queue[_currentIndex] : null;
  }

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
  @override
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
        // Descargada: analizar el archivo local, sin red ni token.
        streamUrl = localFileResolver?.call(track.id) ??
            _service.getStreamUrl(track.id,
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
        debugPrint('Error loading real waveform: ${redactSecrets('$e')}');
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

  Stream<PlayerState> get playerStateStream => _modal(
      _karaokeMode
          ? _karaokePlayerStateController.stream
          : _leadStateController.stream,
      () => PlayerState(_remote!.playing, ProcessingState.ready));

  Stream<Duration> get positionStream => _modal(
      _karaokeMode
          ? _karaokePositionController.stream
          : _leadPositionController.stream,
      () => _remote!.position);

  Stream<Duration?> get durationStream => _modal(
      _karaokeMode ? _karaokeDurationController.stream : _lead.durationStream,
      () => _remote!.duration);

  Stream<double> get volumeStream =>
      _modal(_lead.volumeStream, () => _remote!.volume);

  bool get shuffleEnabled => _mirror ? _remote!.shuffle : _shuffleEnabled;

  LoopMode get repeatMode => _mirror ? _remote!.repeat : _repeatMode;

  @override
  bool get playing => _mirror
      ? _remote!.playing
      : _karaokeMode
          ? (_karaokePlayer?.state.playing ?? false)
          : _lead.playing;

  @override
  Duration get position => _mirror
      ? _remote!.position
      : _karaokeMode
          ? (_karaokePlayer?.state.position ?? Duration.zero)
          : _lead.position;

  Duration? get duration => _mirror
      ? _remote!.duration
      : _karaokeMode
          ? _karaokePlayer?.state.duration
          : _lead.duration;

  double get volume => _mirror ? _remote!.volume : _volume;

  double get playbackSpeed => _playbackSpeed;

  /// Velocidad de reproducción (la usa CrotoLink para corregir deriva suavemente).
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

  CrotoWaveAudioHandler? _audioHandler;

  CrotoWaveAudioHandler? get audioHandler => _audioHandler;

  void setAudioHandler(CrotoWaveAudioHandler? handler) {
    if (identical(_audioHandler, handler)) return;
    _audioHandler?.detachPlayerController();
    _audioHandler = handler;
    _audioHandler?.attachPlayerController(this);
  }

  PlayerController(
    NavidromeService service,
    SettingsController settings, {
    ListeningStatsService? statsService,
    CrotoWaveAudioHandler? audioHandler,
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
    _service.addListener(_onServiceChanged);
    _onServiceChanged();
    // Con sesión, `_onServiceChanged` ya cargó el historial del perfil; sin
    // sesión no hay cambio que lo dispare.
    if (_mostPlayedSession == null) _loadHistory();
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

  void _listenPlayers() {
    _playerSubs
      ..add(_a.playerStateStream.listen((s) => _onPlayerState(_a, s)))
      ..add(_b.playerStateStream.listen((s) => _onPlayerState(_b, s)))
      ..add(_a.positionStream.listen((pos) => _onPositionChanged(_a, pos)))
      ..add(_b.positionStream.listen((pos) => _onPositionChanged(_b, pos)));
  }

  /// Suscripciones a los dos reproductores; se cancelan en [dispose] para que
  /// un evento tardío no notifique a un controlador ya liberado.
  final List<StreamSubscription<dynamic>> _playerSubs = [];

  /// Streams estables del reproductor que conduce: tras un crossfade el rol
  /// A/B se intercambia, y quien ya estaba suscrito seguiría al viejo.
  final StreamController<Duration> _leadPositionController =
      StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _leadStateController =
      StreamController<PlayerState>.broadcast();

  void _onPositionChanged(AudioPlayer player, Duration pos) {
    if (identical(player, _lead)) _leadPositionController.add(pos);
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
    _leadStateController.add(state);
    notifyListeners();
    if (state.processingState == ProcessingState.completed) {
      _checkPlayQualification(_lead.position, _lead.duration, completed: true);
      _onCompleted();
    }
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
            'coverArtUrl': sanitizeArtUrl(item.playlist!.coverArtUrl),
            'songCount': item.playlist!.songCount,
            'duration': item.playlist!.duration,
          },
      };

  static MostPlayedItem? _mostPlayedFromJson(Map<String, dynamic> json,
      {String? Function(String?) art = _sameUrl}) {
    final type = json['type'];
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) return null;
    final count = (json['playCount'] as num?)?.toInt() ?? 0;
    final lastPlayedAt =
        DateTime.tryParse(json['lastPlayedAt'] as String? ?? '');
    if (count <= 0 || lastPlayedAt == null) return null;

    if (type == MostPlayedItemType.track.name && json['track'] is Map) {
      return MostPlayedItem.track(
        _trackFromJson(Map<String, dynamic>.from(json['track'] as Map),
            art: art),
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
          coverArtUrl: art(playlist['coverArtUrl'] as String?),
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
        // Sin `u`/`s`/`t`: el token no caduca y estos JSON quedan en disco
        // (en iOS, visibles desde Archivos). Se vuelve a firmar al cargar.
        'albumArtUrl': sanitizeArtUrl(t.albumArtUrl),
        'playCount': t.playCount,
        if (t.artistId != null) 'artistId': t.artistId,
        if (t.albumId != null) 'albumId': t.albumId,
        if (t.replayGain != null) 'replayGain': t.replayGain!.toJson(),
      };

  static String? _sameUrl(String? url) => url;

  static Track _trackFromJson(Map<String, dynamic> j,
          {String? Function(String?) art = _sameUrl}) =>
      Track(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? 'Unknown',
        artist: (j['artist'] as String?) ?? 'Unknown',
        album: (j['album'] as String?) ?? 'Unknown',
        duration: (j['duration'] as String?) ?? '',
        albumArtUrl: art(j['albumArtUrl'] as String?),
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

  /// Archivo local si la pista está descargada; si no, la URL de streaming.
  /// Lo usa el reproductor de karaoke (media_kit), que no pasa por `_sourceFor`.
  @override
  String _mediaLocationFor(Track t) =>
      _directStreams[t.id] ??
      localFileResolver?.call(t.id) ??
      _service.getPlaybackStreamUrl(t.id, quality: _settings.effectiveQuality);

  @override
  AudioSource _sourceFor(Track t) {
    final direct = _directStreams[t.id];
    if (direct != null) return AudioSource.uri(Uri.parse(direct));
    final path = localFileResolver?.call(t.id);
    return AudioSource.uri(path != null
        ? Uri.file(path)
        : Uri.parse(_service.getPlaybackStreamUrl(t.id,
            quality: _settings.effectiveQuality)));
  }

  @override
  Future<void> _loadTrackOn(AudioPlayer p, int realIndex) async {
    final track = _queue[realIndex];
    final isPlayerA = identical(p, _a);
    _applyReplayGainForTrack(onPlayerA: isPlayerA, track: track);
    await _requestHifiOutputFor(track);
    await p.setAudioSource(_sourceFor(track));
    final gainResult = isPlayerA ? _gainA : _gainB;
    final targetVol = _computeEffectivePlayerVolume(
      baseVolume: _volume,
      crossfadeFactor: 1.0,
      gainResult: gainResult,
    );
    await p.setVolume(targetVol);
  }

  @override
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
      unawaited(_loadCurrentTrackWaveform());
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
  @override
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

  static Duration? _trackDuration(Track? t) {
    final s = int.tryParse(t?.duration ?? '');
    return s == null ? null : Duration(seconds: s);
  }

  // ---------------------------------------------------------------------------
  // Control de reproducción
  // ---------------------------------------------------------------------------

  Future<void> togglePlay() async {
    if (_mirror) return _remote!.toggle();
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
    if (_mirror) return _remote!.play();
    if (!playing) await togglePlay();
  }

  Future<void> pause() async {
    if (_mirror) return _remote!.pause();
    if (playing) await togglePlay();
  }

  @override
  Future<void> skipNext() async {
    if (_mirror) return _remote!.next();
    final next = _nextOrderPos(_pos);
    if (next == null) return;
    if (await _playPreparedNext(next)) {
      _recordRecent(currentTrack!);
      _resetPlayTracking();
      unawaited(
          _loadCurrentTrackWaveform()); // Load waveform for the next track
      notifyListeners();
      return;
    }

    _cancelFade();
    _pos = next;
    if (_karaokeMode && _karaokePlayer != null) {
      final t = currentTrack;
      if (t != null) {
        final url = _mediaLocationFor(t);
        await _applyKaraokeVolume();
        await _karaokePlayer!.open(mk.Media(url), play: true);
        _recordRecent(t);
        _resetPlayTracking();
        unawaited(_loadCurrentTrackWaveform());
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
    if (_mirror) return _remote!.previous();
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
          final url = _mediaLocationFor(t);
          await _applyKaraokeVolume();
          await _karaokePlayer!.open(mk.Media(url), play: true);
          _recordRecent(t);
          _resetPlayTracking();
          unawaited(_loadCurrentTrackWaveform());
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
    if (_mirror) return _remote!.seek(target);
    _cancelFade();
    if (_karaokeMode && _karaokePlayer != null) {
      await _karaokePlayer!.seek(target);
    } else {
      await _lead.seek(target);
    }
    _audioHandler?.updatePosition(target);
  }

  Future<void> setVolume(double v) async {
    if (_mirror) return _remote!.setVolume(v.clamp(0.0, 1.0).toDouble());
    // Bit-perfect: el volumen digital queda fijo al 100 %.
    if (volumeLocked) return;
    _volume = v.clamp(0.0, 1.0).toDouble();
    notifyListeners();
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

  @override
  void dispose() {
    _remote?.removeListener(_onRemoteChanged);
    _audioHandler?.detachPlayerController();
    _audioHandler = null;
    _sleepFadeGen++;
    _queueSaveTimer?.cancel();
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
    for (final sub in _playerSubs) {
      sub.cancel();
    }
    _leadPositionController.close();
    _leadStateController.close();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }
}
