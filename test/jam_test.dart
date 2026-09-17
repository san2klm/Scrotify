import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:navidrome_client/models/jam_models.dart';
import 'package:navidrome_client/services/jam_guest_service.dart';
import 'package:navidrome_client/services/jam_host_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

void main() {
  group('JamCode tests', () {
    test('generate() creates valid 6-char code', () {
      final code = JamCode.generate();
      expect(code.value.length, 6);
      expect(code.formatted, matches(r'^[A-Z0-9]{3}-[A-Z0-9]{3}$'));
    });

    test('parses and formats valid code', () {
      final code = JamCode('ab34ef');
      expect(code.value, 'AB34EF');
      expect(code.formatted, 'AB3-4EF');
    });

    test('throws on invalid length', () {
      expect(() => JamCode('ABC'), throwsArgumentError);
      expect(() => JamCode('ABCDEFG'), throwsArgumentError);
    });
  });

  group('JamQrData tests', () {
    test('toUri and fromUri roundtrip', () {
      final qr = JamQrData(
        host: '192.168.1.50',
        port: 54321,
        code: 'AB34EF',
        sessionId: 'jam_123456',
      );

      final uriStr = qr.toUri();
      expect(uriStr, startsWith('scrotify://jam?'));

      final parsed = JamQrData.fromUri(uriStr);
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.50');
      expect(parsed.port, 54321);
      expect(parsed.code, 'AB34EF');
      expect(parsed.sessionId, 'jam_123456');
    });

    test('fromUri returns null on invalid schemes', () {
      expect(JamQrData.fromUri('http://example.com'), isNull);
      expect(JamQrData.fromUri('scrotify://other?host=1.1.1.1'), isNull);
    });

    test('roundtrips optional remote connection data', () {
      final qr = JamQrData(
        host: '192.168.1.50',
        port: kJamHostPort,
        code: 'AB34EF',
        remoteHost: '203.0.113.10',
        remotePort: 47620,
      );

      final parsed = JamQrData.fromUri(qr.toUri());
      expect(parsed, isNotNull);
      expect(parsed!.remoteHost, '203.0.113.10');
      expect(parsed.remotePort, 47620);
    });

    test('rejects an invalid PIN or port in a QR URI', () {
      expect(
        JamQrData.fromUri('scrotify://jam?host=10.0.0.2&port=0&code=ABC123'),
        isNull,
      );
      expect(
        JamQrData.fromUri(
            'scrotify://jam?host=10.0.0.2&port=47620&code=ABCIO0'),
        isNull,
      );
    });
  });

  group('Jam Models Serialization', () {
    test('JamParticipant JSON roundtrip', () {
      final p = JamParticipant(
        id: 'p1',
        name: 'Alice',
        avatarColorValue: 0xFF10B981,
        isHost: true,
        joinedAt: DateTime(2026, 9, 16, 12, 0),
        canControlPlayback: true,
        canManageQueue: true,
      );

      final json = p.toJson();
      final fromJson = JamParticipant.fromJson(json);

      expect(fromJson.id, p.id);
      expect(fromJson.name, p.name);
      expect(fromJson.avatarColorValue, p.avatarColorValue);
      expect(fromJson.isHost, true);
    });

    test('JamQueueItem JSON roundtrip', () {
      final track = Track(
        id: 't1',
        title: 'Song Title',
        artist: 'Artist Name',
        album: 'Album Name',
        duration: '210',
        albumArtUrl: 'https://example.com/cover.jpg',
      );
      final participant = JamParticipant(
        id: 'p2',
        name: 'Bob',
        avatarColorValue: 0xFFA855F7,
        isHost: false,
        joinedAt: DateTime(2026, 9, 16, 12, 1),
      );
      final item = JamQueueItem(
        id: 'item_1',
        track: track,
        addedBy: participant,
        addedAt: DateTime(2026, 9, 16, 12, 2),
      );

      final json = item.toJson();
      final fromJson = JamQueueItem.fromJson(json);

      expect(fromJson.id, item.id);
      expect(fromJson.track.id, 't1');
      expect(fromJson.track.title, 'Song Title');
      expect(fromJson.addedBy?.name, 'Bob');
    });

    test('JamSessionState JSON roundtrip', () {
      final state = JamSessionState(
        sessionId: 'session_1',
        pinCode: 'AB34EF',
        hostName: 'Alice PC',
        hostIp: '192.168.1.100',
        port: 45000,
        mode: JamMode.partySpeaker,
        isPlaying: true,
        positionMs: 45000,
        updatedAtMs: 1726480000,
        queue: [],
        participants: [
          JamParticipant(
            id: 'host_id',
            name: 'Alice',
            avatarColorValue: 0xFFA855F7,
            isHost: true,
            joinedAt: DateTime.now(),
          ),
        ],
        allowGuestControls: true,
      );

      final json = state.toJson();
      final fromJson = JamSessionState.fromJson(json);

      expect(fromJson.sessionId, 'session_1');
      expect(fromJson.pinCode, 'AB34EF');
      expect(fromJson.mode, JamMode.partySpeaker);
      expect(fromJson.participants.length, 1);
      expect(fromJson.participants.first.name, 'Alice');
      expect(fromJson.allowGuestControls, true);
    });

    test('preserves session access settings', () {
      const state = JamSessionState(
        sessionId: 'private_session',
        pinCode: 'AB34EF',
        hostName: 'Alice',
        hostIp: '192.168.1.2',
        port: kJamHostPort,
        mode: JamMode.synchronizedListening,
        isPlaying: false,
        positionMs: 0,
        updatedAtMs: 1,
        queue: [],
        participants: [],
        allowGuestControls: false,
        allowGuestQueueManage: false,
        isPublic: false,
        initialPlaylistId: 'playlist_1',
        maxParticipants: 3,
      );

      final parsed = JamSessionState.fromJson(state.toJson());
      expect(parsed.allowGuestQueueManage, isFalse);
      expect(parsed.isPublic, isFalse);
      expect(parsed.initialPlaylistId, 'playlist_1');
      expect(parsed.maxParticipants, 3);
    });

    test('DiscoveredJamSession JSON roundtrip', () {
      const disc = DiscoveredJamSession(
        host: '192.168.1.100',
        port: 45000,
        pin: 'AB34EF',
        sessionTitle: 'Jam de Alice',
        hostName: 'Alice',
        participantCount: 3,
        currentTrackTitle: 'Awesome Track',
        currentTrackArtist: 'Awesome Artist',
        albumArtUrl: 'https://example.com/art.jpg',
        mode: JamMode.synchronizedListening,
      );

      final json = disc.toJson();
      final fromJson = DiscoveredJamSession.fromJson(json, '192.168.1.100');

      expect(fromJson.host, '192.168.1.100');
      expect(fromJson.port, 45000);
      expect(fromJson.pin, 'AB34EF');
      expect(fromJson.hostName, 'Alice');
      expect(fromJson.participantCount, 3);
      expect(fromJson.currentTrackTitle, 'Awesome Track');
      expect(fromJson.mode, JamMode.synchronizedListening);
    });

    test('Radar discovery prefers the UDP sender address', () {
      final discovered = DiscoveredJamSession.fromJson(
        {
          'host': '100.64.0.4',
          'port': kJamHostPort,
          'pin': 'AB34EF',
          'mode': JamMode.partySpeaker.name,
        },
        '192.168.1.35',
        preferFallbackHost: true,
      );

      expect(discovered.host, '192.168.1.35');
    });
  });

  group('Jam Network Services (Host & Guest Handshake)', () {
    late JamHostService hostService;
    late JamGuestService guestService;

    setUp(() {
      hostService = JamHostService();
      guestService = JamGuestService();
    });

    tearDown(() async {
      await guestService.disconnect();
      await hostService.stop();
    });

    test('Host starts, Guest connects via WebSocket and exchanges state',
        () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_test_session',
        pinCode: pin,
        hostName: 'TestHost',
        mode: JamMode.partySpeaker,
      );

      expect(hostService.isRunning, isTrue);
      expect(hostService.port, greaterThan(0));

      final stateCompleter = Completer<JamSessionState>();
      guestService.onStateSync = (state) {
        if (!stateCompleter.isCompleted) {
          stateCompleter.complete(state);
        }
      };

      final host = hostService.hostIp ?? '127.0.0.1';
      final connected = await guestService.connect(
        host: host,
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
      );

      expect(connected, isTrue);
      expect(guestService.isConnected, isTrue);

      final syncedState = await stateCompleter.future.timeout(
        const Duration(seconds: 4),
      );

      expect(syncedState.sessionId, 'jam_test_session');
      expect(syncedState.pinCode, pin.value);
      expect(syncedState.hostName, 'TestHost');
      expect(syncedState.mode, JamMode.partySpeaker);
    });

    test('Guest discovers a public host through the Jam radar', () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_radar_session',
        pinCode: pin,
        hostName: 'TestHost',
        isPublic: true,
      );

      final discovered = await guestService.scanRadar(
        timeout: const Duration(seconds: 2),
      );
      final matches =
          discovered.where((item) => item.pin == pin.value).toList();
      expect(matches, isNotEmpty);

      final session = matches.firstWhere(
        (item) => item.port == hostService.port,
        orElse: () => matches.first,
      );

      expect(session.port, hostService.port);
      expect(session.hostName, 'TestHost');
    });

    test('Guest sends add_to_queue and Host receives it', () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_test_session',
        pinCode: pin,
        hostName: 'TestHost',
      );

      final trackCompleter = Completer<Track>();
      hostService.onTrackAddRequested = (track, participant, playNext) {
        if (!trackCompleter.isCompleted) {
          trackCompleter.complete(track);
        }
      };

      final host = hostService.hostIp ?? '127.0.0.1';
      await guestService.connect(
        host: host,
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
      );

      final sampleTrack = Track(
        id: 't_collab_1',
        title: 'Collaborative Tune',
        artist: 'The Guests',
        album: 'Jam Party',
        duration: '180',
      );

      guestService.addToQueue(sampleTrack);

      final receivedTrack = await trackCompleter.future.timeout(
        const Duration(seconds: 4),
      );

      expect(receivedTrack.id, 't_collab_1');
      expect(receivedTrack.title, 'Collaborative Tune');
      expect(receivedTrack.artist, 'The Guests');
    });

    test('Host rejects an incorrect PIN and sessions at capacity', () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_limited_session',
        pinCode: pin,
        hostName: 'TestHost',
        maxParticipants: 1,
      );

      final host = hostService.hostIp ?? '127.0.0.1';
      final wrongPin = await guestService.connect(
        host: host,
        port: hostService.port,
        pin: 'AB34EF',
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
      );
      expect(wrongPin, isFalse);

      final fullSession = await guestService.connect(
        host: host,
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
      );
      expect(fullSession, isFalse);
    });

    test('Host blocks queue changes when guest queue management is disabled',
        () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_read_only_queue',
        pinCode: pin,
        hostName: 'TestHost',
        allowGuestQueueManage: false,
      );

      var addRequestReceived = false;
      hostService.onTrackAddRequested = (_, __, ___) {
        addRequestReceived = true;
      };

      final host = hostService.hostIp ?? '127.0.0.1';
      final connected = await guestService.connect(
        host: host,
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
      );
      expect(connected, isTrue);
      expect(guestService.localParticipant!.canManageQueue, isFalse);

      guestService.addToQueue(Track(
        id: 'blocked_track',
        title: 'Blocked track',
        artist: 'Guest',
        album: 'Jam',
        duration: '180',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(addRequestReceived, isFalse);
    });
  });
}
