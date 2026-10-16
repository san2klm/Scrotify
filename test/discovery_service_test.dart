import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/discovery_service.dart';
import 'package:navidrome_client/services/listening_stats_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

Track song(String id, String artist) =>
    Track(id: id, title: id, artist: artist, album: 'Album', duration: '200');

class _Nav extends NavidromeService {
  String user = 'alice';
  bool online = true;
  int reads = 0;
  Future<List<Track>> Function()? fetch;
  List<Track> library = [
    song('alice-track', 'Alice artist'),
    song('bob-track', 'Bob artist')
  ];
  @override
  bool get connected => online;
  @override
  bool get offlineMode => !online;
  @override
  String? get currentSessionKey => online ? 'server|$user#0' : null;
  @override
  String? get serverUrl => 'server';
  @override
  String? get username => user;
  @override
  Future<List<Track>> getDownloadRecoveryCatalog(
      {bool forceRefresh = false}) async {
    reads++;
    return fetch == null ? library : await fetch!();
  }

  void switchUser(String value) {
    user = value;
    notifyListeners();
  }
}

class _Stats extends ListeningStatsService {
  final events = <ListeningEvent>[];
  @override
  List<ListeningEvent> get allEvents => List.unmodifiable(events);
  void add(String artist, String? scope) {
    events.add(ListeningEvent(
        trackId: 'previous',
        title: 'Previous',
        artist: artist,
        album: 'Album',
        durationSeconds: 200,
        timestamp: DateTime.now(),
        serverScope: scope));
    notifyListeners();
  }
}

void main() {
  test('each account ranks its own exact scoped listening history', () async {
    final nav = _Nav();
    final stats = _Stats();
    final service = DiscoveryService(nav, stats);
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    stats.add('Alice artist', 'server|alice');
    for (var i = 0; i < 10; i++) {
      stats.add('Bob artist', 'server|bob');
      stats.add('Bob artist', null);
    }
    await service.refresh();
    expect(service.recommendations.first.track.id, 'alice-track');
    nav.switchUser('bob');
    await service.refresh();
    expect(service.recommendations.first.track.id, 'bob-track');
  });
  test('late catalogue response cannot cross accounts', () async {
    final nav = _Nav();
    final stats = _Stats();
    final service = DiscoveryService(nav, stats);
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    final old = Completer<List<Track>>();
    nav.fetch = () => old.future;
    final pending = service.refresh();
    nav.switchUser('bob');
    nav.fetch = () async => [song('bob-only', 'B')];
    await service.refresh();
    old.complete([song('alice-only', 'A')]);
    await pending;
    expect(service.recommendations.single.track.id, 'bob-only');
  });
  test('full catalogue includes recommendations after the first 500', () async {
    final nav = _Nav()
      ..library = List.generate(
          501, (i) => song('$i', i == 500 ? 'Favourite' : 'Other'));
    final stats = _Stats()..add('Favourite', 'server|alice');
    final service = DiscoveryService(nav, stats);
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    await service.refresh();
    expect(service.recommendations.first.track.id, '500');
  });
  test(
      'qualified plays refresh ranking without downloading the catalogue again',
      () async {
    final nav = _Nav();
    final stats = _Stats();
    final service = DiscoveryService(nav, stats, debounce: Duration.zero);
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    service.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    stats.add('Bob artist', 'server|alice');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(nav.reads, 1);
    expect(service.recommendations.first.track.id, 'bob-track');
  });
  test('catalogue errors are visible and do not produce external results',
      () async {
    final nav = _Nav()..fetch = () async => throw StateError('offline');
    final stats = _Stats();
    final service = DiscoveryService(nav, stats);
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    await service.refresh();
    expect(service.error, isNotNull);
    expect(service.recommendations, isEmpty);
  });
}
