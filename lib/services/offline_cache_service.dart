import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Immutable domain model representing a verified offline cached audio track.
class OfflineCacheEntry {
  static const int defaultCacheFormatVersion = 1;
  static const int defaultFormatVersion = defaultCacheFormatVersion;

  final String serverScope;
  final String trackId;
  final String localPath;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final int byteSize;
  final DateTime downloadedAt;
  final DateTime lastAccessedAt;
  final String? sourceVersion;
  final int cacheFormatVersion;

  // Convenient aliases for backward-compatibility
  int get duration => durationSeconds;
  String? get sourceMarker => sourceVersion;
  int get formatVersion => cacheFormatVersion;

  OfflineCacheEntry({
    required String serverScope,
    required this.trackId,
    required this.localPath,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    required this.byteSize,
    required this.downloadedAt,
    required this.lastAccessedAt,
    this.sourceVersion,
    this.cacheFormatVersion = defaultCacheFormatVersion,
  })  : serverScope = OfflineCacheService.safeScopeSegment(serverScope),
        assert(trackId.isNotEmpty, 'trackId cannot be empty'),
        assert(localPath.isNotEmpty, 'localPath cannot be empty'),
        assert(byteSize >= 0, 'byteSize must be non-negative') {
    OfflineCacheService.validateSourceVersion(sourceVersion);
  }

  String get compoundKey => '$serverScope:$trackId';

  OfflineCacheEntry copyWith({
    String? serverScope,
    String? trackId,
    String? localPath,
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    int? duration,
    int? byteSize,
    DateTime? downloadedAt,
    DateTime? lastAccessedAt,
    String? sourceVersion,
    String? sourceMarker,
    int? cacheFormatVersion,
    int? formatVersion,
  }) {
    final effectiveSource = sourceVersion ?? sourceMarker ?? this.sourceVersion;
    OfflineCacheService.validateSourceVersion(effectiveSource);
    return OfflineCacheEntry(
      serverScope: serverScope ?? this.serverScope,
      trackId: trackId ?? this.trackId,
      localPath: localPath ?? this.localPath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationSeconds: durationSeconds ?? duration ?? this.durationSeconds,
      byteSize: byteSize ?? this.byteSize,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      sourceVersion: effectiveSource,
      cacheFormatVersion:
          cacheFormatVersion ?? formatVersion ?? this.cacheFormatVersion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'server_scope': serverScope,
      'track_id': trackId,
      'local_path': localPath,
      'title': title,
      'artist': artist,
      'album': album,
      'duration_seconds': durationSeconds,
      'byte_size': byteSize,
      'downloaded_at': downloadedAt.millisecondsSinceEpoch,
      'last_accessed_at': lastAccessedAt.millisecondsSinceEpoch,
      'source_version': sourceVersion,
      'cache_format_version': cacheFormatVersion,
    };
  }

  factory OfflineCacheEntry.fromMap(Map<String, dynamic> map) {
    final rawByteSize = (map['byte_size'] as num?)?.toInt() ?? 0;
    final dur = (map['duration_seconds'] as num?)?.toInt() ??
        (map['duration'] as num?)?.toInt() ??
        0;
    final src =
        (map['source_version'] as String?) ?? (map['source_marker'] as String?);
    final fmt = (map['cache_format_version'] as num?)?.toInt() ??
        (map['format_version'] as num?)?.toInt() ??
        defaultCacheFormatVersion;
    final rawScope = (map['server_scope'] as String?)?.trim() ?? '';
    final scope = rawScope.isEmpty ? 'default' : rawScope;

    String? safeSrc;
    if (src != null && OfflineCacheService.isSafeSourceVersion(src)) {
      safeSrc = src;
    }

    return OfflineCacheEntry(
      serverScope: scope,
      trackId: map['track_id'] as String? ?? '',
      localPath: map['local_path'] as String? ?? '',
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      durationSeconds: dur < 0 ? 0 : dur,
      byteSize: rawByteSize < 0 ? 0 : rawByteSize,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['downloaded_at'] as num?)?.toInt() ?? 0,
      ),
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['last_accessed_at'] as num?)?.toInt() ?? 0,
      ),
      sourceVersion: safeSrc,
      cacheFormatVersion: fmt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfflineCacheEntry &&
          runtimeType == other.runtimeType &&
          serverScope == other.serverScope &&
          trackId == other.trackId &&
          localPath == other.localPath &&
          byteSize == other.byteSize &&
          durationSeconds == other.durationSeconds &&
          sourceVersion == other.sourceVersion &&
          cacheFormatVersion == other.cacheFormatVersion;

  @override
  int get hashCode => Object.hash(
        serverScope,
        trackId,
        localPath,
        byteSize,
        durationSeconds,
        sourceVersion,
        cacheFormatVersion,
      );

  @override
  String toString() =>
      'OfflineCacheEntry(scope: $serverScope, trackId: $trackId, path: $localPath, size: $byteSize bytes)';
}

