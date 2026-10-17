import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crotowave/services/audio_waveform_service.dart';
import 'package:crotowave/services/waveform_service.dart';

void main() {
  test('un fallo de descarga no deja u/t/s en el mensaje de error', () async {
    final tmp = await Directory.systemTemp.createTemp('wf-');
    addTearDown(() => tmp.delete(recursive: true));
    final uri = Uri.parse(
        'https://musica.example.invalid/rest/stream.view?id=1&u=ana&t=SECRETO&s=sal');
    final service = AudioWaveformService(
      httpClient:
          MockClient((_) async => throw http.ClientException('boom', uri)),
      cacheDirOverride: tmp,
    );
    Object? error;
    try {
      await service.getWaveform(
          't1', uri.toString(), const Duration(seconds: 30));
    } catch (e) {
      error = e;
    }
    expect(error, isA<WaveformDecodeException>());
    expect('$error', isNot(contains('SECRETO')));
  });

  test('un Content-Length enorme se rechaza sin bajar el cuerpo', () async {
    final tmp = await Directory.systemTemp.createTemp('wf-');
    addTearDown(() => tmp.delete(recursive: true));
    var consumed = false;
    final client = MockClient.streaming((req, _) async {
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          [1, 2, 3]
        ]).map((c) {
          consumed = true;
          return c;
        }),
        200,
        contentLength: 10 * 1024 * 1024 * 1024,
      );
    });
    final service =
        AudioWaveformService(httpClient: client, cacheDirOverride: tmp);
    await expectLater(
        service.getWaveform('t2', 'https://h.example.invalid/s?id=2',
            const Duration(seconds: 30)),
        throwsA(isA<WaveformDecodeException>()));
    expect(consumed, isFalse);
  });
}
