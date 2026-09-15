import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';
import 'settings_controller.dart';

/// Estado global de reproducción. Persiste entre pantallas y alimenta el
/// panel de control persistente (barra inferior).
///
/// El [AudioPlayer] vive aquí (único en toda la app), de modo que cambiar de
/// pantalla no interrumpe la reproducción.
class PlayerController extends ChangeNotifier {
  final NavidromeService _service;
  final SettingsController _settings;

  // Última calidad efectiva aplicada, para recargar la canción en curso solo
  // cuando la calidad realmente cambió (p. ej. al pasar de WiFi a móvil).
  AudioQuality _lastAppliedQuality = AudioQuality.lossless;

  PlayerController(this._service, this._settings) {
    _listen();
    _loadHistory();
    _lastAppliedQuality = _settings.effectiveQuality;
    _settings.addListener(_onSettingsChanged);
  }

  final AudioPlayer _player = AudioPlayer();

  List<Track> _queue = [];
  int _currentIndex = -1;

  // Historial de escuchas recientes (más reciente primero), persistido y con
  // un máximo de 50 entradas para no crecer indefinidamente.
  List<Track> _recentlyPlayed = [];

  bool _shuffleEnabled = false;
  LoopMode _repeatMode = LoopMode.off;

  List<Track> get queue => List.unmodifiable(_queue);
  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);
  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;
  bool get hasTrack => currentTrack != null;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<double> get volumeStream => _player.volumeStream;

  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get repeatMode => _repeatMode;
  bool get playing => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get volume => _player.volume;
  bool get gapless => _settings.gapless;

  void _listen() {
    _player.playerStateStream.listen((state) {
      notifyListeners();
      if (state.processingState == ProcessingState.completed) {
        _onCompleted();
      }
    });
    _player.currentIndexStream.listen((index) {
      // Mantener `_currentIndex` sincronizado con el índice real del audio.
      // Si no se actualiza, la barra/reproductor muestran siempre la primera
      // canción de la cola aunque el audio ya haya avanzado a otra.
      if (index != null && index >= 0 && index < _queue.length) {
        _currentIndex = index;
        _recordRecent(_queue[index]);
      }
      notifyListeners();
    });
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
      await file.writeAsString(jsonEncode(_recentlyPlayed.map(_trackToJson).toList()));
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

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _currentIndex = startIndex < tracks.length ? startIndex : 0;

    final service = _service;
    final quality = _settings.effectiveQuality;
    final sources = <AudioSource>[
      for (final t in _queue)
        AudioSource.uri(
            Uri.parse(service.getStreamUrl(t.id, quality: quality))),
    ];

    await _player.stop();
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: _currentIndex,
    );
    await _player.setShuffleModeEnabled(false);
    await _player.setLoopMode(_repeatMode);
    await _player.play();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cambios de configuración (calidad, volumen)
  // ---------------------------------------------------------------------------

  void _onSettingsChanged() {
    final q = _settings.effectiveQuality;
    if (q != _lastAppliedQuality) {
      _lastAppliedQuality = q;
      _reloadAtQuality();
    }
    // El volumen inicial se aplica al arrancar y de nuevo si el usuario lo
    // ajusta en Ajustes (feedback inmediato con la canción sonando).
    _player.setVolume(_settings.initialVolume);
  }

  /// Recarga la cola completa con la calidad nueva preservando la posición y
  /// el estado de reproducción. Deja de sonar un instante (cambio de fuente).
  Future<void> _reloadAtQuality() async {
    final index = _currentIndex;
    if (index < 0 || index >= _queue.length) return;
    final wasPlaying = _player.playing;
    final position = _player.position;

    final service = _service;
    final quality = _settings.effectiveQuality;
    final sources = <AudioSource>[
      for (final t in _queue)
        AudioSource.uri(
            Uri.parse(service.getStreamUrl(t.id, quality: quality))),
    ];

    try {
      await _player.stop();
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: index,
      );
      await _player.seek(position);
      await _player.setLoopMode(_repeatMode);
      await _player.setShuffleModeEnabled(_shuffleEnabled);
      if (wasPlaying) await _player.play();
    } catch (_) {
      // Si la recarga falla (p. ej. sin conexión), no matamos la sesión.
    }
    notifyListeners();
  }

  void _onCompleted() {
    if (_repeatMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_player.hasNext) {
      _player.seekToNext();
    } else if (_repeatMode == LoopMode.all && _queue.isNotEmpty) {
      _player.seek(Duration.zero, index: 0);
      _player.play();
    }
  }

  Future<void> togglePlay() async {
    if (currentTrack == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero, index: 0);
      }
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  Future<void> skipPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());
  }

  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    await _player.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    _repeatMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(_repeatMode);
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}