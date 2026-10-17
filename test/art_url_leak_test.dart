import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/connect/track_codec.dart';
import 'package:crotowave/services/crotolink_guest_service.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/remote_crotolink_service.dart';

void main() {
  final track = Track(
    id: '1',
    title: 'T',
    artist: 'A',
    album: 'B',
    duration: '10',
    albumArtUrl:
        'https://musica.example.invalid/rest/getCoverArt.view?id=al-1&u=ana&t=secreto&s=sal',
  );

  void expectNoCredentials(String? url) {
    expect(url, contains('id=al-1'));
    final q = Uri.parse(url!).queryParameters;
    expect(q.containsKey('u'), isFalse);
    expect(q.containsKey('t'), isFalse);
    expect(q.containsKey('s'), isFalse);
    expect(url, isNot(contains('secreto')));
  }

  test('add_to_queue del invitado no lleva u, s ni t', () {
    expectNoCredentials(
        CrotoLinkGuestService.addToQueueTrackJson(track)['albumArtUrl']
            as String?);
  });

  test('el codec de Connect no envía u, s ni t', () {
    expectNoCredentials(trackToConnectJson(track)['albumArtUrl'] as String?);
  });

  test('join_room remoto incluye la clave de la sala', () {
    final msg = RemoteCrotoLinkService.buildJoinRoomMessage(
        pin: '123456', guestName: 'Ana', roomPassword: 'clave1');
    expect(msg['roomPassword'], 'clave1');
    expect(
        RemoteCrotoLinkService.buildJoinRoomMessage(pin: '1', guestName: 'a')
            .containsKey('roomPassword'),
        isFalse);
  });

  test('terminar el CrotoLink remoto envía close_room', () {
    expect(RemoteCrotoLinkService.closeRoomMessage['action'], 'close_room');
  });

  test('la espera de reconexión crece, lleva jitter y se topa en 60 s', () {
    final ms = [
      for (var i = 0; i < 10; i++)
        RemoteCrotoLinkService.reconnectDelay(i).inMilliseconds
    ];
    expect(ms[0], inInclusiveRange(1000, 2000));
    expect(ms[3], inInclusiveRange(8000, 9000));
    for (final x in ms) {
      expect(x, lessThanOrEqualTo(61000));
    }
    expect(ms[9], greaterThanOrEqualTo(60000));
  });
}
