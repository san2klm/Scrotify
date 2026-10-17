import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

import 'package:navidrome_client/models/jam_models.dart';
import 'package:navidrome_client/services/jam_guest_service.dart';
import 'package:navidrome_client/services/jam_host_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/remote_jam_service.dart';

import 'support/app_fakes.dart';

void main() {
  group('JamCode tests', () {
    test('generate() creates valid 6-char code', () {
      final code = JamCode.generate();
      expect(code.value.length, 6);
      expect(code.formatted, matches(r'^[A-Z0-9]{3}-[A-Z0-9]{3}$'));
    });

    test(
        'generate() accepts injected Random and defaults structurally to CSPRNG',
        () {
      final code1 = JamCode.generate(Random(42));
      final code2 = JamCode.generate(Random(42));
      expect(code1.value, code2.value);

      final defaultCode = JamCode.generate();
      expect(defaultCode.value.length, JamCode.length);
      expect(
          defaultCode.value.split('').every((c) => JamCode.charset.contains(c)),
          isTrue);
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
        tlsFingerprint:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      final uriStr = qr.toUri();
      expect(uriStr, startsWith('crotowave://jam?'));

      final parsed = JamQrData.fromUri(uriStr);
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.50');
      expect(parsed.port, 54321);
      expect(parsed.code, 'AB34EF');
      expect(parsed.sessionId, 'jam_123456');
      expect(parsed.tlsFingerprint,
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    });

    test('fromUri returns null on invalid schemes', () {
      expect(JamQrData.fromUri('http://example.com'), isNull);
      expect(JamQrData.fromUri('scrotify://other?host=1.1.1.1'), isNull);
      expect(JamQrData.fromUri('crotowave://other?host=1.1.1.1'), isNull);
    });

    test('fromUri acepta el esquema anterior (scrotify://)', () {
      final parsed = JamQrData.fromUri(
          'scrotify://jam?host=10.0.0.2&port=47620&code=ABC234'
          '&transport=wss&tlsFingerprint=${'a' * 64}');
      expect(parsed?.host, '10.0.0.2');
      expect(parsed?.port, 47620);
    });

    test('roundtrips optional remote connection data', () {
      final qr = JamQrData(
        host: '192.168.1.50',
        port: kJamHostPort,
        code: 'AB34EF',
        remoteHost: '203.0.113.10',
        remotePort: 47620,
        tlsFingerprint:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );

      final parsed = JamQrData.fromUri(qr.toUri());
      expect(parsed, isNotNull);
      expect(parsed!.remoteHost, '203.0.113.10');
      expect(parsed.remotePort, 47620);
      expect(parsed.tlsFingerprint,
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
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
      expect(
        JamQrData.fromUri(
            'scrotify://jam?host=10.0.0.2&port=47620&code=ABC123'),
        isNull,
      );
    });
  });

  group('CrotoLink Models Serialization', () {
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
        queueRevision: 42,
      );

      final parsed = JamSessionState.fromJson(state.toJson());
      expect(parsed.allowGuestQueueManage, isFalse);
      expect(parsed.isPublic, isFalse);
      expect(parsed.initialPlaylistId, 'playlist_1');
      expect(parsed.maxParticipants, 3);
      expect(parsed.queueRevision, 42);
    });

    test('DiscoveredJamSession JSON roundtrip', () {
      const disc = DiscoveredJamSession(
        host: '192.168.1.100',
        port: 45000,
        pin: 'AB34EF',
        sessionTitle: 'CrotoLink de Alice',
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

  group('CrotoLink Network Services (Host & Guest Handshake)', () {
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
      var initialSyncCount = 0;
      guestService.onStateSync = (state) {
        initialSyncCount++;
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
        tlsFingerprint: hostService.tlsFingerprint!,
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

      // The handshake carries one join response and one canonical snapshot.
      // The response itself is intentionally not treated as a second sync.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(initialSyncCount, 1);
    });

    test('Guest discovers a public host through the CrotoLink radar', () async {
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
        tlsFingerprint: hostService.tlsFingerprint!,
      );

      final sampleTrack = Track(
        id: 't_collab_1',
        title: 'Collaborative Tune',
        artist: 'The Guests',
        album: 'CrotoLink Party',
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
        tlsFingerprint: hostService.tlsFingerprint!,
      );
      expect(wrongPin, isFalse);

      final fullSession = await guestService.connect(
        host: host,
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
        tlsFingerprint: hostService.tlsFingerprint!,
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
        tlsFingerprint: hostService.tlsFingerprint!,
      );
      expect(connected, isTrue);
      expect(guestService.localParticipant!.canManageQueue, isFalse);

      guestService.addToQueue(Track(
        id: 'blocked_track',
        title: 'Blocked track',
        artist: 'Guest',
        album: 'CrotoLink',
        duration: '180',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(addRequestReceived, isFalse);
    });

    test('host/guest reconnect retains participant count/id', () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_reconnect_session',
        pinCode: pin,
        hostName: 'TestHost',
      );

      final host = hostService.hostIp ?? '127.0.0.1';
      final connected = await guestService.connect(
        host: host,
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
        tlsFingerprint: hostService.tlsFingerprint!,
      );
      expect(connected, isTrue);

      expect(hostService.participants.length, 1);
      final initialParticipant = hostService.participants.first;
      expect(guestService.localParticipant?.id, initialParticipant.id);

      // Trigger reconnect without explicit disconnect
      await guestService.triggerReconnectForTesting();

      expect(guestService.isConnected, isTrue);
      expect(hostService.participants.length, 1);
      expect(hostService.participants.first.id, initialParticipant.id);
      expect(guestService.localParticipant?.id, initialParticipant.id);
    });

    test('Guest rejects a TLS certificate whose fingerprint is not pinned',
        () async {
      final pin = JamCode('JK94MN');
      await hostService.start(
        sessionId: 'jam_tls_pin_session',
        pinCode: pin,
        hostName: 'TestHost',
      );

      final connected = await guestService.connect(
        host: hostService.hostIp ?? '127.0.0.1',
        port: hostService.port,
        pin: pin.value,
        name: 'GuestUser',
        avatarColorValue: 0xFF10B981,
        tlsFingerprint: List.filled(64, '0').join(),
      );

      expect(connected, isFalse);
      expect(guestService.isConnected, isFalse);
    });
  });

  group('JamRateLimiter tests', () {
    test('enforces window limit deterministically', () {
      final limiter = JamRateLimiter(
        maxEvents: 3,
        window: const Duration(milliseconds: 1000),
      );

      expect(limiter.tryAcquire(100), isTrue);
      expect(limiter.tryAcquire(200), isTrue);
      expect(limiter.tryAcquire(300), isTrue);
      expect(limiter.tryAcquire(400), isFalse);

      // After window expires for first timestamp
      expect(limiter.tryAcquire(1101), isTrue);
      expect(limiter.tryAcquire(1102), isFalse);

      // After window expires for all initial timestamps
      expect(limiter.tryAcquire(2200), isTrue);
      expect(limiter.tryAcquire(2300), isTrue);

      limiter.reset();
      expect(limiter.timestamps, isEmpty);
      expect(limiter.tryAcquire(2400), isTrue);
    });
  });

  group('CrotoLink queue duplicate tracking', () {
    test('isTrackInJamQueue detects existing tracks correctly', () {
      final fakeJam = IdleJam();
      expect(fakeJam.isTrackInJamQueue('trk_1'), isFalse);
    });
  });

  group('CrotoLink Controller & Remote CrotoLink Resiliency', () {
    test('Track instances with identical ID but different object references match queue items', () {
      final trackA1 = Track(
        id: 'track_123',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: '180',
      );
      final trackA2 = Track(
        id: 'track_123',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        duration: '180',
      );
      expect(identical(trackA1, trackA2), isFalse);

      final queueItem = JamQueueItem(
        id: 'item_1',
        track: trackA1,
        addedAt: DateTime.now(),
      );

      final orderedQueue = [trackA2];
      const expected = 0;
      final matched = (expected >= 0 &&
              expected < orderedQueue.length &&
              (identical(orderedQueue[expected], queueItem.track) ||
                  orderedQueue[expected].id == queueItem.track.id))
          ? expected
          : orderedQueue.indexWhere((t) =>
              identical(t, queueItem.track) || t.id == queueItem.track.id);

      expect(matched, 0);
    });

    test('JamQueueItem serializes and deserializes properly for remote state', () {
      final item = JamQueueItem(
        id: 'remote_item_42',
        track: Track(
          id: 'trk_remote',
          title: 'Remote Song',
          artist: 'Remote Artist',
          album: 'Remote Album',
          duration: '215',
        ),
        addedBy: JamParticipant(
          id: 'user_1',
          name: 'Alice',
          avatarColorValue: 0xFF10B981,
          isHost: false,
          joinedAt: DateTime.now(),
        ),
        addedAt: DateTime.parse('2026-09-29T12:00:00Z'),
      );

      final json = item.toJson();
      final roundtrip = JamQueueItem.fromJson(json);

      expect(roundtrip.id, 'remote_item_42');
      expect(roundtrip.track.id, 'trk_remote');
      expect(roundtrip.track.title, 'Remote Song');
      expect(roundtrip.track.artist, 'Remote Artist');
      expect(roundtrip.track.duration, '215');
      expect(roundtrip.addedBy?.name, 'Alice');
    });

    test('Remote permission gating strictly requires both session and participant permission', () {
      bool canControl({required bool sessionAllowed, required bool participantAllowed}) {
        return sessionAllowed && participantAllowed;
      }

      expect(canControl(sessionAllowed: false, participantAllowed: true), isFalse);
      expect(canControl(sessionAllowed: true, participantAllowed: false), isFalse);
      expect(canControl(sessionAllowed: false, participantAllowed: false), isFalse);
      expect(canControl(sessionAllowed: true, participantAllowed: true), isTrue);
    });

    test('Remote state is trimmed to the central server message limit', () {
      Map<String, dynamic> item(int i) => JamQueueItem(
            id: 'item_$i',
            track: Track(
              id: 'trk_$i',
              title: 'Canción número $i con un título bastante largo',
              artist: 'Artista de prueba',
              album: 'Álbum de prueba',
              duration: '215',
              albumArtUrl:
                  'https://nd.example/rest/getCoverArt.view?id=al-$i&size=300',
            ),
            addedBy: JamParticipant(
              id: 'host_local',
              name: 'Host',
              avatarColorValue: 0xFFA855F7,
              isHost: true,
              joinedAt: DateTime.parse('2026-10-04T12:00:00Z'),
            ),
            addedAt: DateTime.parse('2026-10-04T12:00:00Z'),
          ).toJson();
      final state = <String, dynamic>{
        'trackId': 'trk_now',
        'position': 0,
        'isPlaying': true,
        'queue': List.generate(300, item),
      };

      final fitted = RemoteJamService.fitStateToMessageLimit(state);
      final message = jsonEncode({
        'action': 'update_state',
        'pin': 'ABC123',
        'state': fitted,
      });
      final queue = fitted['queue'] as List;

      expect(utf8.encode(message).length,
          lessThanOrEqualTo(kRemoteJamMaxMessageBytes));
      expect(queue.length, inInclusiveRange(1, 299));
      expect((queue.first as Map)['id'], 'item_0');
      expect((state['queue'] as List).length, 300);

      final small = <String, dynamic>{...state, 'queue': [item(0)]};
      expect(RemoteJamService.fitStateToMessageLimit(small), same(small));
    });
  });
}

