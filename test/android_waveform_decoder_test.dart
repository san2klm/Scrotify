import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crotowave/services/android_waveform_decoder.dart';
import 'package:crotowave/services/waveform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const duration = Duration(seconds: 4); // 4000 ms -> 80 bins
  const expectedBins = 80;

  group('AndroidWaveformDecoder bridge contract', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('awf_bridge_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('decode sends exact contract arguments and parses Float64List output',
        () async {
      MethodCall? capturedCall;
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (call) async {
          capturedCall = call;
          return Float64List.fromList(
            List<double>.generate(expectedBins, (i) => i / expectedBins),
          );
        },
      );

      final result = await decoder.decodeFile(
        '/storage/emulated/0/Music/track.mp3',
        duration: duration,
        bins: expectedBins,
        jobId: 'job-42',
      );

      expect(capturedCall, isNotNull);
      expect(capturedCall!.method, 'decode');
      final args = Map<String, Object?>.from(capturedCall!.arguments as Map);
      expect(args['jobId'], 'job-42');
      expect(args['path'], '/storage/emulated/0/Music/track.mp3');
      expect(args['bins'], expectedBins);
      expect(args['durationUs'], duration.inMicroseconds);
      expect(result, hasLength(expectedBins));
      expect(result.first, 0.0);
      expect(result.last, closeTo(79 / 80, 1e-6));
    });

    test('real digital silence (all zeros) is preserved without error',
        () async {
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (call) async => List<double>.filled(expectedBins, 0.0),
      );

      final result = await decoder.decodeFile(
        '/storage/emulated/0/Music/silence.flac',
        duration: duration,
        bins: expectedBins,
      );

      expect(result, hasLength(expectedBins));
      expect(result.every((v) => v == 0.0), isTrue);
    });

    test('rejects invalid amplitude counts or non-finite/out-of-range values',
        () async {
      for (final badPayload in <Object?>[
        null,
        <double>[],
        List<double>.filled(expectedBins - 1, 0.5),
        List<double>.filled(expectedBins + 1, 0.5),
        [double.nan, ...List<double>.filled(expectedBins - 1, 0.5)],
        [double.infinity, ...List<double>.filled(expectedBins - 1, 0.5)],
        [-0.01, ...List<double>.filled(expectedBins - 1, 0.5)],
        [1.01, ...List<double>.filled(expectedBins - 1, 0.5)],
      ]) {
        final decoder = AndroidWaveformDecoder(
          isSupported: true,
          handler: (_) async => badPayload,
        );

        await expectLater(
          decoder.decodeFile(
            '/storage/emulated/0/Music/bad.mp3',
            duration: duration,
            bins: expectedBins,
          ),
          throwsA(isA<WaveformDecodeException>()),
        );
      }
    });

    test('rejects URLs, relative paths, non-positive duration, and bad bins',
        () async {
      var channelCalled = false;
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (_) async {
          channelCalled = true;
          return List<double>.filled(expectedBins, 0.5);
        },
      );

      await expectLater(
        decoder.decodeFile(
          'https://example.invalid/stream.view?id=1&t=SECRET',
          duration: duration,
          bins: expectedBins,
        ),
        throwsA(isA<WaveformDecodeException>()),
      );
      await expectLater(
        decoder.decodeFile(
          'relative/path/audio.mp3',
          duration: duration,
          bins: expectedBins,
        ),
        throwsA(isA<WaveformDecodeException>()),
      );
      await expectLater(
        decoder.decodeFile(
          '/storage/emulated/0/Music/track.mp3',
          duration: Duration.zero,
          bins: expectedBins,
        ),
        throwsA(isA<WaveformDecodeException>()),
      );
      await expectLater(
        decoder.decodeFile(
          '/storage/emulated/0/Music/track.mp3',
          duration: duration,
          bins: 8,
        ),
        throwsA(isA<WaveformDecodeException>()),
      );
      await expectLater(
        decoder.decodeFile(
          '/storage/emulated/0/Music/track.mp3',
          duration: duration,
          bins: 4096,
        ),
        throwsA(isA<WaveformDecodeException>()),
      );

      expect(channelCalled, isFalse,
          reason: 'invalid arguments must not reach the native channel');
    });

    test('maps native PlatformException codes to safe WaveformFailure kinds',
        () async {
      const cases = <(String, WaveformFailure)>[
        ('unsupported', WaveformFailure.unsupported),
        ('timeout', WaveformFailure.timeout),
        ('cancelled', WaveformFailure.cancelled),
        ('decode_failed', WaveformFailure.unknown),
        ('invalid_arguments', WaveformFailure.unknown),
      ];

      for (final (code, expectedKind) in cases) {
        final decoder = AndroidWaveformDecoder(
          isSupported: true,
          handler: (_) async => throw PlatformException(
            code: code,
            message: 'failed on https://host.invalid/s?u=ana&t=TOPSECRET&s=sal',
          ),
        );

        WaveformDecodeException? caught;
        try {
          await decoder.decodeFile(
            '/storage/emulated/0/Music/track.mp3',
            duration: duration,
            bins: expectedBins,
          );
        } on WaveformDecodeException catch (e) {
          caught = e;
        }

        expect(caught, isNotNull, reason: 'must throw for code $code');
        expect(caught!.kind, expectedKind);
        expect(caught.message, isNot(contains('TOPSECRET')));
        expect(caught.userMessage, isNot(contains('TOPSECRET')));
      }
    });

    test('a late native success cannot revive a cancelled decode', () async {
      final output = Completer<Object?>();
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (call) async => call.method == 'decode' ? output.future : null,
      );
      final result = decoder.decodeFile('/audio.mp3',
          duration: duration, bins: expectedBins, jobId: 'late-success');
      final cancelled = expectLater(
          result,
          throwsA(isA<WaveformDecodeException>()
              .having((e) => e.kind, 'kind', WaveformFailure.cancelled)));
      await decoder.cancel('late-success');
      output.complete(List<double>.filled(expectedBins, 0.5));
      await cancelled;
    });

    test('cancel sends jobId and swallows platform errors safely', () async {
      final calls = <MethodCall>[];
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (call) async {
          calls.add(call);
          if (call.method == 'cancel') {
            throw PlatformException(code: 'error', message: 'already done');
          }
          return null;
        },
      );

      await decoder.cancel('job-99');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'cancel');
      expect(calls.single.arguments, {'jobId': 'job-99'});
    });

    test(
        'decodeBytes writes private temp file with valid extension and cleans up on success and error',
        () async {
      String? seenPath;
      bool? existedDuringCall;

      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        tempDirProvider: () async => tempDir,
        handler: (call) async {
          final args = Map<String, Object?>.from(call.arguments as Map);
          seenPath = args['path'] as String;
          existedDuringCall = File(seenPath!).existsSync();
          return List<double>.filled(expectedBins, 0.25);
        },
      );

      // ID3 header bytes simulating an MP3 stream from Subsonic stream.view
      final mp3Bytes = <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00];
      final out = await decoder.decodeBytes(
        mp3Bytes,
        duration: duration,
        bins: expectedBins,
        fileNameHint: 'stream.view',
        jobId: 'bytes-job-1',
      );

      expect(out, hasLength(expectedBins));
      expect(seenPath, isNotNull);
      expect(seenPath, endsWith('.mp3'));
      expect(existedDuringCall, isTrue);
      expect(File(seenPath!).existsSync(), isFalse,
          reason: 'temp file must be deleted after decode');

      // Also verify cleanup when native decode throws
      String? failedTempPath;
      final failingDecoder = AndroidWaveformDecoder(
        isSupported: true,
        tempDirProvider: () async => tempDir,
        handler: (call) async {
          final args = Map<String, Object?>.from(call.arguments as Map);
          failedTempPath = args['path'] as String;
          throw PlatformException(code: 'decode_failed', message: 'corrupt');
        },
      );

      await expectLater(
        failingDecoder.decodeBytes(
          <int>[0x66, 0x4C, 0x61, 0x43, 0x00, 0x00], // fLaC magic
          duration: duration,
          bins: expectedBins,
        ),
        throwsA(isA<WaveformDecodeException>()),
      );

      expect(failedTempPath, isNotNull);
      expect(failedTempPath, endsWith('.flac'));
      expect(File(failedTempPath!).existsSync(), isFalse,
          reason: 'temp file must be deleted even when decode fails');
    });
  });
}
