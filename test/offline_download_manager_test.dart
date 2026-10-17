import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/offline_cache_service.dart';
import 'package:crotowave/services/offline_download_manager.dart';
import 'package:crotowave/services/settings_controller.dart';
import 'package:path/path.dart' as p;

/// Mock HTTP client implementing [http.BaseClient] for isolated Navidrome tests.
class _MockStreamingHttpClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  _MockStreamingHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

/// Fake transport enabling precise control of chunks, delays, gating completers, and errors.
class _ControlledFakeTransport implements DownloadTransport {
  final Map<String, Completer<void>> _pauseGates = {};
  final Map<String, int> callCounts = {};
  final Map<String, Exception> errorsToThrow = {};
  final Map<String, List<int>> payloads = {};

  /// Transferencias en curso ahora mismo.
  int inFlight = 0;

  void setPayload(String trackId, List<int> bytes) {
    payloads[trackId] = bytes;
  }

  void setError(String trackId, Exception error) {
    errorsToThrow[trackId] = error;
  }

  Completer<void> gate(String trackId) {
    final c = Completer<void>();
    _pauseGates[trackId] = c;
    return c;
  }

  void releaseGate(String trackId) {
    _pauseGates[trackId]?.complete();
    _pauseGates.remove(trackId);
  }

