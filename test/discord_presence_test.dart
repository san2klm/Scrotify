import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/discord_presence.dart';
import 'package:crotowave/services/navidrome_service.dart';

class _FakeTransport implements DiscordIpcTransport {
  _FakeTransport({this.available = true});

  final bool available;
  final frames = <List<int>>[];
  bool closed = false;
  bool failWrites = false;

  @override
  Future<bool> connect() async => available;

  @override
  Future<void> write(List<int> bytes) async {
    if (failWrites) throw StateError('tubería rota');
    frames.add(bytes);
  }

  @override
  Future<void> close() async => closed = true;
}

Track track({String title = 'Bohemian Rhapsody'}) => Track(
    id: '1',
    title: title,
    artist: 'Queen',
    album: 'A Night at the Opera',
    duration: '354');

void main() {
  test('la trama IPC lleva opcode y longitud little-endian', () {
    final bytes = DiscordRichPresence.encodeFrame(
        DiscordRichPresence.opHandshake, {'v': 1, 'client_id': '123'});
    expect(bytes.sublist(0, 4), [0, 0, 0, 0]);
    final length = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16);
    expect(length, bytes.length - 8);
    final decoded = DiscordRichPresence.decodeFrame(bytes)!;
    expect(decoded.op, 0);
    expect(decoded.data['client_id'], '123');
  });

  test('una trama truncada o corrupta no se decodifica', () {
    final bytes = DiscordRichPresence.encodeFrame(1, {'a': 1});
    expect(DiscordRichPresence.decodeFrame(bytes.sublist(0, 10)), isNull);
    expect(DiscordRichPresence.decodeFrame([1, 2, 3]), isNull);
  });

  test('la actividad respeta el formato de Discord', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000000);
    final playing = DiscordRichPresence.buildActivity(track(),
        playing: true, position: const Duration(seconds: 30), now: now);
    expect(playing['type'], 2);
    expect(playing['details'], 'Bohemian Rhapsody');
    expect(playing['state'], 'Queen');
    expect(playing['timestamps']['start'], 1000000 - 30000);

    final paused = DiscordRichPresence.buildActivity(track(),
        playing: false, position: const Duration(seconds: 30), now: now);
    expect(paused.containsKey('timestamps'), isFalse);

    final longTitle = DiscordRichPresence.buildActivity(track(title: 'x' * 300),
        playing: true);
    expect((longTitle['details'] as String).length, lessThanOrEqualTo(128));
    final shortTitle =
        DiscordRichPresence.buildActivity(track(title: 'A'), playing: true);
    expect((shortTitle['details'] as String).length, greaterThanOrEqualTo(2));
  });

  test('sin Application ID o sin Discord abierto no escribe nada', () async {
    final noId = _FakeTransport();
    expect(await DiscordRichPresence(clientId: '', transport: noId).start(),
        isFalse);
    expect(noId.frames, isEmpty);

    final noDiscord = _FakeTransport(available: false);
    expect(
        await DiscordRichPresence(clientId: '9', transport: noDiscord).start(),
        isFalse);
  });

  test('saludo, actividad y limpieza al parar', () async {
    final transport = _FakeTransport();
    final presence = DiscordRichPresence(clientId: '42', transport: transport);
    await presence.update(track(), playing: true);
    expect(transport.frames, hasLength(2));
    expect(DiscordRichPresence.decodeFrame(transport.frames[0])!.op, 0);
    final set = DiscordRichPresence.decodeFrame(transport.frames[1])!.data;
    expect(set['cmd'], 'SET_ACTIVITY');
    expect(set['args']['activity']['details'], 'Bohemian Rhapsody');

    await presence.stop();
    final last = DiscordRichPresence.decodeFrame(transport.frames.last)!.data;
    expect(last['args']['activity'], isNull, reason: 'se borra la actividad');
    expect(transport.closed, isTrue);
  });

  test('si Discord se cierra, un fallo de escritura no lanza', () async {
    final transport = _FakeTransport();
    final presence = DiscordRichPresence(clientId: '42', transport: transport);
    await presence.start();
    transport.failWrites = true;
    await presence.update(track(), playing: true);
    expect(presence.isConnected, isFalse);
    expect(jsonEncode({'ok': true}), isNotEmpty);
  });
}
