import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/lyrics_service.dart';

void main() {
  test('parseLrc ordena y convierte tiempos', () {
    const lrc =
        '[00:17.12] Hello\n[00:20.500] World\n[01:02] Plain\n[00:20.500][00:25.00] Repeat';
    final lines = LyricsService.parseLrc(lrc);
    expect(lines.length, 5);
    expect(lines.first.text, 'Hello');
    expect(lines.first.start.inMilliseconds, 17120);
    expect(lines.last.text, 'Plain');
    expect(lines.last.start.inMilliseconds, 62000);
  });
}
