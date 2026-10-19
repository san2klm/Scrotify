import 'dart:async';
import 'dart:io';

import 'package:crotowave/services/android_waveform_decoder.dart';
import 'package:crotowave/services/audio_waveform_service.dart';
import 'package:crotowave/services/pcm_waveform_analyzer.dart';
import 'package:crotowave/services/waveform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/wav_synth.dart';

class _CacheDirectoryGate extends Fake implements Directory {
  _CacheDirectoryGate(this.directory);
  final Directory directory;
  final paused = Completer<void>();
  final release = Completer<void>();
  var reads = 0;

  @override
  String get path => directory.path;

  @override
  Future<bool> exists() async {
    if (++reads == 2) {
      paused.complete();
      await release.future;
    }
    return directory.existsSync();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const duration = Duration(seconds: 5); // 5000 ms -> 100 bins
  final expectedBins = PcmWaveformAnalyzer.targetBinsForDuration(duration);

  group('AudioWaveformService on Android', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('awf_service_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'local compressed file >30 MB on Android is decoded directly by path without tooLarge error',
        () async {
      final bigFlac = File('${tempDir.path}/huge_album.flac');
      final raf = bigFlac.openSync(mode: FileMode.write);
      // Write fLaC header and truncate to 31 MB (> 30 MB limit for in-memory read)
      raf.writeFromSync([0x66, 0x4C, 0x61, 0x43, 0x00, 0x00, 0x00, 0x22]);
      raf.truncateSync(31 * 1024 * 1024);
      raf.closeSync();

      final calls = <MethodCall>[];
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        tempDirProvider: () async => tempDir,
        handler: (call) async {
          calls.add(call);
          return List<double>.generate(
            expectedBins,
            (i) => (i / expectedBins).clamp(0.0, 1.0),
          );
        },
      );

      final service = AudioWaveformService(
        cacheDirOverride: tempDir,
        androidDecoder: decoder,
        isAndroid: true,
      );

      final waveform = await service.getWaveform(
        'local-big',
        bigFlac.path,
        duration,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'decode');
      final args = Map<String, Object?>.from(calls.single.arguments as Map);
      expect(args['path'], bigFlac.path,
          reason: 'must pass original local file path without copying');
      expect(args['bins'], expectedBins);
      expect(args['durationUs'], duration.inMicroseconds);
      expect(waveform.amplitudes, hasLength(expectedBins));
    });

    test(
        'remote compressed stream on Android downloads once, decodes via private temp file, never sends URL/secrets to native, and cleans up temp file',
        () async {
      var httpHits = 0;
      final nativeCalls = <MethodCall>[];
      String? decodedTempPath;
      bool? tempExistedDuringDecode;

      final client = MockClient((request) async {
        httpHits++;
        // Return fake MP3 bytes (ID3 header + payload)
        return http.Response.bytes(
          <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 1, 2, 3, 4],
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      });

      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        tempDirProvider: () async => tempDir,
        handler: (call) async {
          nativeCalls.add(call);
          final args = Map<String, Object?>.from(call.arguments as Map);
          decodedTempPath = args['path'] as String;
          tempExistedDuringDecode = File(decodedTempPath!).existsSync();
          return List<double>.filled(expectedBins, 0.6);
        },
      );

      final service = AudioWaveformService(
        httpClient: client,
        cacheDirOverride: tempDir,
        androidDecoder: decoder,
        isAndroid: true,
      );

      const url1 =
          'https://navidrome.example.invalid/rest/stream.view?id=t1&u=ana&t=SECRET_TOKEN&s=SALT1&format=mp3';
      const url2 =
          'https://navidrome.example.invalid/rest/stream.view?id=t1&u=ana&t=ROTATED_TOKEN&s=SALT2&format=mp3';

      // Concurrent requests coalesce
      final results = await Future.wait([
        service.getWaveform('t1', url1, duration),
        service.getWaveform('t1', url1, duration),
      ]);

      expect(httpHits, 1);
      expect(nativeCalls, hasLength(1));
      expect(decodedTempPath, isNotNull);
      expect(decodedTempPath, isNot(contains('SECRET_TOKEN')));
      expect(decodedTempPath, isNot(contains('http')));
      expect(decodedTempPath, endsWith('.mp3'));
      expect(tempExistedDuringDecode, isTrue);
      expect(File(decodedTempPath!).existsSync(), isFalse,
          reason: 'temporary file must be deleted after native decode');
      expect(results[0].amplitudes, results[1].amplitudes);

      // Subsequent request with rotated token uses disk cache v2
      final cached = await service.getWaveform('t1', url2, duration);
      expect(httpHits, 1);
      expect(nativeCalls, hasLength(1));
      expect(cached.amplitudes, results[0].amplitudes);
    });

