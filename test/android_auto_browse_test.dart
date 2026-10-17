import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/crotowave_audio_handler.dart';

import 'crotowave_audio_handler_test.dart' show FakePlayerController;

Track t(String id) =>
    Track(id: id, title: 'T$id', artist: 'A', album: 'B', duration: '120');

class _BrowsePlayer extends FakePlayerController {
  final played = <String>[];
  int startIndex = -1;

  List<Track>? recentlyPlayedOverride;

  @override
  List<Track> get recentlyPlayed =>
      recentlyPlayedOverride ?? [t('r1'), t('r2')];

  @override
  List<MostPlayedItem> get mostPlayed =>
      [MostPlayedItem.track(t('m1'), playCount: 5)];

  @override
  Future<void> playQueue(List<Track> tracks,
      {int startIndex = 0, Playlist? sourcePlaylist}) async {
    played
      ..clear()
      ..addAll(tracks.map((e) => e.id));
    this.startIndex = startIndex;
  }
}

void main() {
  late CrotoWaveAudioHandler handler;
  late _BrowsePlayer player;

  setUp(() {
    handler = CrotoWaveAudioHandler()
      ..playlistsLoader = (() async => [
            Playlist(id: 'p1', name: 'Rock', songCount: 2, duration: 200),
          ])
      ..playlistTracksLoader = (id) async => [t('x1'), t('x2')];
    player = _BrowsePlayer();
    handler.attachPlayerController(player);
  });

  test('la raíz ofrece Recientes, Más escuchadas y Playlists', () async {
    final root = await handler.getChildren(AudioService.browsableRootId);
    expect(root.map((e) => e.id), ['recents', 'mostPlayed', 'playlists']);
    expect(root.every((e) => e.playable == false), isTrue);
  });

  test('las carpetas listan pistas reproducibles', () async {
    final recents = await handler.getChildren('recents');
    expect(recents.map((e) => e.id), ['track:r1', 'track:r2']);
    expect(recents.every((e) => e.playable == true), isTrue);

    final most = await handler.getChildren('mostPlayed');
    expect(most.single.id, 'track:m1');

    final lists = await handler.getChildren('playlists');
    expect(lists.single.id, 'playlist:p1');
    expect(lists.single.title, 'Rock');

    final tracks = await handler.getChildren('playlist:p1');
    expect(tracks.map((e) => e.id), ['track:x1', 'track:x2']);
  });

  test('reproducir una pista usa la carpeta abierta como cola', () async {
    await handler.getChildren('playlist:p1');
    await handler.playFromMediaId('track:x2');
    expect(player.played, ['x1', 'x2']);
    expect(player.startIndex, 1);
  });

  test('un id desconocido no hace nada', () async {
    await handler.playFromMediaId('track:no-existe');
    await handler.playFromMediaId('otra-cosa');
    expect(player.played, isEmpty);
    expect(await handler.getChildren('desconocido'), isEmpty);
  });

  test('las URLs de carátula remotas con credenciales no se publican',
      () async {
    final item = Track(
        id: 'c',
        title: 'C',
        artist: 'A',
        album: 'B',
        duration: '10',
        albumArtUrl: 'https://s.example.invalid/c?u=ana&t=secreto&s=sal');
    player.recentlyPlayedOverride = [item];
    final out = await handler.getChildren('recents');
    expect(out.single.artUri, isNull);
  });
}
