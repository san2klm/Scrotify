import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/offline_cache_service.dart';
import 'package:crotowave/services/offline_download_manager.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/track_context_menu.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'support/app_fakes.dart';

class _TestNavidromeService extends FakeNavidrome {
  final String? _scope;
  _TestNavidromeService([this._scope = 'srv_testscope1234567890123456789012']);

  @override
  String? get serverScope => _scope;
}

class _TestCrotoLinkController extends IdleCrotoLink {
  final bool _crotoLinkActive;
  _TestCrotoLinkController({bool crotoLinkActive = false})
      : _crotoLinkActive = crotoLinkActive;

  @override
  bool get inCrotoLink => _crotoLinkActive;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testTrack = Track(
    id: 'track_test_101',
    title: 'Canción de Prueba',
    artist: 'Artista Ficticio',
    album: 'Álbum Demo',
    duration: '210',
  );

  const testScope = 'srv_testscope1234567890123456789012';

  group('TrackOfflineActionState.resolve pure action-state mapping', () {
    test('returns notDownloaded when task is null and cache is unverified', () {
      final state = TrackOfflineActionState.resolve(
        task: null,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.notDownloaded);
      expect(state.progress, isNull);
      expect(state.failureMessage, isNull);
    });

    test('returns notDownloaded when task is cancelled and cache is unverified',
        () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.cancelled,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.notDownloaded);
    });

