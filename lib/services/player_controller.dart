import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';
import 'settings_controller.dart';

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
  static const Duration _preRoll = Duration(seconds: 3);

  List<Track> get queue => List.unmodifiable(_queue);
  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);

  int get _currentIndex => _pos >= 0 && _pos < _order.length ? _order[_pos] : -1;

  Track? get currentTrack =>
      _currentIndex >= 0 ? _queue[_currentIndex] : null;
  bool get hasTrack => currentTrack != null;

  Stream<PlayerState> get playerStateStream => _lead.playerStateStream;
  Stream<Duration> get positionStream => _lead.positionStream;
  Stream<Duration?> get durationStream => _lead.durationStream;
  Stream<double> get volumeStream => _lead.volumeStream;

  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get repeatMode => _repeatMode;
  bool get playing => _lead.playing;
  Duration get position => _lead.position;
  Duration? get duration => _lead.duration;
  double get volume => _volume;
  bool get gapless => _settings.gapless;

  PlayerController(this._service, this._settings) {
    _listenPlayers();
    _loadHistory();
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
        _recentlyPlayed = list
            .map((j) => _trackFromJson(j as Map<String, dynamic>))
            .toList();
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
      await file
          .writeAsString(jsonEncode(_recentlyPlayed.map(_trackToJson).toList()));
    } catch (_) {}
  }

  static Map<String, dynamic> _trackToJson(Track t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'duration': t.duration,
        'albumArtUrl': t.albumArtUrl,
      };

  static Track _trackFromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? 'Unknown',
        artist: (j['artist'] as String?) ?? 'Unknown',
        album: (j['album'] as String?) ?? 'Unknown',
        duration: (j['duration'] as String?) ?? '',
        albumArtUrl: j['albumArtUrl'] as String?,
      );

  // ---------------------------------------------------------------------------
  // Carga de fuentes
  // ---------------------------------------------------------------------------

  AudioSource _sourceFor(Track t) => AudioSource.uri(Uri.parse(
      _service.getStreamUrl(t.id, quality: _settings.effectiveQuality)));

  Future<void> _loadTrackOn(AudioPlayer p, int realIndex) async {
    await p.stop();
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

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _cancelFade();
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
    _ensureWatchdog();
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
      unawaited(_lead.seek(Duration.zero));
      unawaited(_lead.play());
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
    unawaited(_loadCurrentAndPlay(_lead));
    _recordRecent(currentTrack!);
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
      final steps =
          (fadeDur.inMilliseconds / 50).round().clamp(1, 2000);
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
    _fading = false;
    _preloaded = false;
    _fadeTargetPos = -1;
    unawaited(_fade.stop());
    unawaited(_lead.setVolume(_volume));
  }

  // ---------------------------------------------------------------------------
  // Control de reproducción
  // ---------------------------------------------------------------------------

  Future<void> togglePlay() async {
    if (currentTrack == null) return;
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
    _cancelFade();
    final next = _nextOrderPos(_pos);
    if (next == null) return;
    _pos = next;
    await _loadCurrentAndPlay(_lead);
    _recordRecent(currentTrack!);
    notifyListeners();
  }

  Future<void> skipPrevious() async {
    _cancelFade();
    if (_lead.position > const Duration(seconds: 3)) {
      await _lead.seek(Duration.zero);
      return;
    }
    if (_pos > 0) {
      _pos--;
      await _loadCurrentAndPlay(_lead);
      _recordRecent(currentTrack!);
      notifyListeners();
    }
  }

  Future<void> seek(Duration target) async {
    _cancelFade();
    await _lead.seek(target);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    // Durante un fundido la rampa converge a `_volume`; no clobberear el cruce.
    if (!_fading) {
      await _lead.setVolume(_volume);
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
    _settings.removeListener(_onSettingsChanged);
    _a.dispose();
    _b.dispose();
    super.dispose();
  }
}