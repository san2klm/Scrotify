import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/offline_cache_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class _MockDatabaseExecutor implements DatabaseExecutor {
  final List<String> executedSql = [];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executedSql.add(sql);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('OfflineCacheService foundation', () {
    late Directory tempDir;
    late InMemoryOfflineCacheMetadataStore metadataStore;
    late OfflineCacheService service;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('offline_cache_test_');
      metadataStore = InMemoryOfflineCacheMetadataStore();
      service = OfflineCacheService(
        cacheRootDir: tempDir,
        metadataStore: metadataStore,
      );
      await service.initialize();
    });

    tearDown(() async {
      await service.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('scope separation: server scopes do not collide for equal track IDs',
        () async {
      const serverA = 'https://admin:secret@server-alpha.local:4533';
      const serverB = 'https://user:token@server-beta.remote.org:8080';
      const trackId = 'track-001';

      final pathA = await service.cachePath(serverA, trackId);
      final pathB = await service.cachePath(serverB, trackId);

      expect(pathA, isNot(equals(pathB)));
      // Ensure paths are deterministic descendants of service root
      expect(pathA.startsWith(tempDir.path), isTrue);
      expect(pathB.startsWith(tempDir.path), isTrue);

      // Verify safe opaque segments do not expose credentials or URLs
      expect(pathA.contains('admin'), isFalse);
      expect(pathA.contains('secret'), isFalse);
      expect(pathA.contains('server-alpha'), isFalse);
      expect(pathA.contains(OfflineCacheService.safeScopeSegment(serverA)),
          isTrue);

      expect(pathB.contains('user'), isFalse);
      expect(pathB.contains('token'), isFalse);
      expect(pathB.contains('server-beta'), isFalse);
      expect(pathB.contains(OfflineCacheService.safeScopeSegment(serverB)),
          isTrue);

      final fileA = await service.getAudioFile(serverA, trackId);
      final fileB = await service.getAudioFile(serverB, trackId);

      await fileA.writeAsBytes(List.filled(100, 1));
      await fileB.writeAsBytes(List.filled(200, 2));

      await service.registerFile(
        serverScope: serverA,
        trackId: trackId,
        localPath: fileA.path,
        title: 'Title Server A',
        artist: 'Artist A',
        album: 'Album A',
        durationSeconds: 120,
      );

      await service.registerFile(
        serverScope: serverB,
        trackId: trackId,
        localPath: fileB.path,
        title: 'Title Server B',
        artist: 'Artist B',
        album: 'Album B',
        durationSeconds: 180,
      );

      final lookupA = await service.lookup(serverA, trackId);
      final lookupB = await service.lookup(serverB, trackId);

      final expectedScopeA = OfflineCacheService.safeScopeSegment(serverA);
      final expectedScopeB = OfflineCacheService.safeScopeSegment(serverB);

      expect(lookupA, isNotNull);
      expect(lookupA!.serverScope, expectedScopeA);
      expect(lookupA.compoundKey, '$expectedScopeA:$trackId');
      expect(lookupA.title, 'Title Server A');
      expect(lookupA.byteSize, 100);
      expect(lookupA.durationSeconds, 120);

      expect(lookupB, isNotNull);
      expect(lookupB!.serverScope, expectedScopeB);
      expect(lookupB.compoundKey, '$expectedScopeB:$trackId');
      expect(lookupB.title, 'Title Server B');
      expect(lookupB.byteSize, 200);
      expect(lookupB.durationSeconds, 180);

      expect(await service.usedBytes(serverScope: serverA), 100);
      expect(await service.usedBytes(serverScope: serverB), 200);
      expect(await service.usedBytes(), 300);

      // Verify no raw credentials or URL fragments remain in memory/persisted metadata
      final allEntries = await metadataStore.getAllEntries();
      expect(allEntries, isNotEmpty);
      for (final entry in allEntries) {
        final entryMap = entry.toMap();
        for (final forbidden in [
          'admin',
          'secret',
          'user',
          'token',
          'server-alpha',
          'server-beta'
        ]) {
          expect(entry.serverScope.contains(forbidden), isFalse);
          expect(entry.localPath.contains(forbidden), isFalse);
          expect(entry.compoundKey.contains(forbidden), isFalse);
          for (final val in entryMap.values) {
            if (val is String) {
              expect(val.contains(forbidden), isFalse);
            }
          }
        }
      }

      // Removing server A's track leaves server B's track untouched
      final removed = await service.remove(serverA, trackId);
      expect(removed, isTrue);
      expect(await service.lookup(serverA, trackId), isNull);
      expect(fileA.existsSync(), isFalse);

      final stillExistingB = await service.lookup(serverB, trackId);
      expect(stillExistingB, isNotNull);
      expect(fileB.existsSync(), isTrue);
      expect(await service.usedBytes(), 200);
    });

    test('reject missing: rejects non-existent files and directories',
        () async {
      const serverScope = 'server-1';
      const trackId = 'missing-track';
      final nonExistentPath = '${tempDir.path}/audio/does_not_exist.audio';

      expect(
        () => service.registerFile(
          serverScope: serverScope,
          trackId: trackId,
          localPath: nonExistentPath,
          title: 'Missing',
          artist: 'No Artist',
          album: 'No Album',
          durationSeconds: 60,
        ),
        throwsA(isA<FileSystemException>()),
      );

      final subDir = Directory('${tempDir.path}/a_directory');
      await subDir.create(recursive: true);

      expect(
        () => service.registerFile(
          serverScope: serverScope,
          trackId: 'dir-track',
          localPath: subDir.path,
          title: 'Directory',
          artist: 'No Artist',
          album: 'No Album',
          durationSeconds: 60,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await service.lookup(serverScope, trackId), isNull);
      expect(await service.usedBytes(), 0);
    });

    test(
        'register/lookup+size: returns verified entry with canonical fields and size',
        () async {
      const serverScope = 'prod-server';
      const trackId = 'trk-999';

      final file = await service.getAudioFile(serverScope, trackId);
      await file.writeAsBytes(List.filled(2048, 7));

      final registered = await service.registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: file.path,
        title: 'Song of Time',
        artist: 'Koji Kondo',
        album: 'Ocarina of Time',
        durationSeconds: 145,
        sourceVersion: 'v1.0-stream',
      );

      // Verify all canonical immutable fields
      final expectedScope = OfflineCacheService.safeScopeSegment(serverScope);
      expect(registered.serverScope, expectedScope);
      expect(registered.trackId, trackId);
      expect(registered.localPath, file.path);
      expect(registered.title, 'Song of Time');
      expect(registered.artist, 'Koji Kondo');
      expect(registered.album, 'Ocarina of Time');
      expect(registered.durationSeconds, 145);
      expect(registered.duration, 145);
      expect(registered.byteSize, 2048);
      expect(registered.sourceVersion, 'v1.0-stream');
      expect(registered.sourceMarker, 'v1.0-stream');
      expect(registered.cacheFormatVersion,
          OfflineCacheEntry.defaultCacheFormatVersion);
      expect(registered.formatVersion,
          OfflineCacheEntry.defaultCacheFormatVersion);
      expect(registered.downloadedAt, isNotNull);
      expect(registered.lastAccessedAt, isNotNull);

      final lookedUp = await service.lookup(serverScope, trackId);
      expect(lookedUp, isNotNull);
      expect(lookedUp!.serverScope, expectedScope);
      expect(lookedUp.compoundKey, '$expectedScope:$trackId');
      expect(lookedUp.byteSize, 2048);
      expect(lookedUp.durationSeconds, 145);

      expect(await service.usedBytes(), 2048);
      expect(await service.getTotalSizeBytes(), 2048);
    });

    test('stale file cleanup: missing local file purges metadata on lookup',
        () async {
      const serverScope = 'test-server';
      const trackId = 'stale-track';

      final file = await service.getAudioFile(serverScope, trackId);
      await file.writeAsBytes(List.filled(512, 9));

      await service.registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: file.path,
        title: 'Vanishing Track',
        artist: 'Ghost',
        album: 'Spooky',
        durationSeconds: 90,
      );

      expect(await service.lookup(serverScope, trackId), isNotNull);
      expect(await service.usedBytes(), 512);

      // Manually delete the physical audio file from disk
      file.deleteSync();
      expect(file.existsSync(), isFalse);

      // Lookup must detect the missing file, purge the stale metadata, and return null
      final lookupResult = await service.lookup(serverScope, trackId);
      expect(lookupResult, isNull);

      // Subsequent size check confirms metadata was purged
      expect(await service.usedBytes(), 0);
      expect(await service.getAllEntries(), isEmpty);
    });

    test('remove: deletes entry and physical audio file safely', () async {
      const serverScope = 'server-remove';
      const trackId = 'remove-track';

      final file = await service.getAudioFile(serverScope, trackId);
      await file.writeAsBytes(List.filled(1024, 3));

      await service.registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: file.path,
        title: 'To Be Deleted',
        artist: 'Artist',
        album: 'Album',
        durationSeconds: 100,
      );

      expect(file.existsSync(), isTrue);

      final removed = await service.remove(serverScope, trackId);
      expect(removed, isTrue);
      expect(file.existsSync(), isFalse);
      expect(await service.lookup(serverScope, trackId), isNull);
      expect(await service.usedBytes(), 0);

      // Calling remove again returns false
      expect(await service.remove(serverScope, trackId), isFalse);
    });

    test(
        'clear: removes all owned cache audio contents and preserves root directory',
        () async {
      final file1 = await service.getAudioFile('server-1', 'trk-1');
      final file2 = await service.getAudioFile('server-1', 'trk-2');
      final file3 = await service.getAudioFile('server-2', 'trk-1');

      await file1.writeAsBytes(List.filled(100, 1));
      await file2.writeAsBytes(List.filled(200, 2));
      await file3.writeAsBytes(List.filled(300, 3));

      await service.registerFile(
        serverScope: 'server-1',
        trackId: 'trk-1',
        localPath: file1.path,
        title: 'Track 1',
        artist: 'Artist 1',
        album: 'Album 1',
        durationSeconds: 100,
      );
      await service.registerFile(
        serverScope: 'server-1',
        trackId: 'trk-2',
        localPath: file2.path,
        title: 'Track 2',
        artist: 'Artist 1',
        album: 'Album 1',
        durationSeconds: 100,
      );
      await service.registerFile(
        serverScope: 'server-2',
        trackId: 'trk-1',
        localPath: file3.path,
        title: 'Track 3',
        artist: 'Artist 2',
        album: 'Album 2',
        durationSeconds: 100,
      );

      expect(await service.usedBytes(), 600);

      await service.clear();

      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isFalse);
      expect(file3.existsSync(), isFalse);
      expect(await service.usedBytes(), 0);
      expect(await service.getAllEntries(), isEmpty);

      // Verify the root directory is still intact and operable after clear
      expect(tempDir.existsSync(), isTrue);
      final newFile = await service.getAudioFile('server-1', 'trk-new');
      await newFile.writeAsBytes([1, 2, 3]);
      expect(newFile.existsSync(), isTrue);
    });

    test(
        'traversal/outside-root rejection: neutralizes traversal and rejects outside paths',
        () async {
      // 1. Safe segments neutralize traversal attempts
      const maliciousScope = '../../../etc';
      const maliciousTrack = '../../passwd';

      final safeScope = OfflineCacheService.safeScopeSegment(maliciousScope);
      final safeTrack = OfflineCacheService.safeTrackSegment(maliciousTrack);

      expect(safeScope.contains('..'), isFalse);
      expect(safeScope.contains('/'), isFalse);
      expect(safeScope.contains(r'\'), isFalse);

      expect(safeTrack.contains('..'), isFalse);
      expect(safeTrack.contains('/'), isFalse);
      expect(safeTrack.contains(r'\'), isFalse);

      final safePath = await service.cachePath(maliciousScope, maliciousTrack);
      expect(safePath.startsWith(tempDir.path), isTrue);

      // 2. Reject registering a local path that lies outside cache root
      final externalDir = Directory.systemTemp.createTempSync('external_dir_');
      try {
        final externalFile = File('${externalDir.path}/external.mp3');
        await externalFile.writeAsBytes([1, 2, 3]);

        expect(
          () => service.registerFile(
            serverScope: 'server-1',
            trackId: 'track-ext',
            localPath: externalFile.path,
            title: 'External',
            artist: 'Artist',
            album: 'Album',
            durationSeconds: 10,
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('outside cache root'),
          )),
        );
      } finally {
        if (externalDir.existsSync()) {
          externalDir.deleteSync(recursive: true);
        }
      }
    });

    test('migration from legacy v1 schema purges metadata without files',
        () async {
      final legacyStore = InMemoryOfflineCacheMetadataStore();
      legacyStore.simulateLegacyV1Entries([
        {
          'id': 'legacy-id-1',
          'track_id': 'track-v1-1',
          'title': 'Legacy Song 1',
          'artist': 'Old Artist',
          'album': 'Old Album',
          'duration': 180,
        },
        {
          'id': 'legacy-id-2',
          'track_id': 'track-v1-2',
          'title': 'Legacy Song 2',
          'artist': 'Old Artist',
          'album': 'Old Album',
          'duration': 210,
        },
      ]);

      expect(legacyStore.schemaVersion, 1);
      expect(legacyStore.legacyV1Rows.length, 2);

      final migratingService = OfflineCacheService(
        cacheRootDir: tempDir,
        metadataStore: legacyStore,
      );

      await migratingService.initialize();

      expect(legacyStore.schemaVersion, 2);
      expect(legacyStore.legacyV1Rows, isEmpty);
      expect(await migratingService.getAllEntries(), isEmpty);
      expect(await migratingService.lookup('any-scope', 'track-v1-1'), isNull);
      expect(await migratingService.usedBytes(), 0);
    });

    test(
        'SqfliteOfflineCacheMetadataStore upgradeDatabase executes explicit migration',
        () async {
      final mockDb = _MockDatabaseExecutor();

      await SqfliteOfflineCacheMetadataStore.upgradeDatabase(mockDb, 1, 2);

      expect(
        mockDb.executedSql
            .any((sql) => sql.contains('DROP TABLE IF EXISTS tracks')),
        isTrue,
      );
      expect(
        mockDb.executedSql.any((sql) =>
            sql.contains('CREATE TABLE IF NOT EXISTS offline_entries')),
        isTrue,
      );
    });

    test(
        'actual regular-file size from FileStat wins over caller-supplied byteSize',
        () async {
      const serverScope = 'size-audit-server';
      const trackId = 'size-track-001';

      final file = await service.getAudioFile(serverScope, trackId);
      await file.writeAsBytes(List.filled(512, 42)); // 512 bytes on disk

      // Caller supplies arbitrary/spoofed byteSize: 999999
      final registered = await service.registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: file.path,
        title: 'Size Integrity Track',
        artist: 'Integrity Artist',
        album: 'Integrity Album',
        durationSeconds: 100,
        byteSize: 999999, // Should be ignored in favor of actual 512 bytes
      );

      expect(registered.byteSize, 512);

      final lookedUp = await service.lookup(serverScope, trackId);
      expect(lookedUp, isNotNull);
      expect(lookedUp!.byteSize, 512);

      expect(await service.usedBytes(serverScope: serverScope), 512);
      expect(await service.usedBytes(), 512);
    });

    test(
        'symlink security: rejects symlinks and paths resolving outside cache root',
        () async {
      final externalDir =
          Directory.systemTemp.createTempSync('symlink_outside_root_');
      try {
        final externalAudioFile = File('${externalDir.path}/external.audio');
        await externalAudioFile.writeAsBytes(List.filled(128, 99));

        final symlinkPath = '${tempDir.path}/audio/symlink_track.audio';
        final symlink = Link(symlinkPath);

        bool symlinkSupported = true;
        try {
          await Directory(p.dirname(symlinkPath)).create(recursive: true);
          await symlink.create(externalAudioFile.path);
        } on FileSystemException {
          symlinkSupported = false;
        }

        if (!symlinkSupported) {
          // Host does not support symlink creation; safely skip as required
          return;
        }

        // 1. registerFile must reject symlink resolving outside root
        expect(
          () => service.registerFile(
            serverScope: 'symlink-server',
            trackId: 'trk-symlink',
            localPath: symlink.path,
            title: 'Symlink Exploit Track',
            artist: 'Attacker',
            album: 'Exploit Album',
            durationSeconds: 30,
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('outside cache root'),
          )),
        );

        // 2. lookup must purge stale metadata if localPath points to a symlink resolving outside
        final fakeScopeKey =
            OfflineCacheService.safeScopeSegment('symlink-server');
        final now = DateTime.now();
        await metadataStore.saveEntry(OfflineCacheEntry(
          serverScope: fakeScopeKey,
          trackId: 'injected-symlink-track',
          localPath: symlink.path,
          title: 'Injected Symlink',
          artist: 'Attacker',
          album: 'Exploit Album',
          durationSeconds: 30,
          byteSize: 128,
          downloadedAt: now,
          lastAccessedAt: now,
        ));

        final lookupResult =
            await service.lookup('symlink-server', 'injected-symlink-track');
        expect(lookupResult, isNull);
        expect(
            await metadataStore.getEntry(
                fakeScopeKey, 'injected-symlink-track'),
            isNull);

        // 3. getValidEntries must reject and purge symlink entry
        await metadataStore.saveEntry(OfflineCacheEntry(
          serverScope: fakeScopeKey,
          trackId: 'injected-symlink-track-2',
          localPath: symlink.path,
          title: 'Injected Symlink 2',
          artist: 'Attacker',
          album: 'Exploit Album',
          durationSeconds: 30,
          byteSize: 128,
          downloadedAt: now,
          lastAccessedAt: now,
        ));

        final validEntries =
            await service.getValidEntries(serverScope: 'symlink-server');
        expect(
            validEntries.where((e) => e.trackId == 'injected-symlink-track-2'),
            isEmpty);
        expect(
            await metadataStore.getEntry(
                fakeScopeKey, 'injected-symlink-track-2'),
            isNull);
      } finally {
        if (externalDir.existsSync()) {
          externalDir.deleteSync(recursive: true);
        }
      }
    });

    test(
        'getValidEntries: rejects paths outside cache root and purges invalid metadata',
        () async {
      final externalDir =
          Directory.systemTemp.createTempSync('external_valid_test_');
      try {
        final externalFile = File('${externalDir.path}/secret_audio.audio');
        await externalFile.writeAsBytes(List.filled(256, 77));

        const scope = 'valid-test-server';
        final fakeScopeKey = OfflineCacheService.safeScopeSegment(scope);
        final now = DateTime.now();

        await metadataStore.saveEntry(OfflineCacheEntry(
          serverScope: fakeScopeKey,
          trackId: 'outside-root-track',
          localPath: externalFile.path,
          title: 'Outside Root Track',
          artist: 'Artist',
          album: 'Album',
          durationSeconds: 60,
          byteSize: 256,
          downloadedAt: now,
          lastAccessedAt: now,
        ));

        // Ensure getValidEntries filters out the outside-root entry and purges it
        final validEntries = await service.getValidEntries(serverScope: scope);
        expect(validEntries, isEmpty);
        expect(await metadataStore.getEntry(fakeScopeKey, 'outside-root-track'),
            isNull);
      } finally {
        if (externalDir.existsSync()) {
          externalDir.deleteSync(recursive: true);
        }
      }
    });

    test(
        'reject authenticated URL in sourceVersion: rejects and keeps metadata/bytes empty',
        () async {
      const serverScope = 'https://music.example.com';
      const trackId = 'auth-url-track';
      const authenticatedUrl =
          'https://music.example.com/rest/stream.view?u=alice&t=d41d8cd98f00b204e9800998ecf8427e&s=salt123&v=1.16.1&c=crotowave';

      final file = await service.getAudioFile(serverScope, trackId);
      await file.writeAsBytes(List.filled(256, 1));

      // 1. Trying to register with authenticated URL via registerFile must reject
      expect(
        () => service.registerFile(
          serverScope: serverScope,
          trackId: trackId,
          localPath: file.path,
          title: 'Protected Track',
          artist: 'Secret Artist',
          album: 'Secret Album',
          durationSeconds: 180,
          sourceVersion: authenticatedUrl,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) =>
              e.toString().contains('alice') ||
              e.toString().contains('salt123') ||
              e.toString().contains('d41d8cd98f00b204e9800998ecf8427e') ||
              e.toString().contains('stream.view'),
          'exception must not contain authenticated URL or credentials',
          isFalse,
        )),
      );

      // Verify metadata and used bytes remain empty
      expect(await service.lookup(serverScope, trackId), isNull);
      expect(await service.usedBytes(), 0);
      expect(await service.usedBytes(serverScope: serverScope), 0);
      expect(await metadataStore.getAllEntries(), isEmpty);

      // 2. Delegation via registerCompletedFile must also reject
      expect(
        () => service.registerCompletedFile(
          serverScope: serverScope,
          trackId: trackId,
          localPath: file.path,
          title: 'Protected Track',
          artist: 'Secret Artist',
          album: 'Secret Album',
          durationSeconds: 180,
          sourceMarker: authenticatedUrl,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) =>
              e.toString().contains('alice') ||
              e.toString().contains('salt123') ||
              e.toString().contains('stream.view'),
          'exception must not contain authenticated URL or credentials',
          isFalse,
        )),
      );

      expect(await service.lookup(serverScope, trackId), isNull);
      expect(await service.usedBytes(), 0);
      expect(await metadataStore.getAllEntries(), isEmpty);

      // 3. Various dangerous URI/URL patterns must also reject and keep metadata/bytes empty
      final dangerousPatterns = [
        'http://user:password@server/audio',
        'http://server:4533/stream',
        'https://s3.amazonaws.com/bucket/stream.mp3?X-Amz-Signature=xyz',
        '/rest/stream.view?u=alice&p=secret',
        'stream#access_token=xyz',
        'user@host',
        '//cdn.example.com/audio',
      ];

      for (final pattern in dangerousPatterns) {
        expect(
          () => service.registerFile(
            serverScope: serverScope,
            trackId: trackId,
            localPath: file.path,
            title: 'Dangerous Track',
            artist: 'Attacker',
            album: 'Album',
            durationSeconds: 120,
            sourceVersion: pattern,
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.toString().contains(pattern),
            'exception must not place offending value in exception message',
            isFalse,
          )),
        );
        expect(await service.lookup(serverScope, trackId), isNull);
        expect(await service.usedBytes(), 0);
        expect(await metadataStore.getAllEntries(), isEmpty);
      }

      // 4. Safe opaque version marker example (e.g. v1.0-stream) succeeds and persists
      const safeMarker = 'v1.0-stream';
      final registered = await service.registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: file.path,
        title: 'Safe Track',
        artist: 'Safe Artist',
        album: 'Safe Album',
        durationSeconds: 180,
        sourceVersion: safeMarker,
      );

      expect(registered.sourceVersion, safeMarker);
      expect(registered.sourceMarker, safeMarker);
      expect(await service.usedBytes(), 256);
      final entries = await metadataStore.getAllEntries();
      expect(entries.length, 1);
      expect(entries.first.sourceVersion, safeMarker);
    });

    test('canonicalizePlatformPath normalizes iOS /private/var and /private/tmp paths', () {
      expect(
        OfflineCacheService.canonicalizePlatformPath('/var/mobile/Containers/Data/Application/123/Documents'),
        p.canonicalize('/var/mobile/Containers/Data/Application/123/Documents'),
      );
      if (Platform.isIOS || Platform.isMacOS) {
        expect(
          OfflineCacheService.canonicalizePlatformPath('/private/var/mobile/Containers/Data/Application/123/Documents'),
          '/var/mobile/Containers/Data/Application/123/Documents',
        );
      }
    });
  });
}