/// Abstract metadata store for offline cache entries.
abstract class OfflineCacheMetadataStore {
  Future<void> init();
  Future<void> saveEntry(OfflineCacheEntry entry);
  Future<OfflineCacheEntry?> getEntry(String serverScope, String trackId);
  Future<List<OfflineCacheEntry>> getAllEntries({String? serverScope});
  Future<int> getTotalSizeBytes({String? serverScope});
  Future<bool> deleteEntry(String serverScope, String trackId);
  Future<void> clearAll();
  Future<void> close();
}

/// SQLite-backed persistent metadata store.
class SqfliteOfflineCacheMetadataStore implements OfflineCacheMetadataStore {
  static const String dbName = 'offline_cache.db';
  static const String tableName = 'offline_entries';
  static const int currentVersion = 2;

  final Database? _injectedDb;
  final String? _customDbPath;
  Database? _db;

  SqfliteOfflineCacheMetadataStore({
    Database? database,
    String? customDbPath,
  })  : _injectedDb = database,
        _customDbPath = customDbPath;

  Future<Database> _getDatabase() async {
    if (_injectedDb != null) return _injectedDb!;
    if (_db != null && _db!.isOpen) return _db!;

    String path;
    if (_customDbPath != null) {
      path = _customDbPath!;
    } else {
      final docDir = await getAppDataDirectory();
      path = p.join(docDir.path, dbName);
    }

    _db = await openDatabase(
      path,
      version: currentVersion,
      onCreate: (db, version) async {
        await createTablesV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await upgradeDatabase(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tracks'",
        );
        if (tables.isNotEmpty) {
          await db.execute('DROP TABLE IF EXISTS tracks');
        }
      },
    );
    return _db!;
  }

  static Future<void> createTablesV2(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        server_scope TEXT NOT NULL,
        track_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        byte_size INTEGER NOT NULL DEFAULT 0,
        downloaded_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL,
        source_version TEXT,
        cache_format_version INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (server_scope, track_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_entries_scope ON $tableName (server_scope)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_offline_entries_accessed ON $tableName (last_accessed_at)',
    );
  }

