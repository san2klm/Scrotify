import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/discovery_policy.dart';
import 'package:crotowave/services/listening_stats_service.dart';
import 'package:crotowave/services/navidrome_service.dart';

Track song(String id, String artist, {String? title, String? mbid}) => Track(
    id: id,
    title: title ?? id,
    artist: artist,
    album: 'Album',
    duration: '200',
    mbid: mbid);
ListeningEvent play(String artist, DateTime at, {String id = 'played'}) =>
    ListeningEvent(
        trackId: id,
        title: id,
        artist: artist,
        album: 'Album',
        durationSeconds: 200,
        timestamp: at);

void main() {
  test('recommendations retain only playable catalogue tracks and original IDs',
      () {
    final library = [
      song('one', 'A'),
      song('two', 'B'),
      song('discovery:external', 'C')
    ];
    final result = recommendNavidromeTracks(
        library: library, events: [], now: DateTime(2026));
    expect(result.map((r) => r.track.id), ['one', 'two']);
    expect(identical(result.first.track, library.first), isTrue);
  });
  test(
      'recent listening influences artist affinity without repeating recent songs first',
      () {
    final now = DateTime(2026, 10, 16);
    final result = recommendNavidromeTracks(library: [
      song('new', 'Favourite'),
      song('played', 'Favourite'),
      song('other', 'Other')
    ], events: List.generate(5, (_) => play('Favourite', now)), now: now);
    expect(result.first.track.id, 'new');
  });
  test('remasters, accents and identical recording IDs do not repeat', () {
    final result = recommendNavidromeTracks(library: [
      song('1', 'Björk', title: 'Human Behaviour'),
      song('2', 'Bjork', title: 'Human Behaviour (2015 Remastered)'),
      song('3', 'Other', mbid: 'same'),
      song('4', 'Other', title: 'Alias', mbid: 'same')
    ], events: [], now: DateTime(2026));
    expect(result, hasLength(2));
  });
  test('a small single artist catalogue still fills the section', () {
    final result = recommendNavidromeTracks(
        library: List.generate(8, (i) => song('$i', 'Only artist')),
        events: [],
        now: DateTime(2026));
    expect(result, hasLength(8));
  });
}
