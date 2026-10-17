import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/crotolink_social.dart';

void main() {
  test('sanitizeChatText trims, strips control chars and enforces length', () {
    expect(sanitizeChatText('  hola\u0007 mundo '), 'hola  mundo');
    expect(sanitizeChatText('   '), isNull);
    expect(sanitizeChatText('x' * 280), isNotNull);
    expect(sanitizeChatText('x' * 281), isNull);
  });

  test('chat log keeps only the latest messages', () {
    final log = CrotoLinkChatLog();
    for (var i = 0; i < kCrotoLinkChatKeep + 10; i++) {
      log.add(CrotoLinkChatMessage('a', '$i', DateTime(2026)));
    }
    expect(log.items.length, kCrotoLinkChatKeep);
    expect(log.items.first.text, '10');
  });

  test('reactions expire after their lifetime', () {
    final feed = CrotoLinkReactionFeed();
    final t0 = DateTime(2026, 1, 1, 12);
    feed.add(CrotoLinkReaction('a', '🔥', t0));
    feed.add(CrotoLinkReaction('b', '🎉', t0.add(const Duration(seconds: 3))));
    expect(feed.active(t0.add(const Duration(seconds: 3))).length, 2);
    expect(feed.active(t0.add(const Duration(seconds: 5))).map((r) => r.from),
        ['b']);
    expect(feed.active(t0.add(const Duration(seconds: 9))), isEmpty);
  });
}
