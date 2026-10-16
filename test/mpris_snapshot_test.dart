import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/mpris_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

void main() {
  test('el estado MPRIS refleja pista y reproducción', () {
    final track =
        Track(id: '1', title: 'T', artist: 'A', album: 'B', duration: '100');
    final playing = MprisService.snapshot(track,
        playing: true, position: const Duration(seconds: 2));
    expect(playing['PlaybackStatus'], 'Playing');
    expect(playing['Position'], 2000000);
    expect(playing['xesam:title'], 'T');
    expect(playing['xesam:artist'], ['A']);

    expect(
        MprisService.snapshot(track,
            playing: false, position: Duration.zero)['PlaybackStatus'],
        'Paused');
    expect(
        MprisService.snapshot(null,
            playing: false, position: Duration.zero)['PlaybackStatus'],
        'Stopped');
  });
}
