import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'navidrome_service.dart';

/// Reproductor de otro dispositivo al que esta app está haciendo de mando
/// (Scrotify Connect). Mientras [active], `PlayerController` actúa de espejo:
/// muestra la cola y el estado del dispositivo remoto y envía allí cada
/// acción (reproducir, encolar, reordenar, pausar…).
abstract class RemotePlayback implements Listenable {
  bool get active;

  /// Cola del dispositivo remoto en orden de reproducción (una ventana
  /// alrededor de la canción actual) y posición de la actual dentro de ella.
  List<Track> get queue;
  int get index;

  bool get playing;
  Duration get position;
  Duration? get duration;
  double get volume;
  bool get shuffle;
  LoopMode get repeat;

  void playQueue(List<Track> tracks, int startIndex, {bool shuffle = false});
  void addToQueue(Track track);
  void addNext(Track track);
  void removeFromQueue(int orderIndex);
  void reorderQueue(int oldIndex, int newIndex);
  void clearQueue();
  void toggle();
  void play();
  void pause();
  void next();
  void previous();
  void seek(Duration target);
  void setVolume(double volume);
  void toggleShuffle();
  void toggleRepeat();
}
