import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Reproductor falso para probar la cola sin motor de audio.
///
/// Solo implementa lo que usa `PlayerController`; cualquier otro miembro
/// lanza `UnimplementedError` (vía `Fake`).
class FakeAudioPlayer extends Fake implements AudioPlayer {
  FakeAudioPlayer(this.name);

  final String name;
  final loaded = <String>[];
  final _state = StreamController<PlayerState>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _volumeController = StreamController<double>.broadcast();

  bool _playing = false;
  double _volume = 1;
  Duration _pos = Duration.zero;
  final Duration _dur = const Duration(minutes: 3);
  ProcessingState _processing = ProcessingState.idle;

  /// Emite una posición como lo haría el motor de audio.
  void emitPosition(Duration d) {
    _pos = d;
    _position.add(d);
  }

  /// Fuente cargada en último lugar (URI de la pista).
  String? get currentUri => loaded.isEmpty ? null : loaded.last;

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    final uri = source is UriAudioSource ? source.uri.toString() : '$source';
    loaded.add(uri);
    _processing = ProcessingState.ready;
    _pos = Duration.zero;
    _state.add(PlayerState(_playing, _processing));
    return _dur;
  }

  @override
  Future<void> play() async {
    _playing = true;
    _state.add(PlayerState(true, _processing));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _state.add(PlayerState(false, _processing));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _processing = ProcessingState.idle;
    _state.add(PlayerState(false, _processing));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _pos = position ?? Duration.zero;
    _position.add(_pos);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    _volumeController.add(volume);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {
    await _state.close();
    await _position.close();
    await _duration.close();
    await _volumeController.close();
  }

  @override
  bool get playing => _playing;
  @override
  double get volume => _volume;
  @override
  Duration get position => _pos;
  @override
  Duration? get duration => _dur;
  @override
  ProcessingState get processingState => _processing;
  @override
  PlayerState get playerState => PlayerState(_playing, _processing);
  @override
  Stream<PlayerState> get playerStateStream => _state.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<double> get volumeStream => _volumeController.stream;
}
