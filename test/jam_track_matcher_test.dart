import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/jam_track_matcher.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

Track t(String title, String artist,
        {String album = 'A', String duration = '200', String? mbid, String? isrc, String id = 'x'}) =>
    Track(id: id, title: title, artist: artist, album: album, duration: duration, mbid: mbid, isrc: isrc);

void main() {
  group('normalizeTitle', () {
    test('accents, case, punctuation', () {
      expect(normalizeTitle('Canción de Amor!'), 'cancion de amor');
    });
    test('strips feat./remaster noise but keeps recording-defining tags', () {
      expect(normalizeTitle('Song (feat. Someone)'), 'song');
      expect(normalizeTitle('Song [Remastered 2011]'), 'song');
      expect(normalizeTitle('Song - 2011 Remaster'), 'song');
      expect(normalizeTitle('Song - Remastered 2009'), 'song');
      expect(normalizeTitle('Song feat. Someone'), 'song');
      expect(normalizeTitle('Song (Live)'), 'song live');
      expect(normalizeTitle('Song (Acoustic)'), 'song acoustic');
      expect(normalizeTitle('Song (Remix)'), 'song remix');
    });
  });

  group('normalizeArtists', () {
    test('splits collaborations', () {
      expect(normalizeArtists('Beyoncé feat. Jay-Z & Kanye'), {'beyonce', 'jay z', 'kanye'});
      expect(normalizeArtists('Earth, Wind & Fire'), {'earth', 'wind', 'fire'});
    });
  });

  group('pickBestMatch', () {
    test('same song across servers with remaster/feat/accents/duration drift', () {
      final remote = t('Canción (feat. Ana) - 2015 Remaster', 'Beyoncé', duration: '201');
      final local = t('Cancion', 'Beyonce', duration: '203', id: 'local1');
      final m = pickBestMatch(remote, [local])!;
      expect(m.track.id, 'local1');
      expect(m.kind, JamMatchKind.metadata);
    });

    test('collaboration listing matches primary artist', () {
      final m = pickBestMatch(t('Under Pressure', 'Queen'), [t('Under Pressure', 'Queen & David Bowie', id: 'q')]);
      expect(m?.track.id, 'q');
    });

    test('no false positives for homonymous songs by different artists', () {
      expect(pickBestMatch(t('Hello', 'Adele'), [t('Hello', 'Lionel Richie')]), isNull);
      expect(pickBestMatch(t('Angel', 'Massive Attack'), [t('Angel', 'Shaggy')]), isNull);
      expect(pickBestMatch(t('Pink', 'Aerosmith'), [t('Pink', 'Pink Floyd')]), isNull);
    });

    test('same title+artist but live/remix version is not the studio track', () {
      expect(pickBestMatch(t('Song', 'Band'), [t('Song (Live)', 'Band')]), isNull);
      expect(pickBestMatch(t('Song', 'Band'), [t('Song (Remix)', 'Band')]), isNull);
    });

    test('duration tolerance is ±3 s', () {
      expect(pickBestMatch(t('S', 'B', duration: '200'), [t('S', 'B', duration: '203')]), isNotNull);
      expect(pickBestMatch(t('S', 'B', duration: '200'), [t('S', 'B', duration: '204')]), isNull);
      // sin duración conocida: se confía en título+artista
      expect(pickBestMatch(t('S', 'B', duration: ''), [t('S', 'B', duration: '204')]), isNotNull);
    });

    test('MBID wins over metadata; ISRC next', () {
      final remote = t('Foo', 'Bar', mbid: 'abc', isrc: 'US123');
      final byMeta = t('Foo', 'Bar', id: 'meta');
      final byIsrc = t('Different Title', 'Other', isrc: 'us123', id: 'isrc');
      final byMbid = t('Another', 'Thing', mbid: 'ABC', id: 'mbid');
      expect(pickBestMatch(remote, [byMeta, byIsrc, byMbid])!.track.id, 'mbid');
      expect(pickBestMatch(remote, [byMeta, byIsrc])!.track.id, 'isrc');
      expect(pickBestMatch(remote, [byMeta])!.kind, JamMatchKind.metadata);
    });

    test('prefers same album, then closest duration', () {
      final remote = t('S', 'B', album: 'Greatest Hits', duration: '200');
      final best = pickBestMatch(remote, [
        t('S', 'B', album: 'Compilation', duration: '200', id: 'c'),
        t('S', 'B', album: 'Greatest Hits', duration: '202', id: 'g'),
      ])!;
      expect(best.track.id, 'g');
    });
  });
}
