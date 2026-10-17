import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/crotolink_security.dart';

void main() {
  test('constantTimeEquals', () {
    expect(constantTimeEquals('abc123', 'abc123'), isTrue);
    expect(constantTimeEquals('abc123', 'abc124'), isFalse);
    expect(constantTimeEquals('abc', 'abcd'), isFalse);
    expect(constantTimeEquals('', ''), isTrue);
  });

  test(
      'CrotoLinkFailureBlocker blocks after N failures and recovers after the window',
      () {
    final b = CrotoLinkFailureBlocker(
        maxFailures: 3, window: const Duration(seconds: 10));
    expect(b.isBlocked(0), isFalse);
    b.recordFailure(0);
    b.recordFailure(1000);
    expect(b.isBlocked(2000), isFalse);
    b.recordFailure(2000);
    expect(b.isBlocked(3000), isTrue);
    expect(b.isBlocked(9999), isTrue);
    expect(b.isBlocked(10500), isFalse); // el primer fallo ya caducó
    b.recordFailure(13000);
    b.reset();
    expect(b.isBlocked(13001), isFalse);
  });
}
