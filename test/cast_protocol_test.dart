import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/cast/cast_protocol.dart';

CastMessage sample([String payload = '{"type":"PING"}']) => CastMessage(
    source: 'sender-0',
    destination: 'receiver-0',
    namespace: CastNamespaces.heartbeat,
    payload: payload);

void main() {
  test('el mensaje protobuf se codifica y decodifica sin pérdida', () {
    final original = sample('{"type":"LOAD","title":"Canción ñ ✓"}');
    final decoded = CastCodec.decodeMessage(CastCodec.encodeMessage(original))!;
    expect(decoded.source, 'sender-0');
    expect(decoded.destination, 'receiver-0');
    expect(decoded.namespace, CastNamespaces.heartbeat);
    expect(decoded.payload, original.payload);
    expect(decoded.type, 'LOAD');
  });

  test('la trama lleva la longitud big-endian y el mensaje', () {
    final frame = CastCodec.encodeFrame(sample());
    final length =
        (frame[0] << 24) | (frame[1] << 16) | (frame[2] << 8) | frame[3];
    expect(length, frame.length - 4);
    expect(frame[4], 0x08, reason: 'campo 1 (protocol_version), varint');
  });

  test('el lector reensambla tramas partidas y varias a la vez', () {
    final a = CastCodec.encodeFrame(sample('{"type":"A"}'));
    final b = CastCodec.encodeFrame(sample('{"type":"B"}'));
    final stream = [...a, ...b];
    final reader = CastCodec.reader();
    final out = <String?>[];
    // En trozos de 5 bytes, como llegaría por TCP.
    for (var i = 0; i < stream.length; i += 5) {
      final end = (i + 5 < stream.length) ? i + 5 : stream.length;
      out.addAll(reader.add(stream.sublist(i, end)).map((m) => m.type));
    }
    expect(out, ['A', 'B']);
  });

  test('un mensaje corrupto o enorme no rompe el lector', () {
    final reader = CastCodec.reader();
    expect(reader.add([0, 0, 0, 3, 1, 2, 3]), isEmpty);
    // Longitud absurda (> 1 MiB): se descarta el búfer.
    expect(reader.add([0x7F, 0xFF, 0xFF, 0xFF, 1, 2]), isEmpty);
    final ok = CastCodec.encodeFrame(sample());
    expect(reader.add(ok), hasLength(1));
  });

  test('LOAD incluye metadatos de música y la URL', () {
    final json = jsonDecode(CastPayloads.load(7,
        url: 'https://s.example.invalid/stream?id=1',
        contentType: 'audio/flac',
        title: 'T',
        artist: 'A',
        album: 'B',
        imageUrl: 'https://s.example.invalid/c.jpg',
        durationSeconds: 120)) as Map<String, dynamic>;
    expect(json['type'], 'LOAD');
    expect(json['requestId'], 7);
    expect(json['autoplay'], true);
    final media = json['media'] as Map<String, dynamic>;
    expect(media['contentId'], 'https://s.example.invalid/stream?id=1');
    expect(media['contentType'], 'audio/flac');
    expect(media['metadata']['metadataType'], 3);
    expect(media['metadata']['artist'], 'A');
    expect(media['metadata']['images'][0]['url'], contains('c.jpg'));
  });

  test('controles y tipos de contenido', () {
    final seek =
        jsonDecode(CastPayloads.mediaControl('SEEK', 3, 9, currentTime: 12.5));
    expect(seek['mediaSessionId'], 9);
    expect(seek['currentTime'], 12.5);
    expect(jsonDecode(CastPayloads.setVolume(1, 3))['volume']['level'], 1.0);
    expect(castContentTypeFor('FLAC'), 'audio/flac');
    expect(castContentTypeFor('opus'), 'audio/ogg');
    expect(castContentTypeFor(null), 'audio/mpeg');
  });
}