    test(
        'SECURITY: completed task alone without verified cache hit is NOT availableOffline and returns notDownloaded',
        () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.completed,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.notDownloaded);
    });

    test('returns queued when task status is queued', () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.queued,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.queued);
      expect(state.task, equals(task));
    });

    test(
        'returns downloading with progress percentage when task is downloading and totalBytes is known',
        () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.downloading,
        downloadedBytes: 500,
        totalBytes: 1000,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.downloading);
      expect(state.progress, equals(0.5));
    });

    test(
        'returns downloading with null progress when task is downloading and totalBytes is null',
        () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.downloading,
        downloadedBytes: 500,
        totalBytes: null,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.downloading);
      expect(state.progress, isNull);
    });

    test('returns paused when task status is paused', () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.paused,
        downloadedBytes: 300,
        totalBytes: 1000,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.paused);
      expect(state.progress, equals(0.3));
    });

    test(
        'returns failed with sanitized failureMessage when task status is failed',
        () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.failed,
        failureMessage: 'Fallo de conexión de red',
        failureCategory: DownloadFailureCategory.network,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: false,
      );
      expect(state.status, TrackOfflineUiState.failed);
      expect(state.failureMessage, equals('Fallo de conexión de red'));
    });

    test(
        'returns availableOffline when hasVerifiedCache is true with null task',
        () {
      final state = TrackOfflineActionState.resolve(
        task: null,
        hasVerifiedCache: true,
      );
      expect(state.status, TrackOfflineUiState.availableOffline);
    });

    test(
        'returns availableOffline when hasVerifiedCache is true with completed task',
        () {
      final task = DownloadTask(
        serverScope: testScope,
        trackId: testTrack.id,
        title: testTrack.title,
        artist: testTrack.artist,
        album: testTrack.album,
        status: DownloadTaskStatus.completed,
      );
      final state = TrackOfflineActionState.resolve(
        task: task,
        hasVerifiedCache: true,
      );
      expect(state.status, TrackOfflineUiState.availableOffline);
    });
  });

  group('TrackOfflineSection widget & dispatch tests', () {
    late Directory tempDir;
    late OfflineCacheService cacheService;
    late OfflineDownloadManager downloadManager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('track_menu_test_');
      cacheService = OfflineCacheService(
        cacheRootDir: tempDir,
        metadataStore: InMemoryOfflineCacheMetadataStore(),
      );
      await cacheService.initialize();

      downloadManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: FunctionalDownloadTransport(
          ({
            required serverScope,
            required trackId,
            required destinationFile,
            sourceMarker,
            onProgress,
            isCancelled,
          }) async {
            if (!await destinationFile.parent.exists()) {
              await destinationFile.parent.create(recursive: true);
            }
            await destinationFile.writeAsBytes(List.filled(256, 1));
          },
        ),
        persistenceDir: tempDir,
      );
      await downloadManager.initialize();
    });

    tearDown(() async {
      downloadManager.dispose();
      await cacheService.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Widget createTestHarness({
      required Widget child,
      NavidromeService? navidromeService,
      CrotoLinkController? crotoLinkController,
      PlayerController? playerController,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController(),
          ),
          ChangeNotifierProvider<NavidromeService>(
            create: (_) => navidromeService ?? _TestNavidromeService(testScope),
          ),
          ChangeNotifierProvider<PlayerController>(
            create: (_) => playerController ?? IdlePlayer(),
          ),
          ChangeNotifierProvider<CrotoLinkController>(
            create: (_) =>
                crotoLinkController ??
                _TestCrotoLinkController(crotoLinkActive: false),
          ),
          Provider<OfflineCacheService>.value(value: cacheService),
          ChangeNotifierProvider<OfflineDownloadManager>.value(
            value: downloadManager,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets(
        'not downloaded state: renders Descargar sin conexión, tap dispatches queueTrack and shows SnackBar',
        (tester) async {
      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: testScope,
            downloadManager: downloadManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Descargar sin conexión'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Descargar sin conexión'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify task was queued in manager
      final task = downloadManager.getTask(testScope, testTrack.id);
      expect(task, isNotNull);

      // Verify SnackBar appears with safe track title
      expect(
        find.text('Descarga añadida para "${testTrack.title}"'),
        findsOneWidget,
      );
    });

    testWidgets(
        'disconnected state: tapping Descargar sin conexión without scope surfaces concise error SnackBar',
        (tester) async {
      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: null,
            downloadManager: downloadManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Descargar sin conexión'), findsOneWidget);

      await tester.tap(find.text('Descargar sin conexión'));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(
        find.text('No hay un servidor conectado para descargar.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'queued/downloading state: renders Pausar descarga; tapping Pausar dispatches pauseTask',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final blockingManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: FunctionalDownloadTransport(
          ({
            required serverScope,
            required trackId,
            required destinationFile,
            sourceMarker,
            onProgress,
            isCancelled,
          }) async {
            while (!gate.isCompleted && !(isCancelled?.call() ?? false)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            if (isCancelled != null && isCancelled()) {
              throw const DownloadException(
                'Download cancelled',
                category: DownloadFailureCategory.cancelled,
              );
            }
          },
        ),
        persistenceDir: tempDir,
      );
      await tester.runAsync(() async {
        await blockingManager.initialize();
        await blockingManager.queueTrack(testTrack, serverScope: testScope);
      });

      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: testScope,
            downloadManager: blockingManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Either queued or downloading shows Pausar descarga
      expect(find.text('Pausar descarga'), findsOneWidget);

      // Tap Pausar descarga
      await tester.tap(find.text('Pausar descarga'));
      if (!gate.isCompleted) gate.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final pausedTask = blockingManager.getTask(testScope, testTrack.id);
      expect(pausedTask?.status, equals(DownloadTaskStatus.paused));

      blockingManager.dispose();
    });

    testWidgets(
        'paused state: renders Reanudar descarga and Cancelar descarga; controls dispatch resume and cancel',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final blockingManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: FunctionalDownloadTransport(
          ({
            required serverScope,
            required trackId,
            required destinationFile,
            sourceMarker,
            onProgress,
            isCancelled,
          }) async {
            while (!gate.isCompleted && !(isCancelled?.call() ?? false)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            if (isCancelled != null && isCancelled()) {
              throw const DownloadException(
                'Download cancelled',
                category: DownloadFailureCategory.cancelled,
              );
            }
          },
        ),
        persistenceDir: tempDir,
      );
      await tester.runAsync(() async {
        await blockingManager.initialize();
        await blockingManager.queueTrack(testTrack, serverScope: testScope);
        await blockingManager.pauseTask(testScope, testTrack.id);
      });

      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: testScope,
            downloadManager: blockingManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Reanudar descarga'), findsOneWidget);
      expect(find.text('Cancelar descarga'), findsOneWidget);

      // Tap Reanudar descarga -> transitions to queued/downloading
      await tester.tap(find.text('Reanudar descarga'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final taskAfterResume = blockingManager.getTask(testScope, testTrack.id);
      expect(
        taskAfterResume?.status == DownloadTaskStatus.queued ||
            taskAfterResume?.status == DownloadTaskStatus.downloading,
        isTrue,
      );

      // Pause again to test cancel
      await blockingManager.pauseTask(testScope, testTrack.id);
      await tester.pump();

      // Tap Cancelar descarga -> resets task
      await tester.runAsync(() async {
        await tester.tap(find.text('Cancelar descarga'));
        if (!gate.isCompleted) gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final cancelledTask = blockingManager.getTask(testScope, testTrack.id);
      expect(cancelledTask?.status, equals(DownloadTaskStatus.cancelled));

      // After cancelling, UI offers Descargar sin conexión again
      expect(find.text('Descargar sin conexión'), findsOneWidget);

      blockingManager.dispose();
    });

    testWidgets(
        'failed state: renders Reintentar descarga with sanitized failure message and Cancelar descarga',
        (tester) async {
      final failingManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: FunctionalDownloadTransport(
          ({
            required serverScope,
            required trackId,
            required destinationFile,
            sourceMarker,
            onProgress,
            isCancelled,
          }) async {
            throw const SocketException('Connection refused');
          },
        ),
        persistenceDir: tempDir,
      );
      await tester.runAsync(() async {
        await failingManager.initialize();
        await failingManager.queueTrack(testTrack, serverScope: testScope);
        // Wait for async execution to catch error
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      final failedTask = failingManager.getTask(testScope, testTrack.id);
      expect(failedTask?.status, equals(DownloadTaskStatus.failed));

      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: testScope,
            downloadManager: failingManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Reintentar descarga'), findsOneWidget);
      expect(find.text('Cancelar descarga'), findsOneWidget);
      // Sanitized message from manager
      expect(find.text('Network connection failed'), findsOneWidget);

      // Tap Reintentar descarga -> re-queues
      await tester.runAsync(() async {
        await tester.tap(find.text('Reintentar descarga'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final retriedTask = failingManager.getTask(testScope, testTrack.id);
      expect(retriedTask?.retryCount, equals(1));

      failingManager.dispose();
    });

    testWidgets(
        'verified cache entry: renders disabled Disponible sin conexión and does not offer transfer',
        (tester) async {
      await tester.runAsync(() async {
        final audioPath = p.join(tempDir.path, 'test_audio.audio');
        final audioFile = File(audioPath);
        await audioFile.writeAsBytes(List.filled(512, 7));

        await cacheService.registerFile(
          serverScope: testScope,
          trackId: testTrack.id,
          localPath: audioPath,
          title: testTrack.title,
          artist: testTrack.artist,
          album: testTrack.album,
        );

        final verified = await cacheService.lookup(testScope, testTrack.id);
        expect(verified, isNotNull);
      });

      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: testScope,
            downloadManager: downloadManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Disponible sin conexión'), findsOneWidget);
      expect(find.text('Guardada en este dispositivo'), findsOneWidget);
      // Does not offer download
      expect(find.text('Descargar sin conexión'), findsNothing);
    });

    testWidgets(
        'sanitization: persisted task, text, and SnackBars never leak URLs, credentials, or tokens',
        (tester) async {
      await tester.pumpWidget(
        createTestHarness(
          child: TrackOfflineSection(
            track: testTrack,
            serverScope: testScope,
            downloadManager: downloadManager,
            cacheService: cacheService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Descargar sin conexión'));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Check all rendered Text widgets for sensitive substrings
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final text in textWidgets) {
        final content = text.data ?? text.textSpan?.toPlainText() ?? '';
        expect(content.contains('http://'), isFalse);
        expect(content.contains('https://'), isFalse);
        expect(content.contains('&t='), isFalse);
        expect(content.contains('&s='), isFalse);
        expect(content.contains('&p='), isFalse);
        expect(content.contains('&u='), isFalse);
        expect(content.contains('password'), isFalse);
        expect(content.contains('token='), isFalse);
      }
    });
  });

  group('TrackContextMenu integration tests', () {
    late Directory tempDir;
    late OfflineCacheService cacheService;
    late OfflineDownloadManager downloadManager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('menu_int_test_');
      cacheService = OfflineCacheService(
        cacheRootDir: tempDir,
        metadataStore: InMemoryOfflineCacheMetadataStore(),
      );
      await cacheService.initialize();

      downloadManager = OfflineDownloadManager(
        cacheService: cacheService,
        transport: FunctionalDownloadTransport(
          ({
            required serverScope,
            required trackId,
            required destinationFile,
            sourceMarker,
            onProgress,
            isCancelled,
          }) async {
            if (!await destinationFile.parent.exists()) {
              await destinationFile.parent.create(recursive: true);
            }
            await destinationFile.writeAsBytes(List.filled(256, 1));
          },
        ),
        persistenceDir: tempDir,
      );
      await downloadManager.initialize();
    });

    tearDown(() async {
      downloadManager.dispose();
      await cacheService.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Widget createContextMenuHarness({
      required bool inCrotoLink,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController(),
          ),
          ChangeNotifierProvider<NavidromeService>(
            create: (_) => _TestNavidromeService(testScope),
          ),
          ChangeNotifierProvider<PlayerController>(
            create: (_) => IdlePlayer(),
          ),
          ChangeNotifierProvider<CrotoLinkController>(
            create: (_) =>
                _TestCrotoLinkController(crotoLinkActive: inCrotoLink),
          ),
          Provider<OfflineCacheService>.value(value: cacheService),
          ChangeNotifierProvider<OfflineDownloadManager>.value(
            value: downloadManager,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TrackContextMenu(track: testTrack),
          ),
        ),
      );
    }

    testWidgets(
        'renders offline action when not in CrotoLink mode (!crotoLink.inCrotoLink) and preserves existing menu actions',
        (tester) async {
      await tester.pumpWidget(createContextMenuHarness(inCrotoLink: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Offline download action is visible
      expect(find.text('Descargar sin conexión'), findsOneWidget);

      // Existing playback actions remain unchanged
      expect(find.text('Reproducir ahora'), findsOneWidget);
      expect(find.text('Añadir a la cola'), findsOneWidget);
      expect(find.text('Reproducir siguiente'), findsOneWidget);
      expect(find.text('Añadir a la fila'), findsOneWidget);
      expect(find.text('Apagado automático'), findsOneWidget);
      expect(find.text('Modo Karaoke'), findsOneWidget);
    });

    testWidgets(
        'does NOT render offline action when in CrotoLink mode (crotoLink.inCrotoLink)',
        (tester) async {
      await tester.pumpWidget(createContextMenuHarness(inCrotoLink: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Offline download action is NOT shown in CrotoLink mode
      expect(find.text('Descargar sin conexión'), findsNothing);
      expect(find.text('Disponible sin conexión'), findsNothing);
    });
  });
}