    test(
        'cancelWaveform cancels active native job, does not cache cancelled result, preserves other cache, and allows retry',
        () async {
      final decodeStarted = Completer<String>();
      final unblockDecode = Completer<void>();
      final cancelledJobs = <String>[];
      var decodeAttempts = 0;

      final client = MockClient((_) async {
        return http.Response.bytes(
          <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 9, 9, 9],
          200,
        );
      });

      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        tempDirProvider: () async => tempDir,
        handler: (call) async {
          final args = Map<String, Object?>.from(call.arguments as Map);
          if (call.method == 'decode') {
            decodeAttempts++;
            final jobId = args['jobId'] as String;
            if (decodeAttempts == 1) {
              decodeStarted.complete(jobId);
              await unblockDecode.future;
              throw PlatformException(code: 'cancelled', message: 'cancelled');
            }
            return List<double>.filled(expectedBins, 0.8);
          }
          if (call.method == 'cancel') {
            cancelledJobs.add(args['jobId'] as String);
            if (!unblockDecode.isCompleted) {
              unblockDecode.complete();
            }
            return null;
          }
          return null;
        },
      );

      final service = AudioWaveformService(
        httpClient: client,
        cacheDirOverride: tempDir,
        androidDecoder: decoder,
        isAndroid: true,
      );

      // First cache a different track 'other' to verify its cache is untouched
      final otherWav = File('${tempDir.path}/other.wav')
        ..writeAsBytesSync(WavSynth.constantToneWav(duration: duration));
      final otherData =
          await service.getWaveform('other', otherWav.path, duration);
      expect(otherData.amplitudes, isNotEmpty);

      // Start slow decode for 't-cancel'
      const streamUrl =
          'https://navidrome.example.invalid/rest/stream.view?id=t-cancel&u=ana&t=tok&s=sal&format=mp3';
      final future1 = service.getWaveform('t-cancel', streamUrl, duration);
      final cancelledResult = expectLater(
        future1,
        throwsA(
          isA<WaveformDecodeException>().having(
            (e) => e.kind,
            'kind',
            WaveformFailure.cancelled,
          ),
        ),
      );
      final firstJobId = await decodeStarted.future;
      await service.cancelWaveform('t-cancel');
      await cancelledResult;
      expect(cancelledJobs, [firstJobId]);

      // Retry for 't-cancel' should succeed and not be blocked or served corrupt cache
      final retried =
          await service.getWaveform('t-cancel', streamUrl, duration);
      expect(retried.amplitudes.first, closeTo(0.8, 1e-6));
      expect(decodeAttempts, 2);

