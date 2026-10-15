import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
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

class _TestNavidrome extends FakeNavidrome {
  @override
  String getPlaybackStreamUrl(String trackId, {AudioQuality? quality}) =>
      'https://example.com/stream/$trackId';
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

  group('Song Radio - PlayerController.playRadio', () {
    test('arma la cola con la semilla y las similares sin duplicados', () async {
      final player = PlayerController(_TestNavidrome(), SettingsController());
      addTearDown(player.dispose);

      await player.playRadio(seedTrack, [similar1, similar2, seedTrack]);

      expect(player.queue.length, 3);
      expect(player.queue[0].id, 'seed_1');
      expect(player.queue[1].id, 'sim_1');
      expect(player.queue[2].id, 'sim_2');
      expect(player.sourcePlaylist, isNotNull);
      expect(player.sourcePlaylist!.id, 'radio_seed_1');
      expect(player.sourcePlaylist!.name, 'Radio: Imposible');
    });

    test('reemplaza la cola fluidamente si la pista semilla ya estaba en reproducción',
        () async {
      final player = PlayerController(_TestNavidrome(), SettingsController());
      addTearDown(player.dispose);

      // Cargamos y reproducimos la pista semilla
      await player.playQueue([seedTrack], startIndex: 0);
      expect(player.currentTrack?.id, 'seed_1');

      // Iniciamos el modo Radio con la misma canción
      await player.playRadio(seedTrack, [similar1, similar2]);

      expect(player.queue.length, 3);
      expect(player.currentTrack?.id, 'seed_1');
      expect(player.sourcePlaylist?.id, 'radio_seed_1');
      expect(player.orderedQueue[1].id, 'sim_1');
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
