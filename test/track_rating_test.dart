import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/rating_stars.dart';
import 'package:navidrome_client/widgets/track_context_menu.dart';

import 'support/app_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track Rating (Fase 8)', () {
    test('Track model parses userRating and rating correctly', () {
      final json1 = {
        'id': 't1',
        'title': 'Comfortably Numb',
        'artist': 'Pink Floyd',
        'album': 'The Wall',
        'duration': 382,
        'userRating': 5,
      };
      final track1 = Track.fromJson(json1);
      expect(track1.userRating, 5);
      expect(track1.rating, 5);

      final json2 = {
        'id': 't2',
        'title': 'Time',
        'artist': 'Pink Floyd',
        'album': 'The Dark Side of the Moon',
        'duration': 425,
        'rating': 4,
      };
      final track2 = Track.fromJson(json2);
      expect(track2.userRating, 4);

      final copy = track2.copyWith(userRating: 3);
      expect(copy.userRating, 3);
      expect(copy.title, 'Time');
    });

    test('NavidromeService getTrackRating and setRating update memory and call Subsonic setRating.view', () async {
      String? requestedUrl;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('setRating.view')) {
          requestedUrl = request.url.toString();
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                'version': '1.16.1',
              }
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'https://demo.navidrome.org',
        username: 'alice',
        password: 'password123',
        client: mockClient,
      );

      expect(nav.getTrackRating('t100'), 0);

      // Set rating to 5
      await nav.setRating('t100', 5);
      expect(nav.getTrackRating('t100'), 5);
      expect(requestedUrl, contains('setRating.view'));
      expect(requestedUrl, contains('id=t100'));
      expect(requestedUrl, contains('rating=5'));

      // Set rating to 0 (remove rating)
      await nav.setRating('t100', 0);
      expect(nav.getTrackRating('t100'), 0);
      expect(requestedUrl, contains('rating=0'));
    });

    test('NavidromeService sortByRating sorts tracks with highest rating first', () {
      final nav = NavidromeService();
      final t1 = Track(
        id: 't1',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: '100',
        userRating: 2,
      );
      final t2 = Track(
        id: 't2',
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        duration: '100',
        userRating: 5,
      );
      final t3 = Track(
        id: 't3',
        title: 'Song 3',
        artist: 'Artist',
        album: 'Album',
        duration: '100',
        userRating: 0,
      );

      final sorted = nav.sortByRating([t1, t2, t3]);
      expect(sorted.map((t) => t.id).toList(), ['t2', 't1', 't3']);

      // Dynamic rating override via service
      nav.setRating('t3', 5);
      final sortedUpdated = nav.sortByRating([t1, t2, t3]);
      expect(sortedUpdated.first.id, anyOf('t2', 't3'));
      expect(sortedUpdated.last.id, 't1');
    });

    test('NavidromeService disconnect clears track ratings', () {
      final nav = NavidromeService();
      nav.setRating('t1', 4);
      expect(nav.getTrackRating('t1'), 4);

      nav.disconnect();
      expect(nav.getTrackRating('t1'), 0);
    });

    testWidgets('TrackContextMenu renders RatingStars and updates rating on tap',
        (tester) async {
      final nav = FakeNavidrome();
      final player = IdlePlayer();
      final jam = IdleJam();
      final theme = ThemeController();

      final track = Track(
        id: 't_rated',
        title: 'Shine On',
        artist: 'Pink Floyd',
        album: 'Wish You Were Here',
        duration: '780',
        userRating: 0,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<JamController>.value(value: jam),
            ChangeNotifierProvider<ThemeController>.value(value: theme),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackContextMenu(track: track),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Puntuación'), findsOneWidget);
      expect(find.byType(RatingStars), findsOneWidget);

      // Initially rating is 0
      expect(nav.getTrackRating('t_rated'), 0);

      // Tap 4th star (stars are Icons.star_border when empty)
      // There are several icons (favorite, star 1..5, etc.). Find the stars within RatingStars
      final starsInWidget = find.descendant(
        of: find.byType(RatingStars),
        matching: find.byType(GestureDetector),
      );
      expect(starsInWidget, findsNWidgets(5));

      // Tap the 4th star (index 3)
      await tester.tap(starsInWidget.at(3));
      await tester.pump();

      expect(nav.getTrackRating('t_rated'), 4);

      // Tap the 4th star again to clear it back to 0
      await tester.tap(starsInWidget.at(3));
      await tester.pump();

      expect(nav.getTrackRating('t_rated'), 0);
    });
  });
}
