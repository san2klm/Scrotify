import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/models/crotolink_models.dart';
import 'package:crotowave/services/crotolink_history.dart';
import 'package:crotowave/services/navidrome_service.dart';

Track t(String id, {String duration = '200'}) =>
    Track(id: id, title: id, artist: 'x', album: 'y', duration: duration);

CrotoLinkParticipant p(String id) => CrotoLinkParticipant(
    id: id,
    name: 'n$id',
    avatarColorValue: 0,
    isHost: false,
    joinedAt: DateTime(2026));

void main() {
  test('skipped tracks (< 30 s and < 50 %) are not recorded', () {
    final h = CrotoLinkHistory();
    expect(
        h.record(t('a'), p('1'),
            listened: const Duration(seconds: 5),
            total: const Duration(seconds: 200)),
        isFalse);
    expect(h.isEmpty, isTrue);
  });

  test('30 s or 50 % qualifies', () {
    final h = CrotoLinkHistory();
    expect(
        h.record(t('a'), p('1'),
            listened: const Duration(seconds: 30),
            total: const Duration(seconds: 200)),
        isTrue);
    expect(
        h.record(t('b', duration: '40'), p('1'),
            listened: const Duration(seconds: 20),
            total: const Duration(seconds: 40)),
        isTrue);
    expect(
        h.record(t('c'), p('1'),
            listened: const Duration(seconds: 29), total: null),
        isFalse);
    expect(h.entries.map((e) => e.track.id), ['a', 'b']);
  });

  test('keeps play order and filters by participant', () {
    final h = CrotoLinkHistory();
    for (final (id, by) in [('a', '1'), ('b', '2'), ('c', '1')]) {
      h.record(t(id), p(by), listened: const Duration(minutes: 1));
    }
    expect(h.entries.map((e) => e.track.id), ['a', 'b', 'c']);
    expect(h.byParticipant('1').map((e) => e.track.id), ['a', 'c']);
  });

  test('summary: top contributor, total duration, most voted', () {
    final h = CrotoLinkHistory();
    h.record(t('a', duration: '100'), p('1'),
        listened: const Duration(minutes: 1), votes: 1);
    h.record(t('b', duration: '2:00'), p('2'),
        listened: const Duration(minutes: 1), votes: 4);
    h.record(t('c', duration: '60'), p('1'),
        listened: const Duration(minutes: 1));
    final s = h.summary();
    expect(s.trackCount, 3);
    expect(s.totalDuration, const Duration(seconds: 280));
    expect(s.topContributor, 'n1');
    expect(s.topContributorCount, 2);
    expect(s.mostVoted?.id, 'b');
    expect(s.mostVotes, 4);
  });

  test('parseTrackDuration handles seconds, m:ss and garbage', () {
    expect(parseTrackDuration('215'), const Duration(seconds: 215));
    expect(parseTrackDuration('3:05'), const Duration(minutes: 3, seconds: 5));
    expect(parseTrackDuration('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(parseTrackDuration(''), isNull);
    expect(parseTrackDuration('x:y'), isNull);
  });
}
