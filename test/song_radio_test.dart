import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/remote_playback.dart';
import 'package:navidrome_client/services/settings_controller.dart';

import 'support/app_fakes.dart';

class _FakeLocalMusic extends LocalMusicService {
  final List<Track> tracks;
  _FakeLocalMusic(this.tracks)
      : super(OfflineCacheService(
          cacheRootDir: Directory.systemTemp,
          metadataStore: InMemoryOfflineCacheMetadataStore(),
        ));

  @override
  List<Track> downloadedTracks(String? scope) => tracks;
}

class FakeRemoteRadio extends FakeRemote {
  List<Track>? lastQueue;
  int? lastStartIndex;

  @override
  void playQueue(List<Track> tracks, int startIndex, {bool shuffle = false}) {
    super.playQueue(tracks, startIndex, shuffle: shuffle);
    lastQueue = List.of(tracks);
    lastStartIndex = startIndex;
  }
}

class FakeRemote extends ChangeNotifier implements RemotePlayback {
  @override
  bool active = false;
  @override
  List<Track> queue = [];
  @override
  int index = 0;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration = Duration.zero;
  @override
  double volume = 0.5;
  @override
  bool shuffle = false;
  @override
  LoopMode repeat = LoopMode.off;

  @override
  void playQueue(List<Track> tracks, int startIndex, {bool shuffle = false}) {}
  @override
  void addToQueue(Track t) {}
  @override
  void addNext(Track t) {}
  @override
  void removeFromQueue(int i) {}
  @override
  void reorderQueue(int a, int b) {}
  @override
  void clearQueue() {}
  @override
  void toggle() {}
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void next() {}
  @override
  void previous() {}
  @override
  void seek(Duration t) {}
  @override
  void setVolume(double v) {}
  @override
  void toggleShuffle() {}
  @override
  void toggleRepeat() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final seedTrack = Track(
    id: 'seed_1',
    title: 'Imposible',
    artist: 'Callejeros',
    album: 'Sed',
    duration: '240',
    genre: 'Rock',
  );

  final sameArtistTrack = Track(
    id: 'same_art_1',
    title: 'Una Nueva Noche Fría',
    artist: 'Callejeros',
    album: 'Presión',
    duration: '300',
    genre: 'Rock',
  );

  final similar1 = Track(
    id: 'sim_1',
    title: 'Reyes de la Noche',
    artist: 'Guasones',
    album: 'Toro Rojo',
    duration: '210',
    genre: 'Rock',
  );

  final similar2 = Track(
    id: 'sim_2',
    title: 'Todo Pasa',
    artist: 'Los Piojos',
    album: '3er Arco',
    duration: '270',
    genre: 'Rock',
  );

  final otherTrack = Track(
    id: 'pop_1',
    title: 'Pop Hit',
    artist: 'Pop Star',
    album: 'Pop Hits',
    duration: '180',
    genre: 'Pop',
  );

  group('Song Radio - PlayerController.playRadio (Mirror / Remote)', () {
    test('en modo remoto/mirror delega la cola completa con la semilla en index 0',
        () async {
      final player = PlayerController(FakeNavidrome(), SettingsController());
      final remote = FakeRemoteRadio();
      player.remote = remote;
      remote.active = true;

      await player.playRadio(seedTrack, [similar1, similar2, seedTrack]);

      expect(remote.lastQueue, isNotNull);
      expect(remote.lastQueue!.length, 3);
      expect(remote.lastQueue![0].id, 'seed_1');
      expect(remote.lastQueue![1].id, 'sim_1');
      expect(remote.lastQueue![2].id, 'sim_2');
      expect(remote.lastStartIndex, 0);
    });
  });

  group('Song Radio - NavidromeService getSimilarSongs (Offline fallback)', () {
    late NavidromeService navService;
    late _FakeLocalMusic fakeLocal;

    setUp(() {
      fakeLocal = _FakeLocalMusic([
        seedTrack,
        sameArtistTrack,
        similar1,
        similar2,
        otherTrack,
      ]);
      navService = NavidromeService();
      navService.localMusic = fakeLocal;
    });

    tearDown(() {
      navService.dispose();
    });

    test('obtiene canciones offline del mismo artista y género excluyendo la semilla',
        () async {
      final radioTracks =
          await navService.getSimilarSongs(seedTrack, count: 10);

      expect(radioTracks, isNotEmpty);
      expect(radioTracks.any((t) => t.id == seedTrack.id), isFalse);
      expect(radioTracks.any((t) => t.id == 'same_art_1'), isTrue);
      expect(radioTracks.any((t) => t.id == 'sim_1'), isTrue);
    });

    test('getRandomSongs offline devuelve canciones del género o aleatorias',
        () async {
      final popTracks = await navService.getRandomSongs(size: 10, genre: 'Pop');
      expect(popTracks.length, 1);
      expect(popTracks.first.id, 'pop_1');
    });
  });
}
