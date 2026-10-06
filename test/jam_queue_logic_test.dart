import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/jam_models.dart';
import 'package:navidrome_client/services/jam_queue_logic.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

JamParticipant p(String id) => JamParticipant(
    id: id,
    name: id,
    avatarColorValue: 0,
    isHost: false,
    joinedAt: DateTime(2026));

JamQueueItem item(String id, String by, {int votes = 0, bool pinned = false, int t = 0}) =>
    JamQueueItem(
      id: id,
      track: Track(id: id, title: id, artist: '', album: '', duration: '0'),
      addedBy: p(by),
      addedAt: DateTime(2026, 1, 1, 0, 0, t),
      votes: votes,
      pinned: pinned,
    );

List<String> ids(List<JamQueueItem> l) => l.map((e) => e.id).toList();

void main() {
  group('fairTurns', () {
    test('a user with 30 songs does not monopolize the queue', () {
      final items = [
        for (var i = 0; i < 30; i++) item('a$i', 'A', t: i),
        item('b0', 'B', t: 40),
        item('c0', 'C', t: 41),
      ];
      final out = orderQueue(items, mode: JamQueueMode.fairTurns);
      expect(ids(out).take(6), ['a0', 'b0', 'c0', 'a1', 'a2', 'a3']);
      expect(out.length, 32);
    });

    test('blocks of N per person and stable within each person', () {
      final items = [
        item('a0', 'A'), item('a1', 'A'), item('a2', 'A'),
        item('b0', 'B'), item('b1', 'B'),
      ];
      final out = orderQueue(items,
          mode: JamQueueMode.fairTurns, fairTurnsPerPerson: 2);
      expect(ids(out), ['a0', 'a1', 'b0', 'b1', 'a2']);
    });

    test('pinned items stay first and are not reordered', () {
      final items = [
        item('a0', 'A'), item('a1', 'A'),
        item('b0', 'B', pinned: true), item('b1', 'B'),
      ];
      final out = orderQueue(items, mode: JamQueueMode.fairTurns);
      expect(ids(out), ['b0', 'a0', 'b1', 'a1']);
    });

    test('is idempotent', () {
      final items = [item('a0', 'A'), item('a1', 'A'), item('b0', 'B')];
      final once = orderQueue(items, mode: JamQueueMode.fairTurns);
      expect(ids(orderQueue(once, mode: JamQueueMode.fairTurns)), ids(once));
    });
  });

  group('voting', () {
    test('sorts by votes desc, ties by addedAt', () {
      final items = [
        item('x', 'A', votes: 1, t: 1),
        item('y', 'B', votes: 3, t: 5),
        item('z', 'C', votes: 1, t: 0),
      ];
      expect(ids(orderQueue(items, mode: JamQueueMode.voting)), ['y', 'z', 'x']);
    });

    test('pinned items ignore votes', () {
      final items = [
        item('x', 'A', votes: 0, pinned: true),
        item('y', 'B', votes: 9),
      ];
      expect(ids(orderQueue(items, mode: JamQueueMode.voting)), ['x', 'y']);
    });

    test('free and approval keep arrival order', () {
      final items = [item('x', 'A', votes: 1), item('y', 'B', votes: 9)];
      expect(ids(orderQueue(items, mode: JamQueueMode.free)), ['x', 'y']);
      expect(ids(orderQueue(items, mode: JamQueueMode.approval)), ['x', 'y']);
    });
  });

  group('JamVoteBook', () {
    test('one vote per participant per item; change and remove', () {
      final b = JamVoteBook();
      expect(b.vote('i', 'u1', 1), isTrue);
      expect(b.vote('i', 'u1', 1), isFalse);
      expect(b.vote('i', 'u2', 1), isTrue);
      expect(b.total('i'), 2);
      expect(b.vote('i', 'u1', -1), isTrue);
      expect(b.total('i'), 0);
      expect(b.myVote('i', 'u1'), -1);
      expect(b.vote('i', 'u1', 0), isTrue);
      expect(b.total('i'), 1);
      expect(b.vote('i', 'u1', 5), isTrue); // se acota a +1
      expect(b.myVote('i', 'u1'), 1);
    });
  });

  group('reorderMoves', () {
    test('transforms current into target', () {
      final current = ['a', 'b', 'c', 'd', 'e'];
      final target = ['c', 'a', 'e', 'b', 'd'];
      final work = List.of(current);
      for (final (from, to) in reorderMoves(current, target)) {
        work.insert(to, work.removeAt(from));
      }
      expect(work, target);
    });

    test('no moves when already ordered', () {
      expect(reorderMoves(['a', 'b'], ['a', 'b']), isEmpty);
    });
  });

  test('JamQueueItem/Request/State roundtrip with new fields', () {
    final i = item('a', 'A', votes: 2, pinned: true);
    final back = JamQueueItem.fromJson(i.toJson());
    expect(back.votes, 2);
    expect(back.pinned, isTrue);
    // Cliente viejo: sin campos nuevos → valores por defecto.
    final old = JamQueueItem.fromJson(
        (i.toJson()..remove('votes')..remove('pinned')));
    expect(old.votes, 0);
    expect(old.pinned, isFalse);

    final r = JamQueueRequest(
        id: 'r1',
        track: i.track,
        requestedById: 'A',
        requestedByName: 'Ana',
        requestedAt: DateTime(2026));
    final s = JamSessionState(
      sessionId: 's', pinCode: 'ABC234', hostName: 'h', hostIp: '', port: 0,
      mode: JamMode.partySpeaker, isPlaying: false, positionMs: 0,
      updatedAtMs: 0, queue: [i], participants: const [],
      queueMode: JamQueueMode.voting, fairTurnsPerPerson: 3,
      requireApproval: true, pendingRequests: [r],
    );
    final s2 = JamSessionState.fromJson(s.toJson());
    expect(s2.queueMode, JamQueueMode.voting);
    expect(s2.fairTurnsPerPerson, 3);
    expect(s2.approvalActive, isTrue);
    expect(s2.pendingRequests.single.requestedByName, 'Ana');
    expect(JamSessionState.fromJson({'queueMode': 'bogus'}).queueMode,
        JamQueueMode.free);
  });
}
