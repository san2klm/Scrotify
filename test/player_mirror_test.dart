import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/remote_playback.dart';
import 'package:navidrome_client/services/settings_controller.dart';

import 'support/app_fakes.dart';

Track track(String id) => Track(
    id: id,
    title: 'Title $id',
    artist: 'Artist',
    album: 'Album',
    duration: '180');

class FakeRemote extends ChangeNotifier implements RemotePlayback {
  @override
  bool active = false;
  @override
  List<Track> queue = [track('r1'), track('r2'), track('r3')];
  @override
  int index = 1;
  @override
  bool playing = true;
  @override
  Duration position = const Duration(seconds: 42);
  @override
  Duration? duration = const Duration(seconds: 180);
  @override
  double volume = 0.3;
  @override
  bool shuffle = true;
  @override
  LoopMode repeat = LoopMode.all;
  final calls = <String>[];

  @override
  void playQueue(List<Track> tracks, int startIndex, {bool shuffle = false}) =>
      calls.add('playQueue:${tracks.length}:$startIndex:$shuffle');
  @override
  void addToQueue(Track t) => calls.add('add:${t.id}');
  @override
  void addNext(Track t) => calls.add('next:${t.id}');
  @override
  void removeFromQueue(int i) => calls.add('remove:$i');
  @override
  void reorderQueue(int a, int b) => calls.add('move:$a:$b');
  @override
  void clearQueue() => calls.add('clear');
  @override
  void toggle() => calls.add('toggle');
  @override
  void play() => calls.add('play');
  @override
  void pause() => calls.add('pause');
  @override
  void next() => calls.add('skipNext');
  @override
  void previous() => calls.add('skipPrevious');
  @override
  void seek(Duration t) => calls.add('seek:${t.inSeconds}');
  @override
  void setVolume(double v) => calls.add('volume:$v');
  @override
  void toggleShuffle() => calls.add('shuffle');
  @override
  void toggleRepeat() => calls.add('repeat');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlayerController player;
  late FakeRemote remote;

  setUp(() {
    player = PlayerController(FakeNavidrome(), SettingsController());
    remote = FakeRemote();
    player.remote = remote;
    player.setQueueForTesting([track('l1'), track('l2')]);
  });

  test('sin remoto activo todo es local', () {
    expect(player.isMirroring, isFalse);
    expect(player.queue.map((t) => t.id), ['l1', 'l2']);
    expect(player.currentTrack, isNull);
  });

  test('con remoto activo la cola y el estado son los del remoto', () {
    remote.active = true;
    expect(player.isMirroring, isTrue);
    expect(player.currentTrack?.id, 'r2');
    expect(player.orderedQueue.map((t) => t.id), ['r1', 'r2', 'r3']);
    expect(player.currentOrderPos, 1);
    expect(player.playing, isTrue);
    expect(player.position, const Duration(seconds: 42));
    expect(player.duration, const Duration(seconds: 180));
    expect(player.volume, 0.3);
    expect(player.shuffleEnabled, isTrue);
    expect(player.repeatMode, LoopMode.all);
  });

  test('las acciones del usuario se envían al remoto', () async {
    remote.active = true;
    await player.togglePlay();
    await player.skipNext();
    await player.skipPrevious();
    await player.seek(const Duration(seconds: 90));
    await player.setVolume(1.5); // se acota a 1.0
    await player.toggleShuffle();
    await player.toggleRepeat();
    await player.playQueue([track('a'), track('b')], startIndex: 1);
    await player.playShuffledQueue([track('a'), track('b')]);
    await player.addToQueue(track('x'));
    await player.addNextInQueue(track('y'));
    player.removeFromQueue(2);
    player.reorderQueue(0, 2);
    player.clearQueue();
    expect(remote.calls, [
      'toggle',
      'skipNext',
      'skipPrevious',
      'seek:90',
      'volume:1.0',
      'shuffle',
      'repeat',
      'playQueue:2:1:false',
      remote.calls[8], // playShuffled: inicio aleatorio, mezcla activada
      'add:x',
      'next:y',
      'remove:2',
      'move:0:2',
      'clear',
    ]);
    expect(remote.calls[8], matches(r'^playQueue:2:[01]:true$'));
    // Lo local no se tocó.
    expect(
        player.readLocally(() => player.queue.map((t) => t.id)), ['l1', 'l2']);
  });

  test('runLocally y readLocally ignoran el modo espejo', () async {
    remote.active = true;
    expect(player.readLocally(() => player.queue.length), 2);
    expect(player.readLocally(() => player.repeatMode), LoopMode.off);
    await player.runLocally(() async {
      await player.toggleRepeat();
    });
    expect(remote.calls, isEmpty);
    expect(player.readLocally(() => player.repeatMode), LoopMode.all);
  });

  test('los streams cambian de local a remoto sin resuscribirse', () async {
    final positions = <Duration>[];
    final sub = player.positionStream.listen(positions.add);
    remote.active = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(positions, contains(const Duration(seconds: 42)));
    await sub.cancel();
  });

  test('el controlador avisa a la UI cuando cambia el remoto', () {
    var notified = 0;
    player.addListener(() => notified++);
    remote.active = true;
    remote.notifyListeners();
    expect(notified, greaterThanOrEqualTo(1));
  });
}
