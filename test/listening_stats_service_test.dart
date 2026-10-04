import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/listening_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ListeningStatsService', () {
    test('qualifiesForPlayCount evaluates thresholds correctly', () {
      // Completed always qualifies
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: Duration.zero,
          duration: const Duration(seconds: 120),
          completed: true,
        ),
        isTrue,
      );

      // Short tracks (< 60s): requires at least 50%
      const shortTrackDuration = Duration(seconds: 40);
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: const Duration(seconds: 19),
          duration: shortTrackDuration,
          completed: false,
        ),
        isFalse,
      );
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: const Duration(seconds: 20),
          duration: shortTrackDuration,
          completed: false,
        ),
        isTrue,
      );

      // Normal tracks (>= 60s): requires at least 30s
      const longTrackDuration = Duration(seconds: 240);
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: const Duration(seconds: 29),
          duration: longTrackDuration,
          completed: false,
        ),
        isFalse,
      );
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: const Duration(seconds: 30),
          duration: longTrackDuration,
          completed: false,
        ),
        isTrue,
      );

      // Unknown duration: fallback to 30s
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: const Duration(seconds: 29),
          duration: null,
          completed: false,
        ),
        isFalse,
      );
      expect(
        ListeningStatsService.qualifiesForPlayCount(
          position: const Duration(seconds: 30),
          duration: null,
          completed: false,
        ),
        isTrue,
      );
    });

    test('records plays and calculates aggregated metrics', () async {
      final stats = ListeningStatsService();

      await stats.recordPlay(
        trackId: 't1',
        title: 'Song One',
        artist: 'Artist Alpha',
        album: 'Album A',
        genre: 'Rock',
        durationSeconds: 180,
      );

      await stats.recordPlay(
        trackId: 't1',
        title: 'Song One',
        artist: 'Artist Alpha',
        album: 'Album A',
        genre: 'Rock',
        durationSeconds: 180,
      );

      await stats.recordPlay(
        trackId: 't2',
        title: 'Song Two',
        artist: 'Artist Beta',
        album: 'Album B',
        genre: 'Electronic',
        durationSeconds: 240,
      );

      expect(stats.getTotalPlayCount(), 3);
      expect(stats.getTotalListeningDuration(), const Duration(seconds: 600));

      final topTracks = stats.getTopTracks(limit: 5);
      expect(topTracks.length, 2);
      expect(topTracks.first.trackId, 't1');
      expect(topTracks.first.playCount, 2);
      expect(topTracks.first.totalDuration, const Duration(seconds: 360));

      final topArtists = stats.getTopArtists(limit: 5);
      expect(topArtists.length, 2);
      expect(topArtists.first.name, 'Artist Alpha');
      expect(topArtists.first.playCount, 2);

      final topGenres = stats.getTopGenres(limit: 5);
      expect(topGenres.length, 2);
      expect(topGenres.first.name, 'Rock');
      expect(topGenres.first.playCount, 2);
    });

    test('daily, weekly, and monthly time-series contain proper bins',
        () async {
      final stats = ListeningStatsService();
      final now = DateTime.now();

      await stats.recordPlay(
        trackId: 't1',
        title: 'Song One',
        artist: 'Artist Alpha',
        album: 'Album A',
        durationSeconds: 200,
        timestamp: now,
      );

      final daily = stats.getDailyListening(days: 7);
      expect(daily.length, 7);
      expect(daily.last.playCount, greaterThanOrEqualTo(1));

      final weekly = stats.getWeeklyListening(weeks: 4);
      expect(weekly.length, 4);
      expect(weekly.last.playCount, greaterThanOrEqualTo(1));

      final monthly = stats.getMonthlyListening(months: 6);
      expect(monthly.length, 6);
      expect(monthly.last.playCount, greaterThanOrEqualTo(1));
    });

    test('supports server/profile scope without deleting historical events',
        () async {
      final stats = ListeningStatsService();

      await stats.recordPlay(
        trackId: 't1',
        title: 'Song Server 1',
        artist: 'Artist 1',
        album: 'Album 1',
        durationSeconds: 100,
        serverScope: 'server_1',
      );

      await stats.recordPlay(
        trackId: 't2',
        title: 'Song Server 2',
        artist: 'Artist 2',
        album: 'Album 2',
        durationSeconds: 150,
        serverScope: 'server_2',
      );

      // Total unfiltered historical events are all preserved
      expect(stats.allEvents.length, 2);

      // Scoped queries isolate data
      expect(stats.getTotalPlayCount(serverScope: 'server_1'), 1);
      expect(stats.getTotalListeningDuration(serverScope: 'server_1'),
          const Duration(seconds: 100));

      expect(stats.getTotalPlayCount(serverScope: 'server_2'), 1);
      expect(stats.getTotalListeningDuration(serverScope: 'server_2'),
          const Duration(seconds: 150));
    });
  });
}
