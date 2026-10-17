import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/crotolink_track_resolver.dart';
import 'package:crotowave/services/navidrome_service.dart';

Track t(String id, String title, String artist,
        {String duration = '200', String album = 'A'}) =>
    Track(
        id: id, title: title, artist: artist, album: album, duration: duration);

void main() {
  late List<Track> library;
  late int searches;
  late int getSongs;
  late CrotoLinkTrackResolver resolver;

  setUp(() {
    searches = 0;
    getSongs = 0;
    library = [
      t('L1', 'Cancion', 'Beyonce', duration: '202'),
      t('L2', 'Hello', 'Lionel Richie'),
    ];
    resolver = CrotoLinkTrackResolver(
      getSong: (id) async {
        getSongs++;
        final i = library.indexWhere((x) => x.id == id);
        return i < 0 ? null : library[i];
      },
      searchSongs: (q) async {
        searches++;
        final needle = q.toLowerCase();
        return library
            .where(
                (x) => needle.contains(x.title.toLowerCase().substring(0, 3)))
            .toList();
      },
    );
  });

  test('fast path: same id + same metadata resolves without searching',
      () async {
    final r = await resolver.resolve(t('L2', 'Hello', 'Lionel Richie'));
    expect(r.isAvailable, isTrue);
    expect(r.track!.id, 'L2');
    expect(searches, 0);
  });

  test('same id but different song (other server reused the id) is not trusted',
      () async {
    final r = await resolver.resolve(t('L2', 'Hello', 'Adele'));
    expect(r.isAvailable, isFalse);
  });

  test('cross-server match by normalized metadata', () async {
    final r = await resolver.resolve(t(
        'REMOTE9', 'Canción (feat. Ana) - 2015 Remaster', 'Beyoncé',
        duration: '201'));
    expect(r.isAvailable, isTrue);
    expect(r.track!.id, 'L1');
  });

  test('homonymous song by another artist is unavailable', () async {
    final r = await resolver.resolve(t('R1', 'Hello', 'Adele'));
    expect(r.isAvailable, isFalse);
  });

  test('results are cached (also negatives) and in-flight calls are shared',
      () async {
    final remote = t('R1', 'Hello', 'Adele');
    await Future.wait([resolver.resolve(remote), resolver.resolve(remote)]);
    final firstSearches = searches;
    await resolver.resolve(remote);
    expect(searches, firstSearches);
    expect(resolver.cached('R1')!.isAvailable, isFalse);
    expect(getSongs, 1);
  });

  test('network errors propagate and are not cached as "unavailable"',
      () async {
    var fail = true;
    final r = CrotoLinkTrackResolver(
      getSong: (_) async => null,
      searchSongs: (_) async {
        if (fail) throw Exception('offline');
        return library;
      },
    );
    await expectLater(
        r.resolve(t('Z', 'Hello', 'Lionel Richie')), throwsException);
    expect(r.cached('Z'), isNull);
    fail = false;
    expect((await r.resolve(t('Z', 'Hello', 'Lionel Richie'))).isAvailable,
        isTrue);
  });

  test('resolveBatch of 100 tracks yields to the event loop between batches',
      () async {
    final tracks = [
      for (var i = 0; i < 100; i++)
        t('R$i', 'Cancion', 'Beyonce', duration: '202')
    ];
    var progress = 0;
    var ticks = 0;
    final ticker = Future(() async {
      while (progress < 25) {
        await Future<void>.delayed(Duration.zero);
        ticks++;
      }
    });
    await resolver.resolveBatch(tracks, onProgress: () => progress++);
    await ticker;
    expect(progress, 25);
    expect(ticks, greaterThan(0));
    expect(tracks.every((x) => resolver.cached(x.id)!.isAvailable), isTrue);
  });
}
