import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crotowave/services/navidrome_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavidromeService Artist Caching & API', () {
    test('cacheArtist and getCachedArtist work in-memory', () {
      final nav = NavidromeService();
      final artist = Artist(
        id: 'art-1',
        name: 'Pink Floyd',
        coverArtUrl: 'https://example.com/cover1.jpg',
      );

      expect(nav.getCachedArtist('art-1'), isNull);
      nav.cacheArtist(artist);
      expect(nav.getCachedArtist('art-1'), isNotNull);
      expect(nav.getCachedArtist('art-1')!.name, 'Pink Floyd');
    });

    test('getArtist fetches from API and caches the result', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('getArtist.view')) {
          requestCount++;
          final response = {
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'artist': {
                'id': 'art-42',
                'name': 'Radiohead',
                'coverArt': 'cov-42',
                'album': [],
              }
            }
          };
          return http.Response(jsonEncode(response), 200);
        }
        return http.Response('Not found', 404);
      });

      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'https://mock.navidrome.org',
        username: 'testuser',
        password: 'password',
        client: mockClient,
      );

      // First call: should query API
      final artist = await nav.getArtist('art-42');
      expect(artist, isNotNull);
      expect(artist!.id, 'art-42');
      expect(artist.name, 'Radiohead');
      expect(requestCount, 1);

      // Second call: should return from in-memory cache without hitting HTTP
      final cached = await nav.getArtist('art-42');
      expect(cached, isNotNull);
      expect(cached!.name, 'Radiohead');
      expect(requestCount, 1);
    });

    test('peticiones simultáneas del mismo artista comparten una sola',
        () async {
      var requests = 0;
      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'https://mock.navidrome.org',
        username: 'testuser',
        password: 'password',
        client: MockClient((request) async {
          requests++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
              jsonEncode({
                'subsonic-response': {
                  'status': 'ok',
                  'artist': {'id': 'a', 'name': 'A', 'album': []}
                }
              }),
              200);
        }),
      );
      final results =
          await Future.wait([for (var i = 0; i < 5; i++) nav.getArtist('a')]);
      expect(results.every((artist) => artist?.name == 'A'), isTrue);
      expect(requests, 1);
    });

    test('un artista que falló no se vuelve a pedir en cada reconstrucción',
        () async {
      var requests = 0;
      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'https://mock.navidrome.org',
        username: 'testuser',
        password: 'password',
        client: MockClient((request) async {
          requests++;
          return http.Response('Error', 503);
        }),
      );
      expect(await nav.getArtist('x'), isNull);
      expect(await nav.getArtist('x'), isNull);
      expect(requests, 1);
    });

    test('disconnect clears artist cache', () {
      final nav = NavidromeService();
      final artist = Artist(
        id: 'art-99',
        name: 'Daft Punk',
      );
      nav.cacheArtist(artist);
      expect(nav.getCachedArtist('art-99'), isNotNull);

      nav.disconnect();
      expect(nav.getCachedArtist('art-99'), isNull);
    });
  });
}