  @override
  Future<void> download({
    required String serverScope,
    required String trackId,
    required File destinationFile,
    String? sourceMarker,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    inFlight++;
    try {
      await _download(trackId, destinationFile, onProgress, isCancelled);
    } finally {
      inFlight--;
    }
  }

  Future<void> _download(
    String trackId,
    File destinationFile,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
  ) async {
    callCounts[trackId] = (callCounts[trackId] ?? 0) + 1;

    // Check for configured error
    if (errorsToThrow.containsKey(trackId)) {
      final err = errorsToThrow.remove(trackId)!;
      throw err;
    }

    // Wait on gate if present
    if (_pauseGates.containsKey(trackId)) {
      await _pauseGates[trackId]!.future;
    }

    if (isCancelled != null && isCancelled()) {
      throw const DownloadException(
        'Download cancelled',
        category: DownloadFailureCategory.cancelled,
      );
    }

    final data = payloads[trackId] ?? List.filled(512, 42);
    if (!await destinationFile.parent.exists()) {
      await destinationFile.parent.create(recursive: true);
    }

    final sink = destinationFile.openWrite();
    try {
      const chunkSize = 64;
      for (int i = 0; i < data.length; i += chunkSize) {
        if (isCancelled != null && isCancelled()) {
          throw const DownloadException(
            'Download cancelled',
            category: DownloadFailureCategory.cancelled,
          );
        }
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        sink.add(data.sublist(i, end));
        onProgress?.call(end, data.length);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}

void main() {
  group('OfflineDownloadManager unit tests', () {
    late Directory tempDir;
    late InMemoryOfflineCacheMetadataStore metadataStore;
    late OfflineCacheService cacheService;
    late _ControlledFakeTransport fakeTransport;
    late OfflineDownloadManager manager;

    Track createTestTrack({
      required String id,
      String title = 'Test Track',
      String artist = 'Test Artist',
      String album = 'Test Album',
      String duration = '180',
    }) {
      return Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      );
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('download_mgr_test_');
      metadataStore = InMemoryOfflineCacheMetadataStore();
      cacheService = OfflineCacheService(
        cacheRootDir: tempDir,
        metadataStore: metadataStore,
      );
      await cacheService.initialize();

      fakeTransport = _ControlledFakeTransport();
      manager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: fakeTransport,
        maxConcurrency: 2,
      );
      await manager.initialize();
    });

    tearDown(() async {
      manager.dispose();
      await cacheService.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Future<void> waitForStatus(
      String scope,
      String id,
      DownloadTaskStatus status, {
      Duration timeout = const Duration(seconds: 3),
    }) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        final t = manager.getTask(scope, id);
        if (t != null && t.status == status) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    /// Espera por condición (no por tiempo): el límite solo evita un cuelgue.
    Future<void> waitUntil(bool Function() ok, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail('Nunca ocurrió: $what');
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    /// La tarea llegó a un estado final.
    Future<void> waitDone(String scope, String id) => waitUntil(() {
          final status = manager.getTask(scope, id)?.status;
          return status == DownloadTaskStatus.completed ||
              status == DownloadTaskStatus.failed ||
              status == DownloadTaskStatus.cancelled;
        }, 'la tarea $id termina');

    /// El transporte ya empezó a descargar [id].
    Future<void> started(String id) => waitUntil(
        () => (fakeTransport.callCounts[id] ?? 0) >= 1,
        'el transporte empieza a descargar $id');

    /// No queda ninguna transferencia en curso y se procesaron sus efectos.
    Future<void> transportIdle() async {
      await waitUntil(
          () => fakeTransport.inFlight == 0, 'el transporte queda libre');
      await pumpEventQueue();
    }

    test(
        'concurrency ceiling: enforces maxConcurrency and processes next in queue',
        () async {
      const serverScope = 'https://server-concurrency.local';

      // Gate all 4 tracks so they pause during download
      final gate1 = fakeTransport.gate('track-1');
      final gate2 = fakeTransport.gate('track-2');
      final gate3 = fakeTransport.gate('track-3');
      final gate4 = fakeTransport.gate('track-4');

      final t1 = createTestTrack(id: 'track-1');
      final t2 = createTestTrack(id: 'track-2');
      final t3 = createTestTrack(id: 'track-3');
      final t4 = createTestTrack(id: 'track-4');

      await manager.queueTrack(t1, serverScope: serverScope);
      await manager.queueTrack(t2, serverScope: serverScope);
      await manager.queueTrack(t3, serverScope: serverScope);
      await manager.queueTrack(t4, serverScope: serverScope);

      // Wait for downloads to enter downloading status
      await waitForStatus(
          serverScope, 'track-1', DownloadTaskStatus.downloading);
      await waitForStatus(
          serverScope, 'track-2', DownloadTaskStatus.downloading);

      // With maxConcurrency=2, exactly 2 should be downloading, 2 queued
      expect(manager.activeCount, 2);
      expect(manager.queuedCount, 2);

      final task1 = manager.getTask(serverScope, 'track-1')!;
      final task2 = manager.getTask(serverScope, 'track-2')!;
      final task3 = manager.getTask(serverScope, 'track-3')!;
      final task4 = manager.getTask(serverScope, 'track-4')!;

      expect(task1.status, DownloadTaskStatus.downloading);
      expect(task2.status, DownloadTaskStatus.downloading);
      expect(task3.status, DownloadTaskStatus.queued);
      expect(task4.status, DownloadTaskStatus.queued);

      // Release gate 1 -> track 1 finishes, freeing a slot for track 3
      gate1.complete();
      await waitForStatus(serverScope, 'track-1', DownloadTaskStatus.completed);
      await waitForStatus(
          serverScope, 'track-3', DownloadTaskStatus.downloading);

      expect(manager.getTask(serverScope, 'track-1')!.status,
          DownloadTaskStatus.completed);
      expect(manager.getTask(serverScope, 'track-3')!.status,
          DownloadTaskStatus.downloading);
      expect(manager.activeCount, 2); // track-2 and track-3

      // Release remaining gates
      gate2.complete();
      gate3.complete();
      gate4.complete();

      await waitForStatus(serverScope, 'track-2', DownloadTaskStatus.completed);
      await waitForStatus(serverScope, 'track-3', DownloadTaskStatus.completed);
      await waitForStatus(serverScope, 'track-4', DownloadTaskStatus.completed);

      expect(manager.activeCount, 0);
      expect(manager.queuedCount, 0);
      expect(manager.getTask(serverScope, 'track-2')!.status,
          DownloadTaskStatus.completed);
      expect(manager.getTask(serverScope, 'track-3')!.status,
          DownloadTaskStatus.completed);
      expect(manager.getTask(serverScope, 'track-4')!.status,
          DownloadTaskStatus.completed);
    });

    test(
        'progress/completion: updates byte counts, atomic transfer, and registers verified C1 file',
        () async {
      const serverScope = 'https://server-progress.local';
      const trackId = 'progress-track';
      final track = createTestTrack(
        id: trackId,
        title: 'Progressive Tune',
        artist: 'Progress Artist',
        album: 'Progress Album',
        duration: '120',
      );

      final testBytes = List<int>.generate(256, (i) => i % 256);
      fakeTransport.setPayload(trackId, testBytes);

      final progressEvents = <int>[];
      manager.addListener(() {
        final t = manager.getTask(serverScope, trackId);
        if (t != null && t.downloadedBytes > 0) {
          progressEvents.add(t.downloadedBytes);
        }
      });

      final task = await manager.queueTrack(
        track,
        serverScope: serverScope,
        sourceMarker: 'lossless',
      );
      expect(task.status,
          anyOf(DownloadTaskStatus.queued, DownloadTaskStatus.downloading));

      // Wait for completion
      await waitUntil(
          () =>
              manager.getTask(serverScope, trackId)?.status ==
              DownloadTaskStatus.completed,
          'la descarga se completa');

      final completedTask = manager.getTask(serverScope, trackId)!;
      expect(completedTask.status, DownloadTaskStatus.completed);
      expect(completedTask.downloadedBytes, 256);
      expect(completedTask.totalBytes, 256);
      expect(completedTask.progress, 1.0);
      expect(progressEvents, isNotEmpty);

      // Verify C1 cache registration
      final verifiedEntry = await cacheService.lookup(serverScope, trackId);
      expect(verifiedEntry, isNotNull);
      expect(verifiedEntry!.byteSize, 256);
      expect(verifiedEntry.title, 'Progressive Tune');
      expect(verifiedEntry.artist, 'Progress Artist');
      expect(verifiedEntry.durationSeconds, 120);
      expect(verifiedEntry.sourceMarker, 'lossless');

      // Verify temp directory contains no leftover partial files
      final tmpDir = Directory(p.join(tempDir.path, 'download_tmp'));
      if (tmpDir.existsSync()) {
        final leftOvers = tmpDir.listSync();
        expect(leftOvers, isEmpty);
      }
    });

    test(
        'duplicate coalescing: returns existing nonterminal task and avoids duplicate transfers',
        () async {
      const serverScope = 'https://server-dup.local';
      const trackId = 'dup-track';
      final gate = fakeTransport.gate(trackId);

      final track = createTestTrack(id: trackId);

      final task1 = await manager.queueTrack(track, serverScope: serverScope);
      final task2 = await manager.queueTrack(track, serverScope: serverScope);

      expect(identical(task1, task2) || task1.compoundKey == task2.compoundKey,
          isTrue);
      expect(manager.tasks.length, 1);

      await started(trackId);
      await pumpEventQueue();
      // Only one transport call should be initiated
      expect(fakeTransport.callCounts[trackId], 1);

      gate.complete();
      await waitDone(serverScope, trackId);
      expect(manager.getTask(serverScope, trackId)!.status,
          DownloadTaskStatus.completed);
    });

    test(
        'failure then retry: maps errors to sanitized category and retryTask resumes only failed tasks',
        () async {
      const serverScope = 'https://server-fail.local';
      const trackId = 'fail-track';
      final track = createTestTrack(id: trackId);

      // Inject a network error
      fakeTransport.setError(
        trackId,
        const DownloadException('Server down',
            category: DownloadFailureCategory.network),
      );

      await manager.queueTrack(track, serverScope: serverScope);
      await waitForStatus(serverScope, trackId, DownloadTaskStatus.failed);

      final failedTask = manager.getTask(serverScope, trackId)!;
      expect(failedTask.status, DownloadTaskStatus.failed);
      expect(failedTask.failureCategory, DownloadFailureCategory.network);
      expect(failedTask.failureMessage, 'Server down');
      expect(failedTask.retryCount, 0);

      // Calling retry on non-failed task returns false
      expect(await manager.retryTask(serverScope, 'non-existent'), isFalse);

      // Retry the failed task
      final retried = await manager.retryTask(serverScope, trackId);
      expect(retried, isTrue);

      final retryTaskState = manager.getTask(serverScope, trackId)!;
      expect(retryTaskState.retryCount, 1);
      expect(retryTaskState.failureCategory, isNull);
      expect(retryTaskState.failureMessage, isNull);

      // Second attempt succeeds
      await waitForStatus(serverScope, trackId, DownloadTaskStatus.completed);
      final completedTask = manager.getTask(serverScope, trackId)!;
      expect(completedTask.status, DownloadTaskStatus.completed);
    });

    test(
        'pause/resume safe restart: pausing aborts in-flight transfer and resume restarts from zero',
        () async {
      const serverScope = 'https://server-pause.local';
      const trackId = 'pause-track';
      final gate = fakeTransport.gate(trackId);
      final track = createTestTrack(id: trackId);

      await manager.queueTrack(track, serverScope: serverScope);
      await started(trackId);

      // Pause while in-flight
      final paused = await manager.pauseTask(serverScope, trackId);
      expect(paused, isTrue);

      final pausedTask = manager.getTask(serverScope, trackId)!;
      expect(pausedTask.status, DownloadTaskStatus.paused);

      // Release gate and ensure no cache entry was registered
      gate.complete();
      await transportIdle();

      expect(await cacheService.lookup(serverScope, trackId), isNull);

      // Resume task: documents and tests safe restart from zero bytes
      final resumed = await manager.resumeTask(serverScope, trackId);
      expect(resumed, isTrue);

      final resumedTask = manager.getTask(serverScope, trackId)!;
      expect(resumedTask.downloadedBytes, 0); // Safe restart from zero
      expect(resumedTask.status,
          anyOf(DownloadTaskStatus.queued, DownloadTaskStatus.downloading));

      await waitDone(serverScope, trackId);
      expect(manager.getTask(serverScope, trackId)!.status,
          DownloadTaskStatus.completed);
      expect(await cacheService.lookup(serverScope, trackId), isNotNull);
    });

    test(
        'pausar y reanudar sin esperar: el intento viejo no borra el temporal ni el token del nuevo',
        () async {
      const serverScope = 'https://server-rapid.local';
      const trackId = 'rapid-track';
      final gate = fakeTransport.gate(trackId);
      await manager.queueTrack(createTestTrack(id: trackId),
          serverScope: serverScope);
      await started(trackId);

      expect(await manager.pauseTask(serverScope, trackId), isTrue);
      expect(await manager.resumeTask(serverScope, trackId), isTrue);
      gate.complete();

      await waitDone(serverScope, trackId);
      expect(manager.getTask(serverScope, trackId)!.status,
          DownloadTaskStatus.completed);
      expect(await cacheService.lookup(serverScope, trackId), isNotNull);
      await transportIdle();
    });

    test('cancel: removes partial file and leaves no C1 cache entry', () async {
      const serverScope = 'https://server-cancel.local';
      const trackId = 'cancel-track';
      final gate = fakeTransport.gate(trackId);
      final track = createTestTrack(id: trackId);

      await manager.queueTrack(track, serverScope: serverScope);
      await started(trackId);

      // Cancel while downloading
      final cancelled = await manager.cancelTask(serverScope, trackId);
      expect(cancelled, isTrue);

      final cancelledTask = manager.getTask(serverScope, trackId)!;
      expect(cancelledTask.status, DownloadTaskStatus.cancelled);

      gate.complete();
      await transportIdle();

      // No entry in C1 cache
      expect(await cacheService.lookup(serverScope, trackId), isNull);

      // Partial temp files are purged
      final tmpDir = Directory(p.join(tempDir.path, 'download_tmp'));
      if (tmpDir.existsSync()) {
        expect(tmpDir.listSync(), isEmpty);
      }

      // Cancelling an already cancelled task returns false
      expect(await manager.cancelTask(serverScope, trackId), isFalse);
    });

    test(
        'server-scope isolation: same track ID in different server scopes remains distinct',
        () async {
      const serverA = 'https://server-alpha.local';
      const serverB = 'https://server-beta.local';
      const trackId = 'shared-track-id';

      final trackA = createTestTrack(id: trackId, title: 'Server A Title');
      final trackB = createTestTrack(id: trackId, title: 'Server B Title');

      final taskA = await manager.queueTrack(trackA, serverScope: serverA);
      final taskB = await manager.queueTrack(trackB, serverScope: serverB);

      expect(taskA.serverScope, isNot(equals(taskB.serverScope)));
      expect(taskA.compoundKey, isNot(equals(taskB.compoundKey)));

      await waitDone(serverA, trackId);
      await waitDone(serverB, trackId);

      final lookupA = await cacheService.lookup(serverA, trackId);
      final lookupB = await cacheService.lookup(serverB, trackId);

      expect(lookupA, isNotNull);
      expect(lookupB, isNotNull);
      expect(lookupA!.title, 'Server A Title');
      expect(lookupB!.title, 'Server B Title');
      expect(lookupA.localPath, isNot(equals(lookupB.localPath)));
    });

    test(
        'persistence: downloading tasks restore as paused and require explicit resume',
        () async {
      const serverScope = 'https://server-persist.local';
      final persistenceFile = File(p.join(tempDir.path, 'custom_tasks.json'));

      // Create initial persistence state with a task marked as downloading
      final taskMap = {
        'version': 1,
        'tasks': [
          {
            'server_scope': OfflineCacheService.safeScopeSegment(serverScope),
            'track_id': 'interrupted-track',
            'status': 'downloading',
            'title': 'Interrupted',
            'artist': 'Artist',
            'album': 'Album',
            'duration_seconds': 150,
            'downloaded_bytes': 100,
            'total_bytes': 500,
            'retry_count': 0,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
          {
            'server_scope': OfflineCacheService.safeScopeSegment(serverScope),
            'track_id': 'already-paused-track',
            'status': 'paused',
            'title': 'Paused',
            'artist': 'Artist',
            'album': 'Album',
            'duration_seconds': 200,
            'downloaded_bytes': 0,
            'retry_count': 0,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          }
        ]
      };
      await persistenceFile.writeAsString(jsonEncode(taskMap));

      final secondManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: fakeTransport,
        persistenceFile: persistenceFile,
      );

      await secondManager.initialize();

      // Previously downloading task must be restored as PAUSED, never automatically active
      final interrupted =
          secondManager.getTask(serverScope, 'interrupted-track')!;
      expect(interrupted.status, DownloadTaskStatus.paused);
      expect(secondManager.activeCount, 0);

      // Requires explicit resume to start downloading
      final resumed =
          await secondManager.resumeTask(serverScope, 'interrupted-track');
      expect(resumed, isTrue);

      await waitUntil(
          () =>
              secondManager.getTask(serverScope, 'interrupted-track')?.status ==
              DownloadTaskStatus.completed,
          'la tarea reanudada se completa');
      expect(secondManager.getTask(serverScope, 'interrupted-track')!.status,
          DownloadTaskStatus.completed);

      secondManager.dispose();
    });

    test(
        'persistence: corrupt persistence fails closed without deleting verified C1 files',
        () async {
      const serverScope = 'https://server-corrupt.local';
      final persistenceFile = File(p.join(tempDir.path, 'corrupt_tasks.json'));

      // Register an existing valid C1 cached file
      final dummyFile = File(p.join(tempDir.path, 'valid.audio'));
      await dummyFile.writeAsBytes(List.filled(128, 5));
      await cacheService.registerFile(
        serverScope: serverScope,
        trackId: 'preserved-c1-track',
        localPath: dummyFile.path,
        title: 'Preserved Track',
        artist: 'Preserved Artist',
        album: 'Preserved Album',
      );

      expect(await cacheService.lookup(serverScope, 'preserved-c1-track'),
          isNotNull);

      // Corrupt persistence file with malformed JSON
      await persistenceFile.writeAsString('{"tasks": [broken_unclosed_json...');

      final thirdManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: fakeTransport,
        persistenceFile: persistenceFile,
      );

      // Must initialize without crashing and start with empty queue (fail-closed)
      await thirdManager.initialize();
      expect(thirdManager.tasks, isEmpty);

      // Verified C1 cache file must be completely untouched
      final lookupAfterCorrupt =
          await cacheService.lookup(serverScope, 'preserved-c1-track');
      expect(lookupAfterCorrupt, isNotNull);
      expect(lookupAfterCorrupt!.title, 'Preserved Track');

      thirdManager.dispose();
    });

    test(
        'sanitization: persisted JSON, task state, and errors never leak URLs or credentials',
        () async {
      const serverScope =
          'https://admin:supersecret@navidrome.example.com:4533';
      const trackId = 'sanitized-track';
      final track = createTestTrack(id: trackId);

      const sensitiveExceptionString =
          'Error connecting to https://admin:supersecret@navidrome.example.com/rest/stream.view?u=admin&t=token123&s=salt456&v=1.16.1';

      // Throw exception with sensitive URL
      fakeTransport.setError(
        trackId,
        Exception(sensitiveExceptionString),
      );

      await manager.queueTrack(
        track,
        serverScope: serverScope,
        sourceMarker: 'lossless',
      );
      await waitDone(serverScope, trackId);

      final failedTask = manager.getTask(serverScope, trackId)!;
      expect(failedTask.status, DownloadTaskStatus.failed);

      // Check task failureMessage does not contain credentials or stream URLs
      final msg = failedTask.failureMessage ?? '';
      for (final forbidden in [
        'admin',
        'supersecret',
        'token123',
        'salt456',
        'stream.view',
        'navidrome.example.com',
        '://',
        '?u=',
        '&t=',
        '&s=',
      ]) {
        expect(msg.contains(forbidden), isFalse);
        expect(failedTask.serverScope.contains(forbidden), isFalse);
      }

      // Read persisted JSON directly from disk
      final persistFile = File(p.join(tempDir.path, 'downloads', 'tasks.json'));
      expect(persistFile.existsSync(), isTrue);
      final jsonContent = persistFile.readAsStringSync();

      for (final forbidden in [
        'admin',
        'supersecret',
        'token123',
        'salt456',
        'stream.view',
        'navidrome.example.com',
        '://',
        '?u=',
        '&t=',
        '&s=',
      ]) {
        expect(jsonContent.contains(forbidden), isFalse);
      }

      // DownloadTask validation rejects sensitive strings
      expect(
        () => DownloadTask(
          serverScope: 'server',
          trackId: 'trk',
          title: 'T',
          artist: 'A',
          album: 'Al',
          failureMessage: sensitiveExceptionString,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('downloadTrackStream rechaza un 200 que trae JSON/XML de error',
        () async {
      for (final body in [
        '{"subsonic-response":{"status":"failed"}}',
        '<?xml version="1.0"?><subsonic-response status="failed"/>',
      ]) {
        final client = _MockStreamingHttpClient((request) async {
          return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
        });
        final nav = NavidromeService()
          ..setConnectedForTesting(
              url: 'https://test-navidrome.local:4533',
              username: 'alice',
              password: 'password123',
              client: client);
        final dest = File(p.join(tempDir.path, 'error_body.audio'));
        await expectLater(
          nav.downloadTrackStream(trackId: 't', destinationFile: dest),
          throwsA(isA<DownloadException>().having((e) => e.category, 'category',
              DownloadFailureCategory.serverError)),
        );
      }
    });

    test(
        'NavidromeService.downloadTrackStream: isolated unit tests with mock client',
        () async {
      // 1. Not connected throws DownloadException(notConnected)
      final disconnectedNav = NavidromeService();
      final destFile = File(p.join(tempDir.path, 'nav_test.audio'));

      expect(
        () => disconnectedNav.downloadTrackStream(
          trackId: 'track-disc',
          destinationFile: destFile,
        ),
        throwsA(isA<DownloadException>().having(
          (e) => e.category,
          'category',
          DownloadFailureCategory.notConnected,
        )),
      );

      // 2. Connected with mock streaming client: success case
      final testData = List<int>.generate(512, (i) => i % 256);
      final mockClient = _MockStreamingHttpClient((request) async {
        // Verify request is authenticated internally
        expect(request.url.path, contains('stream.view'));
        expect(request.url.queryParameters, contains('u'));
        expect(request.url.queryParameters, contains('t'));
        expect(request.url.queryParameters, contains('s'));

        final byteStream = http.ByteStream(Stream.fromIterable([
          testData.sublist(0, 256),
          testData.sublist(256, 512),
        ]));

        return http.StreamedResponse(
          byteStream,
          200,
          contentLength: 512,
        );
      });

      final connectedNav = NavidromeService(httpClient: mockClient);
      connectedNav.setConnectedForTesting(
        url: 'https://test-navidrome.local:4533',
        username: 'alice',
        password: 'password123',
        client: mockClient,
      );

      expect(
          connectedNav.serverScope,
          equals(OfflineCacheService.safeScopeSegment(
              'https://test-navidrome.local:4533')));

      final progressCalls = <int>[];
      await connectedNav.downloadTrackStream(
        trackId: 'track-streaming-ok',
        destinationFile: destFile,
        quality: AudioQuality.lossless,
        onProgress: (received, total) {
          progressCalls.add(received);
        },
      );

      expect(destFile.existsSync(), isTrue);
      expect(destFile.lengthSync(), 512);
      expect(progressCalls, containsAllInOrder([256, 512]));

      // 3. HTTP 401 maps to DownloadFailureCategory.auth
      final authErrorClient = _MockStreamingHttpClient((request) async {
        return http.StreamedResponse(
          http.ByteStream(Stream.value([])),
          401,
        );
      });

      connectedNav.setConnectedForTesting(
        url: 'https://test-navidrome.local:4533',
        username: 'alice',
        password: 'password123',
        client: authErrorClient,
      );

      expect(
        () => connectedNav.downloadTrackStream(
          trackId: 'track-401',
          destinationFile: destFile,
        ),
        throwsA(isA<DownloadException>().having(
          (e) => e.category,
          'category',
          DownloadFailureCategory.auth,
        )),
      );

      // 4. HTTP 404 maps to DownloadFailureCategory.notFound
      final notFoundClient = _MockStreamingHttpClient((request) async {
        return http.StreamedResponse(
          http.ByteStream(Stream.value([])),
          404,
        );
      });

      connectedNav.setConnectedForTesting(
        url: 'https://test-navidrome.local:4533',
        username: 'alice',
        password: 'password123',
        client: notFoundClient,
      );

      expect(
        () => connectedNav.downloadTrackStream(
          trackId: 'track-404',
          destinationFile: destFile,
        ),
        throwsA(isA<DownloadException>().having(
          (e) => e.category,
          'category',
          DownloadFailureCategory.notFound,
        )),
      );

      // 5. Timeout maps to DownloadFailureCategory.timeout
      final timeoutClient = _MockStreamingHttpClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.StreamedResponse(http.ByteStream(Stream.value([])), 200);
      });

      connectedNav.setConnectedForTesting(
        url: 'https://test-navidrome.local:4533',
        username: 'alice',
        password: 'password123',
        client: timeoutClient,
      );

      expect(
        () => connectedNav.downloadTrackStream(
          trackId: 'track-timeout',
          destinationFile: destFile,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<DownloadException>().having(
          (e) => e.category,
          'category',
          DownloadFailureCategory.timeout,
        )),
      );
    });

    test(
        'security: traversal-style track ID stays strictly under cache root for temp, final, and cancel paths',
        () async {
      const serverScope = 'https://server-traversal.local';
      const traversalTrackId = '../../../../etc/malicious_track';
      final track = createTestTrack(
        id: traversalTrackId,
        title: 'Traversal Song',
        artist: 'Traversal Artist',
      );

      final testBytes = List<int>.generate(128, (i) => i % 128);
      fakeTransport.setPayload(traversalTrackId, testBytes);

      // Verify manager-created temp path stays strictly under cache root
      final tempFile = await manager.getTempFile(serverScope, traversalTrackId);
      expect(p.isWithin(tempDir.path, tempFile.path), isTrue);
      expect(tempFile.path, contains('download_tmp'));
      expect(tempFile.path.contains('..'), isFalse);
      expect(tempFile.path.contains('malicious'), isFalse);
      expect(tempFile.path.contains('etc'), isFalse);

      final task = await manager.queueTrack(track, serverScope: serverScope);
      expect(task.trackId, traversalTrackId);

      // Wait for download completion
      await waitDone(serverScope, traversalTrackId);

      final completedTask = manager.getTask(serverScope, traversalTrackId)!;
      expect(completedTask.status, DownloadTaskStatus.completed);

      // Verify manager-created final path in C1 cache stays strictly under cache root
      final entry = await cacheService.lookup(serverScope, traversalTrackId);
      expect(entry, isNotNull);
      expect(p.isWithin(tempDir.path, entry!.localPath), isTrue);
      expect(entry.localPath.contains('..'), isFalse);
      expect(entry.localPath.contains('malicious'), isFalse);
      expect(entry.localPath.contains('etc'), isFalse);
      expect(File(entry.localPath).existsSync(), isTrue);

      // Verify cancellation cleanup with traversal-style track ID stays strictly under cache root
      const cancelTraversalId = '../../../../var/log/cancel_malicious';
      final cancelTrack = createTestTrack(id: cancelTraversalId);
      final gate = fakeTransport.gate(cancelTraversalId);

      await manager.queueTrack(cancelTrack, serverScope: serverScope);
      await started(cancelTraversalId);

      final cancelTemp =
          await manager.getTempFile(serverScope, cancelTraversalId);
      expect(p.isWithin(tempDir.path, cancelTemp.path), isTrue);

      final cancelled =
          await manager.cancelTask(serverScope, cancelTraversalId);
      expect(cancelled, isTrue);
      gate.complete();
      await transportIdle();

      expect(cancelTemp.existsSync(), isFalse);
      expect(await cacheService.lookup(serverScope, cancelTraversalId), isNull);

      // Ensure every single file/dir within tempDir is strictly within root
      for (final entity in tempDir.listSync(recursive: true)) {
        expect(p.isWithin(tempDir.path, entity.path), isTrue);
        expect(p.canonicalize(entity.path).contains('..'), isFalse);
        expect(entity.path.contains('malicious'), isFalse);
        expect(entity.path.contains('var/log'), isFalse);
      }
    });

    test(
        'Un fallo de registro restaura un archivo que apareció durante la transferencia',
        () async {
      const serverScope = 'https://server-atomic-rollback.local';
      const trackId = 'rollback-track-1';
      final initialAudioPath =
          await cacheService.getAudioFilePath(serverScope, trackId);
      final initialFile = File(initialAudioPath);
      final initialBytes = List<int>.filled(200, 42);
      final replacementBytes = List<int>.filled(500, 99);
      fakeTransport.setPayload(trackId, replacementBytes);
      fakeTransport.gate(trackId);
      manager.c1RegisterSeam = ({
        required String serverScope,
        required String trackId,
        required String localPath,
        required String title,
        required String artist,
        required String album,
        int? durationSeconds,
        String? sourceMarker,
      }) async {
        throw const FileSystemException('Fallo de registro simulado');
      };
      final replacementTrack =
          createTestTrack(id: trackId, title: 'Nueva canción');
      final task =
          await manager.queueTrack(replacementTrack, serverScope: serverScope);
      expect(task.status,
          anyOf(DownloadTaskStatus.queued, DownloadTaskStatus.downloading));
      // La consulta inicial no encuentra audio; aparece mientras la red está detenida.
      while (fakeTransport.callCounts[trackId] == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await initialFile.parent.create(recursive: true);
      await initialFile.writeAsBytes(initialBytes, flush: true);
      await cacheService.registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: initialAudioPath,
        title: 'Canción original',
        artist: 'Artista original',
        album: 'Álbum original',
        durationSeconds: 180,
        sourceMarker: 'lossless',
      );
      final finished = Completer<void>();
      void listener() {
        if (manager.getTask(serverScope, trackId)?.status ==
                DownloadTaskStatus.failed &&
            !finished.isCompleted) {
          finished.complete();
        }
      }

      manager.addListener(listener);
      fakeTransport.releaseGate(trackId);
      await finished.future.timeout(const Duration(seconds: 5));
      manager.removeListener(listener);
      final failedTask = manager.getTask(serverScope, trackId)!;
      expect(failedTask.failureCategory, DownloadFailureCategory.storage);
      expect(await initialFile.readAsBytes(), initialBytes);
      final lookup = await cacheService.lookup(serverScope, trackId);
      expect(lookup?.byteSize, 200);
      expect(lookup?.title, 'Canción original');
      expect(lookup?.artist, 'Artista original');
      expect(await File('$initialAudioPath.bak').exists(), isFalse);
      expect(await (await manager.getTempFile(serverScope, trackId)).exists(),
          isFalse);
    });

    test(
        'persistence: deterministic seam proves serialized writes and that last state wins',
        () async {
      const serverScope = 'https://server-seam-persist.local';
      final persistenceFile =
          File(p.join(tempDir.path, 'seam_persist_tasks.json'));

      final firstWriteGate = Completer<void>();
      int persistHookCount = 0;

      final seamManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: fakeTransport,
        persistenceFile: persistenceFile,
        onBeforePersistWrite: () async {
          persistHookCount++;
          if (persistHookCount == 1) {
            // Pause the 1st write in-flight
            await firstWriteGate.future;
          }
        },
      );
      await seamManager.initialize();

      const track1Id = 'seam-track-1';
      const track2Id = 'seam-track-2';
      final track1 = createTestTrack(id: track1Id);
      final track2 = createTestTrack(id: track2Id);

      // 1. Queue track 1 -> triggers first _persistTasks() which pauses at firstWriteGate
      unawaited(seamManager.queueTrack(track1, serverScope: serverScope));
      while (persistHookCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(persistHookCount, 1);

      // 2. While the 1st write is paused, trigger multiple rapid unawaited state updates:
      // - Queue track 2
      unawaited(seamManager.queueTrack(track2, serverScope: serverScope));
      // - Pause track 1
      unawaited(seamManager.pauseTask(serverScope, track1Id));
      // - Cancel track 1 (terminal transition: must NOT be stored in tasks.json!)
      unawaited(seamManager.cancelTask(serverScope, track1Id));

      // 3. Release the 1st write
      firstWriteGate.complete();

      // 4. Await flush of all persistence writes
      await seamManager.flushPersistence();

      // 5. Read persisted file directly from disk and verify last state won
      expect(persistenceFile.existsSync(), isTrue);
      final content = await persistenceFile.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      final List<dynamic> storedTasks = data['tasks'];

      // Terminal cancelled track1 MUST NOT exist in stored tasks!
      final storedTrack1 = storedTasks.where(
        (t) => t['track_id'] == track1Id,
      );
      expect(storedTrack1, isEmpty,
          reason:
              'Cancelled task must not be persisted by an earlier stale snapshot');

      // Queued track2 MUST exist in stored tasks!
      final storedTrack2 = storedTasks.firstWhere(
        (t) => t['track_id'] == track2Id,
        orElse: () => null,
      );
      expect(storedTrack2, isNotNull,
          reason: 'Latest state of task2 must be saved');
      expect(storedTrack2['status'], anyOf('queued', 'downloading'));

      seamManager.dispose();
    });

    test(
        'persistence: asynchronous stress test with rapid concurrent state transitions preserves final state',
        () async {
      const serverScope = 'https://server-stress-persist.local';
      final persistenceFile =
          File(p.join(tempDir.path, 'stress_persist_tasks.json'));

      final stressManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: fakeTransport,
        persistenceFile: persistenceFile,
        maxConcurrency: 1, // force queuing
      );
      await stressManager.initialize();

      // Gate all downloads so nothing completes until we want
      for (int i = 0; i < 8; i++) {
        fakeTransport.gate('stress-track-$i');
      }

      // Rapidly fire queue operations concurrently
      final futures = <Future<void>>[];
      for (int i = 0; i < 8; i++) {
        final t = createTestTrack(id: 'stress-track-$i');
        futures.add(stressManager.queueTrack(t, serverScope: serverScope));
      }
      await Future.wait(futures);

      // Now rapidly pause, resume, cancel across multiple tasks asynchronously
      unawaited(stressManager.pauseTask(serverScope, 'stress-track-1'));
      unawaited(stressManager.pauseTask(serverScope, 'stress-track-2'));
      unawaited(stressManager.cancelTask(serverScope, 'stress-track-3'));
      unawaited(stressManager.resumeTask(serverScope, 'stress-track-1'));
      unawaited(stressManager.cancelTask(serverScope, 'stress-track-4'));

      // Flush all persistence writes
      await stressManager.flushPersistence();

      // Read persisted file directly and verify integrity and state matching
      expect(persistenceFile.existsSync(), isTrue);
      final content = await persistenceFile.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      expect(data['version'], 1);
      final List<dynamic> storedTasks = data['tasks'];

      // Cancelled tasks 3 and 4 must NOT be in stored tasks
      final ids = storedTasks.map((t) => t['track_id']).toSet();
      expect(ids.contains('stress-track-3'), isFalse);
      expect(ids.contains('stress-track-4'), isFalse);

      // Resumed track 1 must be queued or downloading
      final task1 =
          storedTasks.firstWhere((t) => t['track_id'] == 'stress-track-1');
      expect(task1['status'], anyOf('queued', 'downloading'));

      // Paused track 2 must be paused
      final task2 =
          storedTasks.firstWhere((t) => t['track_id'] == 'stress-track-2');
      expect(task2['status'], 'paused');

      // Release gates to clean up
      for (int i = 0; i < 8; i++) {
        fakeTransport.releaseGate('stress-track-$i');
      }
      stressManager.dispose();
    });
  });
}
