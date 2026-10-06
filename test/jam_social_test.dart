import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/jam_social.dart';

void main() {
  test('sanitizeChatText trims, strips control chars and enforces length', () {
    expect(sanitizeChatText('  hola\u0007 mundo '), 'hola  mundo');
    expect(sanitizeChatText('   '), isNull);
    expect(sanitizeChatText('x' * 280), isNotNull);
    expect(sanitizeChatText('x' * 281), isNull);
  });

  test('chat log keeps only the latest messages', () {
    final log = JamChatLog();
    for (var i = 0; i < kJamChatKeep + 10; i++) {
      log.add(JamChatMessage('a', '$i', DateTime(2026)));
    }
    expect(log.items.length, kJamChatKeep);
    expect(log.items.first.text, '10');
  });

  test('reactions expire after their lifetime', () {
    final feed = JamReactionFeed();
    final t0 = DateTime(2026, 1, 1, 12);
    feed.add(JamReaction('a', '🔥', t0));
    feed.add(JamReaction('b', '🎉', t0.add(const Duration(seconds: 3))));
    expect(feed.active(t0.add(const Duration(seconds: 3))).length, 2);
    expect(feed.active(t0.add(const Duration(seconds: 5))).map((r) => r.from), ['b']);
    expect(feed.active(t0.add(const Duration(seconds: 9))), isEmpty);
  });
}
