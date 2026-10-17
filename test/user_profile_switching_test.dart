import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:crotowave/screens/home_screen.dart';
import 'package:crotowave/screens/liked_songs_screen.dart';
import 'package:crotowave/screens/mobile_home_screen.dart';
import 'package:crotowave/services/home_navigation_controller.dart';
import 'package:crotowave/services/connect/connect_service.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/settings_controller.dart';
import 'package:crotowave/services/theme_controller.dart';

import 'support/app_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('User Profile & Session Switching', () {
    test(
        'NavidromeService generates unique userScopes and currentSessionKeys per user',
        () {
      final nav = NavidromeService();

      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'user_alice',
        password: 'password_alice',
      );

      final key1 = nav.currentSessionKey;
      final scope1 = nav.userScope;
      final version1 = nav.sessionVersion;

      expect(key1, isNotNull);
      expect(key1, contains('user_alice'));
      expect(scope1, isNotNull);
      expect(version1, greaterThan(0));

      // Switch to Bob on same server URL
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'user_bob',
        password: 'password_bob',
      );

      final key2 = nav.currentSessionKey;
      final scope2 = nav.userScope;
      final version2 = nav.sessionVersion;

      expect(key2, isNotNull);
      expect(key2, contains('user_bob'));
      expect(key2, isNot(equals(key1)));
      expect(scope2, isNot(equals(scope1)));
      expect(version2, greaterThan(version1));
    });

    test('NavidromeService clears in-memory state when switching users', () {
      final nav = NavidromeService();

      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'alice',
        password: 'alice_password',
      );

      nav.togglePinPlaylist('playlist_alice');
      nav.toggleFollowArtist('artist_alice');
      expect(nav.isPinnedPlaylist('playlist_alice'), isTrue);
      expect(nav.isFollowingArtist('artist_alice'), isTrue);

      // Reconnect as Bob
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'bob',
        password: 'bob_password',
      );

      // State from Alice must not leak into Bob's session
      expect(nav.isPinnedPlaylist('playlist_alice'), isFalse);
      expect(nav.isFollowingArtist('artist_alice'), isFalse);
    });

    test(
        'PlayerController clears playback queue and reloads history when user session changes',
        () {
      final nav = NavidromeService();
      final settings = SettingsController();
      final player = PlayerController(nav, settings);

      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'alice',
        password: 'alice_password',
      );

      final trackAlice = Track(
        id: 't_alice',
        title: 'Song Alice',
        artist: 'Artist Alice',
        album: 'Album Alice',
        duration: '3:00',
      );
      player.setQueueForTesting([trackAlice]);
      expect(player.queue.isNotEmpty, isTrue);

      // Switch to Bob
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'bob',
        password: 'bob_password',
      );

      // Queue should have been cleared upon user switch
      expect(player.queue.isEmpty, isTrue);
      expect(player.currentTrack, isNull);
    });

    testWidgets(
        'LikedSongsScreen watches NavidromeService and reloads on sessionKey change',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int requestCountAlice = 0;
      int requestCountBob = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('getStarred2.view') ||
            request.url.path.contains('getStarred.view')) {
          if (request.url.queryParameters['u'] == 'alice') {
            requestCountAlice++;
            return http.Response(
              jsonEncode({
                'subsonic-response': {
                  'status': 'ok',
                  'starred2': {
                    'song': [
                      {
                        'id': 's_alice_1',
                        'title': 'Alice Favorite',
                        'artist': 'Artist A',
                        'album': 'Album A',
                        'duration': 180,
                      }
                    ]
                  }
                }
              }),
              200,
            );
          } else {
            requestCountBob++;
            return http.Response(
              jsonEncode({
                'subsonic-response': {
                  'status': 'ok',
                  'starred2': {
                    'song': [
                      {
                        'id': 's_bob_1',
                        'title': 'Bob Favorite',
                        'artist': 'Artist B',
                        'album': 'Album B',
                        'duration': 200,
                      }
                    ]
                  }
                }
              }),
              200,
            );
          }
        }
        return http.Response('{"subsonic-response":{"status":"ok"}}', 200);
      });

      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'alice',
        password: 'alice_password',
        client: mockClient,
      );

      final settings = SettingsController();
      final player = PlayerController(nav, settings);
      final theme = ThemeController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<ConnectService>(
                create: (_) => idleConnectService()),
            ChangeNotifierProvider<CrotoLinkController>(
                create: (_) => IdleCrotoLink()),
          ],
          child: const MaterialApp(
            home: LikedSongsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Alice Favorite'), findsOneWidget);
      expect(find.text('Bob Favorite'), findsNothing);

      // Now switch active session to Bob without closing the screen
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'bob',
        password: 'bob_password',
        client: mockClient,
      );

      // Pump to trigger rebuild with the new session
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Bob Favorite'), findsOneWidget);
      expect(find.text('Alice Favorite'), findsNothing);
      expect(requestCountAlice, greaterThan(0));
      expect(requestCountBob, greaterThan(0));
    });

    testWidgets(
        'HomeScreen reloads playlists without restarting app when currentSessionKey changes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('getPlaylists.view')) {
          final isAlice = request.url.queryParameters['u'] == 'alice';
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                'playlists': {
                  'playlist': [
                    {
                      'id': isAlice ? 'pl_alice' : 'pl_bob',
                      'name': isAlice ? 'Alice Hits' : 'Bob Classics',
                      'songCount': 10,
                      'duration': 1800,
                    }
                  ]
                }
              }
            }),
            200,
          );
        }
        if (request.url.path.contains('getGenres.view')) {
          return http.Response(
              '{"subsonic-response":{"status":"ok","genres":{"genre":[]}}}',
              200);
        }
        if (request.url.path.contains('getAlbumList2.view') ||
            request.url.path.contains('getAlbumList.view')) {
          return http.Response(
              '{"subsonic-response":{"status":"ok","albumList2":{"album":[]}}}',
              200);
        }
        if (request.url.path.contains('getRandomSongs.view') ||
            request.url.path.contains('search3.view')) {
          return http.Response(
              '{"subsonic-response":{"status":"ok","searchResult3":{"song":[]}}}',
              200);
        }
        return http.Response('{"subsonic-response":{"status":"ok"}}', 200);
      });

      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'alice',
        password: 'alice_password',
        client: mockClient,
      );

      final settings = SettingsController();
      final player = PlayerController(nav, settings);
      final theme = ThemeController();
      final homeNav = HomeNavigationController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<HomeNavigationController>.value(
                value: homeNav),
            ChangeNotifierProvider<ConnectService>(
                create: (_) => idleConnectService()),
            ChangeNotifierProvider<CrotoLinkController>(
                create: (_) => IdleCrotoLink()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Alice Hits'), findsOneWidget);
      expect(find.text('Bob Classics'), findsNothing);

      // Change session to Bob
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'bob',
        password: 'bob_password',
        client: mockClient,
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Bob Classics'), findsOneWidget);
      expect(find.text('Alice Hits'), findsNothing);
    });

    testWidgets(
        'MobileHomeScreen reloads playlists without restarting app when currentSessionKey changes',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('getPlaylists.view')) {
          final isAlice = request.url.queryParameters['u'] == 'alice';
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                'playlists': {
                  'playlist': [
                    {
                      'id': isAlice ? 'pl_alice' : 'pl_bob',
                      'name': isAlice ? 'Alice Hits' : 'Bob Classics',
                      'songCount': 10,
                      'duration': 1800,
                    }
                  ]
                }
              }
            }),
            200,
          );
        }
        if (request.url.path.contains('getGenres.view')) {
          return http.Response(
              '{"subsonic-response":{"status":"ok","genres":{"genre":[]}}}',
              200);
        }
        if (request.url.path.contains('getAlbumList2.view') ||
            request.url.path.contains('getAlbumList.view')) {
          return http.Response(
              '{"subsonic-response":{"status":"ok","albumList2":{"album":[]}}}',
              200);
        }
        if (request.url.path.contains('getRandomSongs.view') ||
            request.url.path.contains('search3.view')) {
          return http.Response(
              '{"subsonic-response":{"status":"ok","searchResult3":{"song":[]}}}',
              200);
        }
        return http.Response('{"subsonic-response":{"status":"ok"}}', 200);
      });

      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'alice',
        password: 'alice_password',
        client: mockClient,
      );

      final settings = SettingsController();
      final player = PlayerController(nav, settings);
      final theme = ThemeController();
      final homeNav = HomeNavigationController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider<PlayerController>.value(value: player),
            ChangeNotifierProvider<ThemeController>.value(value: theme),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<HomeNavigationController>.value(
                value: homeNav),
            ChangeNotifierProvider<ConnectService>(
                create: (_) => idleConnectService()),
            ChangeNotifierProvider<CrotoLinkController>(
                create: (_) => IdleCrotoLink()),
          ],
          child: const MaterialApp(
            home: MobileHomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Go to Library tab (index 2) in MobileHomeScreen
      final libraryTab = find.text('Biblioteca');
      if (libraryTab.evaluate().isNotEmpty) {
        await tester.tap(libraryTab);
        await tester.pumpAndSettle();
      }

      expect(find.text('Alice Hits'), findsOneWidget);
      expect(find.text('Bob Classics'), findsNothing);

      // Change session to Bob
      nav.setConnectedForTesting(
        url: 'http://192.168.1.50:4533',
        username: 'bob',
        password: 'bob_password',
        client: mockClient,
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Bob Classics'), findsOneWidget);
      expect(find.text('Alice Hits'), findsNothing);
    });
  });
}
