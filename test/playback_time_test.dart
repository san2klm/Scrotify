import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/utils/playback_time.dart';
import 'package:navidrome_client/screens/player_screen.dart';
import 'package:navidrome_client/widgets/persistent_player_bar.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:provider/provider.dart';

import 'support/app_fakes.dart';

class _FakePlayerWithTrack extends IdlePlayer {
  final Track _track;
  final Duration _pos;
  final Duration _dur;
  Duration? lastSought;

  _FakePlayerWithTrack({
    required Track track,
    required Duration position,
    required Duration duration,
  })  : _track = track,
        _pos = position,
        _dur = duration;

  @override
  Track? get currentTrack => _track;

  @override
  Duration get position => _pos;

  @override
  Duration? get duration => _dur;

  @override
  Stream<Duration> get positionStream => Stream.value(_pos);

  @override
  Stream<Duration?> get durationStream => Stream.value(_dur);

  @override
  Future<void> seek(Duration position) async {
    lastSought = position;
  }
}

void main() {
  group('playback_time pure unit tests', () {
    test('normal elapsed duration formatting', () {
      expect(formatPlaybackTime(Duration.zero), '0:00');
      expect(formatPlaybackTime(const Duration(seconds: 5)), '0:05');
      expect(formatPlaybackTime(const Duration(seconds: 59)), '0:59');
      expect(
          formatPlaybackTime(const Duration(minutes: 1, seconds: 23)), '1:23');
      expect(
          formatPlaybackTime(const Duration(minutes: 4, seconds: 17)), '4:17');
      expect(formatPlaybackTime(const Duration(minutes: 10, seconds: 45)),
          '10:45');
      expect(formatPlaybackTime(null), '0:00');
      expect(formatPlaybackTime(const Duration(seconds: -10)), '0:00');

      // Also verify PlaybackTime static helper and aliases
      expect(PlaybackTime.formatElapsed(const Duration(seconds: 5)), '0:05');
      expect(
          PlaybackTime.format(const Duration(minutes: 1, seconds: 23)), '1:23');
      expect(formatElapsed(const Duration(minutes: 4, seconds: 17)), '4:17');
    });

    test('elapsed padding (seconds padded to two digits, exact minutes)', () {
      expect(formatPlaybackTime(const Duration(seconds: 0)), '0:00');
      expect(formatPlaybackTime(const Duration(seconds: 9)), '0:09');
      expect(
          formatPlaybackTime(const Duration(minutes: 1, seconds: 0)), '1:00');
      expect(
          formatPlaybackTime(const Duration(minutes: 3, seconds: 4)), '3:04');
      expect(
          formatPlaybackTime(const Duration(minutes: 10, seconds: 0)), '10:00');
      expect(
          formatPlaybackTime(const Duration(minutes: 59, seconds: 0)), '59:00');
    });

    test('hours elapsed formatting with padded minutes and seconds', () {
      expect(formatPlaybackTime(const Duration(hours: 1)), '1:00:00');
      expect(
          formatPlaybackTime(const Duration(hours: 1, minutes: 5, seconds: 9)),
          '1:05:09');
      expect(
          formatPlaybackTime(
              const Duration(hours: 2, minutes: 45, seconds: 30)),
          '2:45:30');
    });

    test('clamping max(total - position, zero) in remaining calculation', () {
      // Normal positive remaining
      expect(
        calculateRemainingDuration(
          const Duration(seconds: 30),
          const Duration(seconds: 100),
        ),
        const Duration(seconds: 70),
      );
      // Exhausted (position == duration)
      expect(
        calculateRemainingDuration(
          const Duration(seconds: 100),
          const Duration(seconds: 100),
        ),
        Duration.zero,
      );
      // Overrun / exhausted (position > duration)
      expect(
        calculateRemainingDuration(
          const Duration(seconds: 120),
          const Duration(seconds: 100),
        ),
        Duration.zero,
      );
      // Zero duration
      expect(
        calculateRemainingDuration(Duration.zero, Duration.zero),
        Duration.zero,
      );
      // Null duration
      expect(
        calculateRemainingDuration(const Duration(seconds: 30), null),
        Duration.zero,
      );
      // Null position treated as zero
      expect(
        calculateRemainingDuration(null, const Duration(seconds: 60)),
        const Duration(seconds: 60),
      );
      // Negative position treated as zero
      expect(
        calculateRemainingDuration(
            const Duration(seconds: -10), const Duration(seconds: 60)),
        const Duration(seconds: 60),
      );
      // PlaybackTime.remaining helper
      expect(
        PlaybackTime.remaining(
            const Duration(seconds: 10), const Duration(seconds: 60)),
        const Duration(seconds: 50),
      );
    });

    test('normal remaining time formatting with leading minus', () {
      expect(
        formatRemainingPlaybackTime(
          const Duration(minutes: 1, seconds: 42),
          const Duration(minutes: 4, seconds: 17),
        ),
        '-2:35',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(seconds: 15),
          const Duration(minutes: 1),
        ),
        '-0:45',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(minutes: 4, seconds: 12),
          const Duration(minutes: 4, seconds: 17),
        ),
        '-0:05',
      );

      // Verify PlaybackTime static helper and alias
      expect(
        PlaybackTime.formatRemaining(
          const Duration(minutes: 1, seconds: 42),
          const Duration(minutes: 4, seconds: 17),
        ),
        '-2:35',
      );
      expect(
        formatRemaining(
          const Duration(seconds: 15),
          const Duration(minutes: 1),
        ),
        '-0:45',
      );
    });

    test('remaining padding (seconds and exact minutes)', () {
      expect(
        formatRemainingPlaybackTime(
          Duration.zero,
          const Duration(minutes: 3),
        ),
        '-3:00',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(minutes: 1),
          const Duration(minutes: 4),
        ),
        '-3:00',
      );
      expect(
        formatRemainingPlaybackTime(
          Duration.zero,
          const Duration(minutes: 1),
        ),
        '-1:00',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(seconds: 55),
          const Duration(minutes: 1),
        ),
        '-0:05',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(seconds: 51),
          const Duration(minutes: 1),
        ),
        '-0:09',
      );
    });

    test('exhausted remaining duration clamped to -0:00', () {
      // Exactly exhausted
      expect(
        formatRemainingPlaybackTime(
          const Duration(minutes: 4, seconds: 17),
          const Duration(minutes: 4, seconds: 17),
        ),
        '-0:00',
      );
      // Overrun position > duration
      expect(
        formatRemainingPlaybackTime(
          const Duration(minutes: 5),
          const Duration(minutes: 4, seconds: 17),
        ),
        '-0:00',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(seconds: 100),
          const Duration(seconds: 50),
        ),
        '-0:00',
      );
      // Zero duration
      expect(
        formatRemainingPlaybackTime(Duration.zero, Duration.zero),
        '-0:00',
      );
      // Null values
      expect(
        formatRemainingPlaybackTime(null, null),
        '-0:00',
      );
      expect(
        formatRemainingPlaybackTime(const Duration(seconds: 30), null),
        '-0:00',
      );
      expect(
        formatRemainingPlaybackTime(null, Duration.zero),
        '-0:00',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(seconds: 10),
          const Duration(seconds: -50),
        ),
        '-0:00',
      );
    });

    test('hours remaining formatting with minus', () {
      expect(
        formatRemainingPlaybackTime(
          const Duration(minutes: 15),
          const Duration(hours: 1, minutes: 30),
        ),
        '-1:15:00',
      );
      expect(
        formatRemainingPlaybackTime(
          const Duration(hours: 2),
          const Duration(hours: 1, minutes: 30),
        ),
        '-0:00',
      );
    });
  });

  group('PlayerScreen elapsed/remaining time toggle widget tests', () {
    testWidgets(
        'tapping right time label toggles between duration and remaining time',
        (tester) async {
      final track = Track(
        id: 'track_1',
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        duration: '257', // 4:17 = 257 seconds
      );
      final player = _FakePlayerWithTrack(
        track: track,
        position: const Duration(minutes: 1, seconds: 42), // 1:42
        duration: const Duration(minutes: 4, seconds: 17), // 4:17
      );
      final nav = FakeNavidrome();
      final jam = JamController(player, nav);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<JamController>.value(value: jam),
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: const MaterialApp(
            home: PlayerScreen(),
          ),
        ),
      );
      await tester.pump();

      // Left label: elapsed time 1:42
      expect(find.text('1:42'), findsOneWidget);
      // Right label: initially total duration 4:17
      expect(find.text('4:17'), findsOneWidget);
      expect(find.text('-2:35'), findsNothing);

      // Verify tooltip and semantics
      final toggleFinder = find.byTooltip('Mostrar tiempo restante');
      expect(toggleFinder, findsOneWidget);

      // Verify touch target is at least 40 logical pixels in width and height
      final initialToggleSize = tester.getSize(toggleFinder);
      expect(initialToggleSize.width, greaterThanOrEqualTo(40.0));
      expect(initialToggleSize.height, greaterThanOrEqualTo(40.0));

      // Verify visual vertical alignment between elapsed time and duration toggle
      expect(
        (tester.getCenter(find.text('1:42')).dy -
                tester.getCenter(find.text('4:17')).dy)
            .abs(),
        lessThan(1.0),
      );

      // Tap the right label
      await tester.tap(find.text('4:17'));
      await tester.pump();

      // Right label should now show negative remaining time -2:35
      expect(find.text('-2:35'), findsOneWidget);
      expect(find.text('4:17'), findsNothing);
      // Left label still displays elapsed time 1:42
      expect(find.text('1:42'), findsOneWidget);
      // Tooltip now invites switching back
      final durationToggleFinder = find.byTooltip('Mostrar duración total');
      expect(durationToggleFinder, findsOneWidget);

      // Verify touch target remains at least 40 logical pixels in remaining time state
      final remainingToggleSize = tester.getSize(durationToggleFinder);
      expect(remainingToggleSize.width, greaterThanOrEqualTo(40.0));
      expect(remainingToggleSize.height, greaterThanOrEqualTo(40.0));

      // Verify visual vertical alignment in toggled state
      expect(
        (tester.getCenter(find.text('1:42')).dy -
                tester.getCenter(find.text('-2:35')).dy)
            .abs(),
        lessThan(1.0),
      );

      // Tap again to toggle back
      await tester.tap(find.text('-2:35'));
      await tester.pump();

      expect(find.text('4:17'), findsOneWidget);
      expect(find.text('-2:35'), findsNothing);
      expect(find.text('1:42'), findsOneWidget);
    });

    testWidgets(
        'PersistentPlayerBar desktop toggles right label between duration and remaining time independently',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final track = Track(
        id: 'track_2',
        title: 'Desktop Song',
        artist: 'Desktop Artist',
        album: 'Desktop Album',
        duration: '257',
      );
      final player = _FakePlayerWithTrack(
        track: track,
        position: const Duration(minutes: 1, seconds: 42),
        duration: const Duration(minutes: 4, seconds: 17),
      );
      final nav = FakeNavidrome();
      final jam = JamController(player, nav);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<JamController>.value(value: jam),
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: PersistentPlayerBar(compact: false),
            ),
          ),
        ),
      );
      await tester.pump();

      // Left label: elapsed time 1:42
      expect(find.text('1:42'), findsOneWidget);
      // Right label: initially total duration 4:17
      expect(find.text('4:17'), findsOneWidget);
      expect(find.text('-2:35'), findsNothing);

      // Tooltip to show remaining time
      final toggleFinder = find.byTooltip('Mostrar tiempo restante');
      expect(toggleFinder, findsOneWidget);

      // Verify touch target is at least 40 logical pixels in width and height
      final initialToggleSize = tester.getSize(toggleFinder);
      expect(initialToggleSize.width, greaterThanOrEqualTo(40.0));
      expect(initialToggleSize.height, greaterThanOrEqualTo(40.0));

      // Verify visual vertical alignment between elapsed time and duration toggle
      expect(
        (tester.getCenter(find.text('1:42')).dy -
                tester.getCenter(find.text('4:17')).dy)
            .abs(),
        lessThan(1.0),
      );

      // Tap the right label
      await tester.tap(find.text('4:17'));
      await tester.pump();

      // Toggled to remaining time -2:35
      expect(find.text('-2:35'), findsOneWidget);
      expect(find.text('4:17'), findsNothing);
      expect(find.text('1:42'), findsOneWidget);
      final durationToggleFinder = find.byTooltip('Mostrar duración total');
      expect(durationToggleFinder, findsOneWidget);

      // Verify touch target remains at least 40 logical pixels in remaining time state
      final remainingToggleSize = tester.getSize(durationToggleFinder);
      expect(remainingToggleSize.width, greaterThanOrEqualTo(40.0));
      expect(remainingToggleSize.height, greaterThanOrEqualTo(40.0));

      // Verify visual vertical alignment in toggled state
      expect(
        (tester.getCenter(find.text('1:42')).dy -
                tester.getCenter(find.text('-2:35')).dy)
            .abs(),
        lessThan(1.0),
      );

      // Tap again to toggle back
      await tester.tap(find.text('-2:35'));
      await tester.pump();

      expect(find.text('4:17'), findsOneWidget);
      expect(find.text('-2:35'), findsNothing);
      expect(find.text('1:42'), findsOneWidget);
    });

    testWidgets(
        'seeking with desktop progress slider does not toggle time format and toggle does not trigger seek',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final track = Track(
        id: 'track_3',
        title: 'Seek Song',
        artist: 'Seek Artist',
        album: 'Seek Album',
        duration: '257',
      );
      final player = _FakePlayerWithTrack(
        track: track,
        position: const Duration(minutes: 1, seconds: 42),
        duration: const Duration(minutes: 4, seconds: 17),
      );
      final nav = FakeNavidrome();
      final jam = JamController(player, nav);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<JamController>.value(value: jam),
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: PersistentPlayerBar(compact: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final progressSliderFinder = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.max > 1,
      );
      expect(progressSliderFinder, findsOneWidget);
      expect(player.lastSought, isNull);

      // Tapping the slider to seek
      await tester.tap(progressSliderFinder);
      await tester.pump();

      // Seeking occurred on player
      expect(player.lastSought, isNotNull);
      // Time label on the right is still displaying total duration (did not toggle)
      expect(find.text('4:17'), findsOneWidget);
      expect(find.text('-2:35'), findsNothing);

      // Reset lastSought
      player.lastSought = null;

      // Now tap the right toggle
      await tester.tap(find.text('4:17'));
      await tester.pump();

      // Right label toggled to remaining time
      expect(find.text('-2:35'), findsOneWidget);
      // Toggle tap did NOT invoke seek
      expect(player.lastSought, isNull);
    });
  });
}