      // 'other' cache is still present
      final otherFiles = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('track_other_'))
          .toList();
      expect(otherFiles, hasLength(1));
    });

    test('cancelling before source identity resolves never starts IO or native',
        () async {
      var httpHits = 0;
      var nativeHits = 0;
      final service = AudioWaveformService(
        httpClient: MockClient((_) async {
          httpHits++;
          return http.Response.bytes([0x49, 0x44, 0x33], 200);
        }),
        cacheDirOverride: tempDir,
        isAndroid: true,
        androidDecoder: AndroidWaveformDecoder(
          isSupported: true,
          handler: (_) async {
            nativeHits++;
            return List<double>.filled(expectedBins, 0.5);
          },
        ),
      );
      final future = service.getWaveform(
          'immediate', 'https://example.invalid/stream.mp3', duration);
      final cancelled = expectLater(
          future,
          throwsA(isA<WaveformDecodeException>()
              .having((e) => e.kind, 'kind', WaveformFailure.cancelled)));
      await service.cancelWaveform('immediate');
      await cancelled;
      expect(httpHits, 0);
      expect(nativeHits, 0);
    });

    test(
        'aborting slow downloads releases analysis slots and allows next track',
        () async {
      final ready = Completer<void>();
      final bodies = <StreamController<List<int>>>[];
      final aborts = <Future<void>>[];
      var nativeHits = 0;
      final client = MockClient.streaming((request, _) async {
        if (request.url.path.startsWith('/slow')) {
          final body = StreamController<List<int>>();
          bodies.add(body);
          if (request is http.AbortableRequest) {
            aborts.add(request.abortTrigger!.then((_) {
              if (!body.isClosed) {
                body.addError(http.RequestAbortedException(request.url));
                unawaited(body.close());
              }
            }));
          }
          if (bodies.length == 2) ready.complete();
          return http.StreamedResponse(body.stream, 200);
        }
        return http.StreamedResponse(
            Stream.value([0x49, 0x44, 0x33, 0x04]), 200);
      });
      final service = AudioWaveformService(
        httpClient: client,
        cacheDirOverride: tempDir,
        isAndroid: true,
        androidDecoder: AndroidWaveformDecoder(
          isSupported: true,
          tempDirProvider: () async => tempDir,
          handler: (_) async {
            nativeHits++;
            return List<double>.filled(expectedBins, 0.5);
          },
        ),
      );
      Future<WaveformFailure?> slow(String id) => service
          .getWaveform(id, 'https://example.invalid/$id.mp3', duration)
          .then<WaveformFailure?>((_) => null,
              onError: (Object e) => e is WaveformDecodeException
                  ? e.kind
                  : WaveformFailure.unknown);
      final first = slow('slow1');
      final second = slow('slow2');
      try {
        await ready.future.timeout(const Duration(seconds: 3));
        expect(aborts, hasLength(2),
            reason: 'both HTTP requests must be abortable');
        await service.cancelWaveform();
        expect(await first, WaveformFailure.cancelled);
        expect(await second, WaveformFailure.cancelled);
        await Future.wait(aborts).timeout(const Duration(seconds: 3));
        final next = await service
            .getWaveform('next', 'https://example.invalid/fast.mp3', duration)
            .timeout(const Duration(seconds: 3));
        expect(next.amplitudes, hasLength(expectedBins));
        expect(nativeHits, 1, reason: 'cancelled downloads must never decode');
      } finally {
        await service.cancelWaveform();
        for (final body in bodies) {
          if (!body.isClosed) await body.close();
        }
        await Future.wait([first, second]);
        client.close();
      }
    });

    test('cancelling during cache preparation never publishes the result',
        () async {
      final gate = _CacheDirectoryGate(tempDir);
      final sentinel = File('${tempDir.path}/keep.json')
        ..writeAsStringSync('keep');
      final service = AudioWaveformService(
        cacheDirOverride: gate,
        httpClient: MockClient(
            (_) async => http.Response.bytes([0x49, 0x44, 0x33], 200)),
        isAndroid: true,
        androidDecoder: AndroidWaveformDecoder(
          isSupported: true,
          tempDirProvider: () async => tempDir,
          handler: (_) async => List<double>.filled(expectedBins, 0.5),
        ),
      );
      final future = service.getWaveform(
          'cache-cancel', 'https://example.invalid/stream.mp3', duration);
      final cancelled = expectLater(
          future,
          throwsA(isA<WaveformDecodeException>()
              .having((e) => e.kind, 'kind', WaveformFailure.cancelled)));
      await gate.paused.future;
      await service.cancelWaveform('cache-cancel');
      await cancelled;
      gate.release.complete();
      // The gate resumes entirely in microtasks; a turn drains the cancellation
      // checkpoint. Poll through the old async filesystem write to reproduce it.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
          tempDir
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .where((p) => p.contains('track_cache-cancel_')),
          isEmpty);
      expect(sentinel.readAsStringSync(), 'keep');
    });

    test('WAV on Android still uses pure-Dart WavDecoder without native call',
        () async {
      var nativeCalled = false;
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (_) async {
          nativeCalled = true;
          return List<double>.filled(expectedBins, 0.5);
        },
      );

      final service = AudioWaveformService(
        cacheDirOverride: tempDir,
        androidDecoder: decoder,
        isAndroid: true,
      );

      final wavFile = File('${tempDir.path}/local.wav')
        ..writeAsBytesSync(WavSynth.silenceToneSilenceWav(duration: duration));
      final wave = await service.getWaveform('wav-1', wavFile.path, duration);

      expect(nativeCalled, isFalse,
          reason: 'WAV must keep using pure-Dart WavDecoder on Android');
      expect(wave.amplitudes, hasLength(expectedBins));
    });

    test('Desktop (isAndroid: false) does not invoke AndroidWaveformDecoder',
        () async {
      var nativeCalled = false;
      final decoder = AndroidWaveformDecoder(
        isSupported: true,
        handler: (_) async {
          nativeCalled = true;
          return List<double>.filled(expectedBins, 0.5);
        },
      );

      final service = AudioWaveformService(
        cacheDirOverride: tempDir,
        androidDecoder: decoder,
        isAndroid: false,
      );

      final wavFile = File('${tempDir.path}/desktop.wav')
        ..writeAsBytesSync(WavSynth.constantToneWav(duration: duration));
      final wave = await service.getWaveform('desk-1', wavFile.path, duration);

      expect(nativeCalled, isFalse);
      expect(wave.amplitudes, hasLength(expectedBins));
    });
  });
}