  static Future<void> upgradeDatabase(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // Legacy schema version 1 only stored metadata without audio files.
      // Never treat legacy metadata with no actual local file as offline-ready.
      await db.execute('DROP TABLE IF EXISTS tracks');
      await db.execute('DROP TABLE IF EXISTS $tableName');
      await createTablesV2(db);
    }
  }

  @override
  Future<void> init() async {
    await _getDatabase();
  }

  @override
  Future<void> saveEntry(OfflineCacheEntry entry) async {
    final db = await _getDatabase();
    await db.insert(
      tableName,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<OfflineCacheEntry?> getEntry(
      String serverScope, String trackId) async {
    final db = await _getDatabase();
    final canonicalScope = OfflineCacheService.safeScopeSegment(serverScope);
    final results = await db.query(
      tableName,
      where: 'server_scope = ? AND track_id = ?',
      whereArgs: [canonicalScope, trackId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return OfflineCacheEntry.fromMap(results.first);
  }

  @override
  Future<List<OfflineCacheEntry>> getAllEntries({String? serverScope}) async {
    final db = await _getDatabase();
    final List<Map<String, dynamic>> results;
    if (serverScope != null && serverScope.isNotEmpty) {
      final canonicalScope = OfflineCacheService.safeScopeSegment(serverScope);
      results = await db.query(
        tableName,
        where: 'server_scope = ?',
        whereArgs: [canonicalScope],
        orderBy: 'last_accessed_at DESC',
      );
    } else {
      results = await db.query(
        tableName,
        orderBy: 'last_accessed_at DESC',
      );
    }
    return results.map(OfflineCacheEntry.fromMap).toList();
  }

  @override
  Future<int> getTotalSizeBytes({String? serverScope}) async {
    final db = await _getDatabase();
    final List<Map<String, dynamic>> result;
    if (serverScope != null && serverScope.isNotEmpty) {
      final canonicalScope = OfflineCacheService.safeScopeSegment(serverScope);
      result = await db.rawQuery(
        'SELECT COALESCE(SUM(byte_size), 0) as total FROM $tableName WHERE server_scope = ?',
        [canonicalScope],
      );
    } else {
      result = await db.rawQuery(
        'SELECT COALESCE(SUM(byte_size), 0) as total FROM $tableName',
      );
    }
    if (result.isEmpty) return 0;
    final total = (result.first['total'] as num?)?.toInt() ?? 0;
    return total < 0 ? 0 : total;
  }

  @override
  Future<bool> deleteEntry(String serverScope, String trackId) async {
    final db = await _getDatabase();
    final canonicalScope = OfflineCacheService.safeScopeSegment(serverScope);
    final count = await db.delete(
      tableName,
      where: 'server_scope = ? AND track_id = ?',
      whereArgs: [canonicalScope, trackId],
    );
    return count > 0;
  }

  @override
  Future<void> clearAll() async {
    final db = await _getDatabase();
    await db.delete(tableName);
  }

  @override
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}

/// In-memory metadata store implementation for fast, isolated unit testing.
class InMemoryOfflineCacheMetadataStore implements OfflineCacheMetadataStore {
  final Map<String, OfflineCacheEntry> _entries = {};
  bool _initialized = false;
  int schemaVersion;
  final List<Map<String, dynamic>> _legacyV1Rows = [];

  InMemoryOfflineCacheMetadataStore({this.schemaVersion = 2});

  bool get isInitialized => _initialized;

  void simulateLegacyV1Entries(List<Map<String, dynamic>> legacyRows) {
    schemaVersion = 1;
    _legacyV1Rows.clear();
    _legacyV1Rows.addAll(legacyRows);
  }

  List<Map<String, dynamic>> get legacyV1Rows =>
      List.unmodifiable(_legacyV1Rows);

  @override
  Future<void> init() async {
    if (schemaVersion < 2) {
      // Legacy schema version 1 had no audio files and must be dropped.
      _legacyV1Rows.clear();
      schemaVersion = 2;
    }
    _initialized = true;
  }

  String _key(String serverScope, String trackId) {
    final canonicalScope = OfflineCacheService.safeScopeSegment(serverScope);
    return '$canonicalScope:$trackId';
  }

  @override
  Future<void> saveEntry(OfflineCacheEntry entry) async {
    _entries[_key(entry.serverScope, entry.trackId)] = entry;
  }

  @override
  Future<OfflineCacheEntry?> getEntry(
      String serverScope, String trackId) async {
    return _entries[_key(serverScope, trackId)];
  }

  @override
  Future<List<OfflineCacheEntry>> getAllEntries({String? serverScope}) async {
    final values = _entries.values.toList();
    if (serverScope != null && serverScope.isNotEmpty) {
      final canonicalScope = OfflineCacheService.safeScopeSegment(serverScope);
      return values.where((e) => e.serverScope == canonicalScope).toList();
    }
    return values;
  }

  @override
  Future<int> getTotalSizeBytes({String? serverScope}) async {
    final entries = await getAllEntries(serverScope: serverScope);
    final total = entries.fold<int>(
      0,
      (sum, e) => sum + (e.byteSize > 0 ? e.byteSize : 0),
    );
    return total < 0 ? 0 : total;
  }

  @override
  Future<bool> deleteEntry(String serverScope, String trackId) async {
    return _entries.remove(_key(serverScope, trackId)) != null;
  }

  @override
  Future<void> clearAll() async {
    _entries.clear();
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }
}

/// Service managing offline cached audio files and verified metadata.
class OfflineCacheService {
  final Directory? _cacheRootDir;
  final OfflineCacheMetadataStore _metadataStore;
  Directory? _resolvedRootDir;
  bool _initialized = false;

  OfflineCacheService({
    Directory? cacheRootDir,
    OfflineCacheMetadataStore? metadataStore,
  })  : _cacheRootDir = cacheRootDir,
        _metadataStore = metadataStore ?? SqfliteOfflineCacheMetadataStore();

  // Solo se autorizan raíces elegidas y comprobadas por Música local.
  final List<Directory> _musicRoots = [];

  void allowMusicRoot(Directory root) {
    if (!_musicRoots.any((item) => item.absolute.path == root.absolute.path)) {
      _musicRoots.add(root.absolute);
    }
  }

  Directory _rootForPath(String path, Directory fallback) {
    final absolute = p.canonicalize(p.absolute(path));
    for (final root in _musicRoots) {
      if (p.isWithin(p.canonicalize(root.path), absolute)) return root;
    }
    return fallback;
  }

  Future<Directory> getCacheRootDir() async {
    if (_resolvedRootDir != null) return _resolvedRootDir!;
    if (_cacheRootDir != null) {
      _resolvedRootDir = _cacheRootDir!;
    } else {
      final base = await getApplicationSupportDirectory();
      _resolvedRootDir = Directory(p.join(base.path, 'offline_cache'));
    }
    if (!_resolvedRootDir!.existsSync()) {
      _resolvedRootDir!.createSync(recursive: true);
    }
    return _resolvedRootDir!;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await getCacheRootDir();
    await _metadataStore.init();
    _initialized = true;
    await _purgeStaleEntries();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  Future<void> _purgeStaleEntries() async {
    final root = await getCacheRootDir();
    final allEntries = await _metadataStore.getAllEntries();
    for (final entry in allEntries) {
      if (!await _isPathValidAndWithinRoot(
          entry.localPath, _rootForPath(entry.localPath, root))) {
        await _metadataStore.deleteEntry(entry.serverScope, entry.trackId);
      }
    }
  }

  /// Derives an opaque, deterministic, filesystem-safe directory segment from [serverScope].
  /// Never exposes credentials, usernames, or URLs in directory names or metadata.
  static String safeScopeSegment(String serverScope) {
    final trimmed = serverScope.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('serverScope cannot be empty');
    }
    if (RegExp(r'^srv_[0-9a-f]{32}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final hash = sha256.convert(utf8.encode(trimmed)).toString();
    return 'srv_${hash.substring(0, 32)}';
  }

  /// Derives an opaque, deterministic, filesystem-safe file segment from [trackId].
  static String safeTrackSegment(String trackId, [String? extension]) {
    if (trackId.trim().isEmpty) {
      throw ArgumentError('trackId cannot be empty');
    }
    final hash = sha256.convert(utf8.encode(trackId.trim())).toString();
    final ext = (extension != null && extension.isNotEmpty)
        ? (extension.startsWith('.') ? extension : '.$extension')
        : '.audio';
    final safeExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
    return 'trk_${hash.substring(0, 32)}$safeExt';
  }

  /// Checks whether [sourceVersion] is a safe opaque version marker and not a URL, URI,
  /// or credential-bearing string.
  ///
  /// Rejects values that contain URI/URL delimiters (at a minimum `://`, `?`, `#`, `@`) or
  /// look like a URI/URL. Offending values are NEVER included in error messages or logs.
  static bool isSafeSourceVersion(String? sourceVersion) {
    if (sourceVersion == null) return true;
    final trimmed = sourceVersion.trim();
    if (trimmed.isEmpty) return true;

    // Minimum required delimiter checks: ://, ?, #, @, control chars
    if (trimmed.contains('://') ||
        trimmed.contains('?') ||
        trimmed.contains('#') ||
        trimmed.contains('@') ||
        trimmed.contains('\x00') ||
        trimmed.contains('\n') ||
        trimmed.contains('\r')) {
      return false;
    }

    // Scheme-relative or double-slash
    if (trimmed.contains('//')) {
      return false;
    }

    // Common URI scheme prefixes
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http:') ||
        lower.startsWith('https:') ||
        lower.startsWith('ftp:') ||
        lower.startsWith('file:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('ws:') ||
        lower.startsWith('wss:')) {
      return false;
    }

    // Check if it parses as a URI with a scheme, authority, query, or fragment
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      if (uri.hasScheme &&
          (uri.scheme == 'http' ||
              uri.scheme == 'https' ||
              uri.scheme == 'ftp' ||
              uri.scheme == 'file' ||
              uri.scheme == 'blob' ||
              uri.scheme == 'data' ||
              uri.scheme == 'ws' ||
              uri.scheme == 'wss')) {
        return false;
      }
      if (uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        return false;
      }
    }

    return true;
  }

  /// Throws [ArgumentError] if [sourceVersion] is not a safe opaque version marker.
  /// The offending value is NEVER placed in the exception message or logs.
  static void validateSourceVersion(String? sourceVersion) {
    if (!isSafeSourceVersion(sourceVersion)) {
      throw ArgumentError(
        'sourceVersion must be an opaque version marker and cannot be a URL or contain URI/credential delimiters',
      );
    }
  }

  /// Ensures that [targetPath] resolves strictly inside [rootDir] lexically.
  void _validatePathWithinRoot(String targetPath, Directory rootDir) {
    final canonicalTarget = p.canonicalize(p.absolute(targetPath));
    final canonicalRoot = p.canonicalize(p.absolute(rootDir.path));
    if (!p.isWithin(canonicalRoot, canonicalTarget) &&
        canonicalTarget != canonicalRoot) {
      throw ArgumentError('Path is outside cache root: $targetPath');
    }
  }

  /// Validates a file for registration: lexical check, existence, symlink check,
  /// resolved canonical target check, and regular file check.
  Future<FileStat> _validateFileForRegistration(
      String localPath, Directory rootDir) async {
    _validatePathWithinRoot(localPath, rootDir);

    final entityType =
        await FileSystemEntity.type(localPath, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileSystemException('Audio file does not exist', localPath);
    }
    if (entityType == FileSystemEntityType.link) {
      throw ArgumentError(
          'Path is outside cache root or is a symlink: $localPath');
    }
    if (entityType != FileSystemEntityType.file) {
      throw ArgumentError('Path does not point to a regular file: $localPath');
    }

    final file = File(localPath);
    final resolvedPath = await file.resolveSymbolicLinks();
    final resolvedRoot = await rootDir.resolveSymbolicLinks();
    final canonicalResolved = p.canonicalize(p.absolute(resolvedPath));
    final canonicalResolvedRoot = p.canonicalize(p.absolute(resolvedRoot));
    if (!p.isWithin(canonicalResolvedRoot, canonicalResolved) &&
        canonicalResolved != canonicalResolvedRoot) {
      throw ArgumentError('Path is outside cache root: $localPath');
    }

    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError('Path does not point to a regular file: $localPath');
    }

    return stat;
  }

  Future<bool> _isPathValidAndWithinRoot(String path, Directory rootDir) async {
    try {
      final canonicalTarget = p.canonicalize(p.absolute(path));
      final canonicalRoot = p.canonicalize(p.absolute(rootDir.path));
      if (!p.isWithin(canonicalRoot, canonicalTarget) &&
          canonicalTarget != canonicalRoot) {
        return false;
      }

      final entityType = FileSystemEntity.typeSync(path, followLinks: false);
      if (entityType != FileSystemEntityType.file) {
        return false;
      }

      final file = File(path);
      final resolvedPath = file.resolveSymbolicLinksSync();
      final resolvedRoot = rootDir.resolveSymbolicLinksSync();
      final canonicalResolved = p.canonicalize(p.absolute(resolvedPath));
      final canonicalResolvedRoot = p.canonicalize(p.absolute(resolvedRoot));
      if (!p.isWithin(canonicalResolvedRoot, canonicalResolved) &&
          canonicalResolved != canonicalResolvedRoot) {
        return false;
      }

      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the deterministic target audio file path for a `(serverScope, trackId)` pair.
  Future<String> getAudioFilePath(
    String serverScope,
    String trackId, {
    String? extension,
  }) async {
    await _ensureInitialized();
    final root = await getCacheRootDir();
    final scopeDir = safeScopeSegment(serverScope);
    final trackFile = safeTrackSegment(trackId, extension);
    final filePath =
        p.canonicalize(p.join(root.path, 'audio', scopeDir, trackFile));
    _validatePathWithinRoot(filePath, root);
    return filePath;
  }

  /// Alias for [getAudioFilePath] representing cache path for scope+track.
  Future<String> cachePath(
    String serverScope,
    String trackId, {
    String? extension,
  }) =>
      getAudioFilePath(serverScope, trackId, extension: extension);

  /// Returns a [File] handle at the target audio cache path, ensuring its parent directory exists.
  Future<File> getAudioFile(
    String serverScope,
    String trackId, {
    String? extension,
  }) async {
    final path =
        await getAudioFilePath(serverScope, trackId, extension: extension);
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  /// Registers an existing completed local audio file in the cache after verifying
  /// it exists, is a regular file, does not contain symlinks escaping the cache root,
  /// and resides strictly within the service-owned root.
  ///
  /// Always records actual regular-file bytes from [FileStat], ignoring caller-supplied [byteSize].
  Future<OfflineCacheEntry> registerFile({
    required String serverScope,
    required String trackId,
    required String localPath,
    required String title,
    required String artist,
    required String album,
    int? durationSeconds,
    int? duration,
    int? byteSize,
    String? sourceVersion,
    String? sourceMarker,
  }) async {
    validateSourceVersion(sourceVersion);
    validateSourceVersion(sourceMarker);
    final effectiveSource = sourceVersion ?? sourceMarker;

    await _ensureInitialized();
    final root = await getCacheRootDir();
    final stat = await _validateFileForRegistration(
        localPath, _rootForPath(localPath, root));

    final int actualByteSize = stat.size >= 0 ? stat.size : 0;
    final effectiveDuration = durationSeconds ?? duration ?? 0;
    final canonicalScope = safeScopeSegment(serverScope);

    final now = DateTime.now();
    final entry = OfflineCacheEntry(
      serverScope: canonicalScope,
      trackId: trackId,
      localPath: p.canonicalize(p.absolute(localPath)),
      title: title,
      artist: artist,
      album: album,
      durationSeconds: effectiveDuration >= 0 ? effectiveDuration : 0,
      byteSize: actualByteSize,
      downloadedAt: now,
      lastAccessedAt: now,
      sourceVersion: effectiveSource,
      cacheFormatVersion: OfflineCacheEntry.defaultCacheFormatVersion,
    );

    await _metadataStore.saveEntry(entry);
    return entry;
  }

  /// Alias for [registerFile] maintaining backward compatibility.
  Future<OfflineCacheEntry> registerCompletedFile({
    required String serverScope,
    required String trackId,
    required String localPath,
    required String title,
    required String artist,
    required String album,
    int? durationSeconds,
    int? duration,
    int? byteSize,
    String? sourceVersion,
    String? sourceMarker,
  }) =>
      registerFile(
        serverScope: serverScope,
        trackId: trackId,
        localPath: localPath,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds ?? duration,
        byteSize: byteSize,
        sourceVersion: sourceVersion,
        sourceMarker: sourceMarker,
      );

  /// Looks up a cached entry. Verifies that the underlying audio file exists, is a regular file,
  /// and is strictly within root. If missing, a symlink, or invalid, stale metadata is purged and `null` is returned.
  Future<OfflineCacheEntry?> lookup(String serverScope, String trackId) async {
    await _ensureInitialized();
    final canonicalScope = safeScopeSegment(serverScope);
    final entry = await _metadataStore.getEntry(canonicalScope, trackId);
    if (entry == null) return null;

    final root = await getCacheRootDir();
    final valid = await _isPathValidAndWithinRoot(
        entry.localPath, _rootForPath(entry.localPath, root));
    if (!valid) {
      await _metadataStore.deleteEntry(canonicalScope, trackId);
      return null;
    }

    final updated = entry.copyWith(lastAccessedAt: DateTime.now());
    await _metadataStore.saveEntry(updated);
    return updated;
  }

  /// Retira solo los metadatos, conservando cualquier archivo del usuario.
  Future<void> forget(String serverScope, String trackId) async {
    await _ensureInitialized();
    await _metadataStore.deleteEntry(safeScopeSegment(serverScope), trackId);
  }

  /// Alias for [lookup].
  Future<OfflineCacheEntry?> getEntry(String serverScope, String trackId) =>
      lookup(serverScope, trackId);

  /// Calculates the total bytes used by cached entries, ensuring non-negative result.
  Future<int> usedBytes({String? serverScope}) async {
    await _ensureInitialized();
    final canonicalScope = (serverScope != null && serverScope.isNotEmpty)
        ? safeScopeSegment(serverScope)
        : null;
    final total =
        await _metadataStore.getTotalSizeBytes(serverScope: canonicalScope);
    return total < 0 ? 0 : total;
  }

  /// Alias for [usedBytes].
  Future<int> getTotalSizeBytes({String? serverScope}) =>
      usedBytes(serverScope: serverScope);

  /// Removes a single entry and its physical audio file safely.
  Future<bool> remove(String serverScope, String trackId) async {
    await _ensureInitialized();
    final canonicalScope = safeScopeSegment(serverScope);
    final root = await getCacheRootDir();
    final entry = await _metadataStore.getEntry(canonicalScope, trackId);
    bool fileRemoved = false;

    if (entry != null) {
      try {
        if (await _isPathValidAndWithinRoot(
            entry.localPath, _rootForPath(entry.localPath, root))) {
          final file = File(entry.localPath);
          if (await file.exists()) {
            await file.delete();
            fileRemoved = true;
          }
        }
      } catch (_) {
        // Path validation or deletion errors ignored for safety
      }
      await _metadataStore.deleteEntry(canonicalScope, trackId);
      return true;
    } else {
      // Clean up orphan file at default path if present
      try {
        final expectedPath = await getAudioFilePath(canonicalScope, trackId);
        final file = File(expectedPath);
        if (await file.exists()) {
          await file.delete();
          fileRemoved = true;
        }
      } catch (e) {
        debugPrint(
            'OfflineCacheService: no se pudo borrar el archivo de audio: $e');
      }
    }
    return fileRemoved;
  }

  /// Alias for [remove].
  Future<bool> removeEntry(String serverScope, String trackId) =>
      remove(serverScope, trackId);

  /// Safely removes only owned cache audio contents and clears all metadata.
  Future<void> clear() async {
    await _ensureInitialized();
    final root = await getCacheRootDir();

    final audioDir = Directory(p.join(root.path, 'audio'));
    if (await audioDir.exists()) {
      _validatePathWithinRoot(audioDir.path, root);
      await audioDir.delete(recursive: true);
      await audioDir.create(recursive: true);
    }

    await _metadataStore.clearAll();
  }

  /// Aliases for [clear].
  Future<void> clearAll() => clear();
  Future<void> clearCache() => clear();

  /// Returns all metadata entries without disk validation.
  Future<List<OfflineCacheEntry>> getAllEntries({String? serverScope}) async {
    await _ensureInitialized();
    final canonicalScope = (serverScope != null && serverScope.isNotEmpty)
        ? safeScopeSegment(serverScope)
        : null;
    return _metadataStore.getAllEntries(serverScope: canonicalScope);
  }

  /// Returns verified cached entries, purging any stale metadata whose file no longer exists,
  /// is outside root, or is a symlink.
  Future<List<OfflineCacheEntry>> getValidEntries({String? serverScope}) async {
    await _ensureInitialized();
    final canonicalScope = (serverScope != null && serverScope.isNotEmpty)
        ? safeScopeSegment(serverScope)
        : null;
    final root = await getCacheRootDir();
    final entries =
        await _metadataStore.getAllEntries(serverScope: canonicalScope);
    final valid = <OfflineCacheEntry>[];
    for (final entry in entries) {
      if (await _isPathValidAndWithinRoot(
          entry.localPath, _rootForPath(entry.localPath, root))) {
        valid.add(entry);
      } else {
        await _metadataStore.deleteEntry(entry.serverScope, entry.trackId);
      }
    }
    return valid;
  }

  /// Releases storage and database resources.
  Future<void> close() async {
    await _metadataStore.close();
    _initialized = false;
  }
}
