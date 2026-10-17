import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:crotowave/models/crotolink_models.dart';
import 'package:crotowave/services/navidrome_service.dart';

void main() {
  group('NowPlayingEntry Models', () {
    test('parses Subsonic nowPlaying JSON correctly', () {
      final json = {
        'id': 'track_123',
        'title': 'Stairway to Heaven',
        'artist': 'Led Zeppelin',
        'album': 'Led Zeppelin IV',
        'duration': 480,
        'coverArt': 'al-123',
        'username': 'Carlos',
        'minutesAgo': 2,
        'playerId': 1,
      };

      final entry = NowPlayingEntry.fromJson(
        json,
        'https://my-navidrome.com/cover/123.jpg',
      );

      expect(entry.username, 'Carlos');
      expect(entry.minutesAgo, 2);
      expect(entry.playerId, 1);
      expect(entry.track.id, 'track_123');
      expect(entry.track.title, 'Stairway to Heaven');
      expect(entry.track.artist, 'Led Zeppelin');
      expect(entry.track.albumArtUrl, 'https://my-navidrome.com/cover/123.jpg');
    });
  });

  group('ChatMessage Models', () {
    test('parses Subsonic chatMessage with epoch timestamp', () {
      final json = {
        'username': 'Lucia',
        'time': 1726485000000,
        'message': '¡Hola a todos en el servidor!',
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.username, 'Lucia');
      expect(msg.message, '¡Hola a todos en el servidor!');
      expect(msg.time.millisecondsSinceEpoch, 1726485000000);
    });

    test('parses Subsonic chatMessage with ISO string timestamp', () {
      final json = {
        'username': 'Pedro',
        'time': '2026-09-16T12:00:00Z',
        'message': 'Recomiendo este álbum de Pink Floyd',
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.username, 'Pedro');
      expect(msg.message, 'Recomiendo este álbum de Pink Floyd');
      expect(msg.time.year, 2026);
    });
  });

  group('Server CrotoLink Announcements', () {
    test('parses CrotoLink announcement from chat message payload', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'tag': 'CROTOLINK_LIVE',
        'sessionId': 'crotolink_server_999',
        'pin': 'XY99ZZ',
        'host': '192.168.1.150',
        'port': 47623,
        'hostName': 'David',
        'title': 'CrotoLink de David en el Servidor',
        'trackTitle': 'Bohemian Rhapsody',
        'trackArtist': 'Queen',
        'albumArtUrl': 'https://example.com/queen.jpg',
        'mode': 'partySpeaker',
        'participantCount': 3,
        'timestamp': now,
      });

      final fullMessage = '[CROTOLINK_LIVE]:$payload';
      expect(fullMessage.startsWith('[CROTOLINK_LIVE]:'), isTrue);

      final jsonStr = fullMessage.substring('[CROTOLINK_LIVE]:'.length);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final disc = DiscoveredCrotoLinkSession(
        host: data['host'] as String,
        port: data['port'] as int,
        pin: data['pin'] as String,
        sessionTitle: data['title'] as String,
        hostName: data['hostName'] as String,
        participantCount: data['participantCount'] as int,
        currentTrackTitle: data['trackTitle'] as String?,
        currentTrackArtist: data['trackArtist'] as String?,
        albumArtUrl: data['albumArtUrl'] as String?,
        mode: CrotoLinkMode.partySpeaker,
      );

      expect(disc.pin, 'XY99ZZ');
      expect(disc.hostName, 'David');
      expect(disc.currentTrackTitle, 'Bohemian Rhapsody');
      expect(disc.participantCount, 3);
      expect(disc.mode, CrotoLinkMode.partySpeaker);
    });
  });
}
