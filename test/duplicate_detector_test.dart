import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/duplicate_detector.dart';

void main() {
  group('DuplicateDetector', () {
    final track1 = Track(
      id: 't1',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      duration: '354',
    );
    final track1ExactDuplicate = Track(
      id: 't1',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      duration: '354',
    );
    final track1Remaster = Track(
      id: 't1_remaster',
      title: 'Bohemian Rhapsody (2011 Remaster)',
      artist: 'Queen',
      album: 'Greatest Hits',
      duration: '355',
    );
    final track2 = Track(
      id: 't2',
      title: 'Hotel California',
      artist: 'Eagles',
      album: 'Hotel California',
      duration: '391',
    );
    final track2Deluxe = Track(
      id: 't2_deluxe',
      title: 'Hotel California - 2013 Remaster',
      artist: 'The Eagles',
      album: 'Hotel California (40th Anniversary)',
      duration: '391',
    );
    final track3 = Track(
      id: 't3',
      title: 'Stairway to Heaven',
      artist: 'Led Zeppelin',
      album: 'Led Zeppelin IV',
      duration: '482',
    );

    test('returns empty duplicate list when tracks are all distinct', () {
      final tracks = [track1, track2, track3];
      final duplicates = DuplicateDetector.findDuplicates(tracks);
      expect(duplicates, isEmpty);
      expect(DuplicateDetector.findDuplicateIndicesToRemove(tracks), isEmpty);
      expect(DuplicateDetector.deduplicate(tracks), equals(tracks));
    });

    test('detects exact ID duplicates', () {
      final tracks = [track1, track2, track1ExactDuplicate, track3];
      final duplicates = DuplicateDetector.findDuplicates(
        tracks,
        matchMetadata: false,
      );

      expect(duplicates.length, equals(1));
      expect(duplicates.first.tracks.length, equals(2));
      expect(duplicates.first.indices, equals([0, 2]));

      final indicesToRemove = DuplicateDetector.findDuplicateIndicesToRemove(
        tracks,
        matchMetadata: false,
      );
      expect(indicesToRemove, equals({2}));

      final clean = DuplicateDetector.deduplicate(tracks, matchMetadata: false);
      expect(clean.map((t) => t.id).toList(), equals(['t1', 't2', 't3']));
    });

    test('detects fuzzy metadata duplicates (remasters, casing, accents)', () {
      final tracks = [track1, track2, track1Remaster, track2Deluxe, track3];
      final duplicates = DuplicateDetector.findDuplicates(
        tracks,
        matchMetadata: true,
      );

      expect(duplicates.length, equals(2));

      final queenGroup = duplicates.firstWhere(
        (g) => g.canonicalArtist.contains('queen'),
      );
      expect(queenGroup.tracks.length, equals(2));
      expect(queenGroup.indices, equals([0, 2]));

      final eaglesGroup = duplicates.firstWhere(
        (g) => g.canonicalArtist.contains('eagles'),
      );
      expect(eaglesGroup.tracks.length, equals(2));
      expect(eaglesGroup.indices, equals([1, 3]));

      final indicesToRemove = DuplicateDetector.findDuplicateIndicesToRemove(
        tracks,
        matchMetadata: true,
      );
      expect(indicesToRemove, equals({2, 3}));

      final clean = DuplicateDetector.deduplicate(tracks, matchMetadata: true);
      expect(clean.length, equals(3));
      expect(clean[0].id, equals('t1'));
      expect(clean[1].id, equals('t2'));
      expect(clean[2].id, equals('t3'));
    });

    test('handles empty and single-item track lists gracefully', () {
      expect(DuplicateDetector.findDuplicates([]), isEmpty);
      expect(DuplicateDetector.deduplicate([]), isEmpty);
      expect(DuplicateDetector.findDuplicateIndicesToRemove([]), isEmpty);

      expect(DuplicateDetector.findDuplicates([track1]), isEmpty);
      expect(DuplicateDetector.deduplicate([track1]), equals([track1]));
      expect(DuplicateDetector.findDuplicateIndicesToRemove([track1]), isEmpty);
    });
  });
}
