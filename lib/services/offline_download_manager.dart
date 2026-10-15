import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../utils/path_utils.dart';
import 'package:path/path.dart' as p;

import 'navidrome_service.dart';
import 'offline_cache_service.dart';
import 'settings_controller.dart';

/// Status enum representing the lifecycle state of a download task.
enum DownloadTaskStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == DownloadTaskStatus.completed ||
      this == DownloadTaskStatus.cancelled;

  bool get isNonTerminal => !isTerminal;

  bool get isResumable => this == DownloadTaskStatus.paused;

  bool get isRetryable => this == DownloadTaskStatus.failed;
}

/// Sanitized error categories preventing leak of URLs, tokens, or raw exception strings.
enum DownloadFailureCategory {
  notConnected,
  network,
  timeout,
  auth,
  notFound,
  serverError,
  storage,
  cancelled,
  unknown;

  static DownloadFailureCategory fromName(String? name) {
    if (name == null) return DownloadFailureCategory.unknown;
    return DownloadFailureCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => DownloadFailureCategory.unknown,
    );
  }
}

/// Sanitized domain exception for download operations.
class DownloadException implements Exception {
  final String message;
  final DownloadFailureCategory category;

  const DownloadException(
    this.message, {
    this.category = DownloadFailureCategory.unknown,
  });

  @override
  String toString() => 'DownloadException($category): $message';
}

/// Internal cancellation token for aborting in-flight streaming downloads.
class _CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Immutable domain model representing a download task.
class DownloadTask {
  final String serverScope;
  final String trackId;
  final DownloadTaskStatus status;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final String? sourceMarker;
  final int downloadedBytes;
  final int? totalBytes;
  final int retryCount;
  final DownloadFailureCategory? failureCategory;
  final String? failureMessage;
  final DateTime createdAt;
  final DateTime? updatedAt;

  DownloadTask({
    required String serverScope,
    required this.trackId,
    this.status = DownloadTaskStatus.queued,
    required this.title,
    required this.artist,
    required this.album,
    this.durationSeconds = 0,
    this.sourceMarker,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.retryCount = 0,
    this.failureCategory,
    this.failureMessage,
    DateTime? createdAt,
    this.updatedAt,
  })  : serverScope = OfflineCacheService.safeScopeSegment(serverScope),
        createdAt = createdAt ?? DateTime.now() {
    if (trackId.trim().isEmpty) {
      throw ArgumentError('trackId cannot be empty');
    }
    if (downloadedBytes < 0) {
      throw ArgumentError('downloadedBytes must be non-negative');
    }
    if (totalBytes != null && totalBytes! < 0) {
      throw ArgumentError('totalBytes must be non-negative');
    }
    if (retryCount < 0) {
      throw ArgumentError('retryCount must be non-negative');
    }
    OfflineCacheService.validateSourceVersion(sourceMarker);
    _validateSanitizedString(failureMessage, 'failureMessage');
  }

  static void _validateSanitizedString(String? text, String fieldName) {
    if (text == null) return;
    if (text.contains('://') ||
        text.contains('token=') ||
        text.contains('&t=') ||
        text.contains('&s=') ||
        text.contains('salt=') ||
        text.contains('password=') ||
        text.contains('&p=') ||
        text.contains('&u=')) {
      throw ArgumentError(
        '$fieldName contains sensitive URI or credential parameters',
      );
    }
  }

  String get compoundKey => '$serverScope:$trackId';

  bool get isTerminal => status.isTerminal;
  bool get isNonTerminal => status.isNonTerminal;

  double? get progress {
    if (totalBytes == null || totalBytes! <= 0) return null;
    return (downloadedBytes / totalBytes!).clamp(0.0, 1.0);
  }

  DownloadTask copyWith({
    String? serverScope,
    String? trackId,
    DownloadTaskStatus? status,
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? sourceMarker,
    int? downloadedBytes,
    int? totalBytes,
    int? retryCount,
    DownloadFailureCategory? failureCategory,
    bool clearFailureCategory = false,
    String? failureMessage,
    bool clearFailureMessage = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DownloadTask(
      serverScope: serverScope ?? this.serverScope,
      trackId: trackId ?? this.trackId,
      status: status ?? this.status,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      sourceMarker: sourceMarker ?? this.sourceMarker,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      retryCount: retryCount ?? this.retryCount,
      failureCategory: clearFailureCategory
          ? null
          : (failureCategory ?? this.failureCategory),
      failureMessage:
          clearFailureMessage ? null : (failureMessage ?? this.failureMessage),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'server_scope': serverScope,
      'track_id': trackId,
      'status': status.name,
      'title': title,
      'artist': artist,
      'album': album,
      'duration_seconds': durationSeconds,
      'source_marker': sourceMarker,
      'downloaded_bytes': downloadedBytes,
      'total_bytes': totalBytes,
      'retry_count': retryCount,
      'failure_category': failureCategory?.name,
      'failure_message': failureMessage,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    final rawScope = map['server_scope'] as String? ?? 'default';
    final statusName = map['status'] as String?;
    final status = DownloadTaskStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => DownloadTaskStatus.queued,
    );

    final rawCat = map['failure_category'] as String?;
    final category =
        rawCat != null ? DownloadFailureCategory.fromName(rawCat) : null;

    final rawMsg = map['failure_message'] as String?;
    String? sanitizedMsg;
    if (rawMsg != null) {
      try {
        _validateSanitizedString(rawMsg, 'failure_message');
        sanitizedMsg = rawMsg;
      } catch (_) {
        sanitizedMsg = 'Error during download';
      }
    }

    return DownloadTask(
      serverScope: rawScope,
      trackId: map['track_id'] as String? ?? '',
      status: status,
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      sourceMarker: map['source_marker'] as String?,
      downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['total_bytes'] as num?)?.toInt(),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      failureCategory: category,
      failureMessage: sanitizedMsg,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['created_at'] as num).toInt())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['updated_at'] as num).toInt())
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          serverScope == other.serverScope &&
          trackId == other.trackId &&
          status == other.status &&
          downloadedBytes == other.downloadedBytes &&
          totalBytes == other.totalBytes &&
          retryCount == other.retryCount &&
          failureCategory == other.failureCategory &&
          failureMessage == other.failureMessage;

  @override
  int get hashCode => Object.hash(
        serverScope,
        trackId,
        status,
        downloadedBytes,
        totalBytes,
        retryCount,
        failureCategory,
        failureMessage,
      );

  @override
  String toString() =>
      'DownloadTask(scope: $serverScope, trackId: $trackId, status: $status, bytes: $downloadedBytes/$totalBytes)';
}

/// Abstract transport interface allowing decoupling of network streaming from manager logic.
abstract class DownloadTransport {
  Future<void> download({
    required String serverScope,
    required String trackId,
    required File destinationFile,
    String? sourceMarker,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Typedef for closure-based mock/fake transports in unit tests.
typedef DownloadTransportFunction = Future<void> Function({
  required String serverScope,
  required String trackId,
  required File destinationFile,
  String? sourceMarker,
  void Function(int receivedBytes, int? totalBytes)? onProgress,
  bool Function()? isCancelled,
});

/// Function signature for registering a completed file in C1 cache.
typedef C1RegisterFunction = Future<OfflineCacheEntry> Function({
  required String serverScope,
  required String trackId,
  required String localPath,
  required String title,
  required String artist,
  required String album,
  int? durationSeconds,
  String? sourceMarker,
});

/// Adapter creating a [DownloadTransport] from a function callback.
class FunctionalDownloadTransport implements DownloadTransport {
  final DownloadTransportFunction _handler;

  const FunctionalDownloadTransport(this._handler);

  @override
  Future<void> download({
    required String serverScope,
    required String trackId,
    required File destinationFile,
    String? sourceMarker,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) =>
      _handler(
        serverScope: serverScope,
        trackId: trackId,
        destinationFile: destinationFile,
        sourceMarker: sourceMarker,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
}

/// Authenticated Navidrome transport adapter delegating to [NavidromeService].
class NavidromeDownloadTransport implements DownloadTransport {
  final NavidromeService _navidromeService;
  final Duration timeout;

  NavidromeDownloadTransport(
    this._navidromeService, {
    this.timeout = const Duration(seconds: 30),
  });

  String? get serverScope => _navidromeService.serverScope;

  @override
  Future<void> download({
    required String serverScope,
    required String trackId,
    required File destinationFile,
    String? sourceMarker,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    AudioQuality? quality;
    if (sourceMarker != null && sourceMarker.isNotEmpty) {
      quality = AudioQuality.fromName(sourceMarker);
    }
    await _navidromeService.downloadTrackStream(
      trackId: trackId,
      destinationFile: destinationFile,
      quality: quality,
      onProgress: onProgress,
      isCancelled: isCancelled,
      timeout: timeout,
    );
  }
}

/// Bounded offline download manager coordinating track downloads, atomic cache transfer,
/// progress observation, and safe state persistence.
class OfflineDownloadManager extends ChangeNotifier {
  final OfflineCacheService _cacheService;
  final DownloadTransport _transport;
  final File? _persistenceFile;
  final Directory? _persistenceDir;
  final int maxConcurrency;
  final DateTime Function() _now;

  @visibleForTesting
  C1RegisterFunction? c1RegisterSeam;

  @visibleForTesting
  Future<void> Function()? onBeforePersistWrite;

  int _persistCounter = 0;
  bool _isPersisting = false;
  bool _hasPendingWrite = false;
  Completer<void>? _currentWriteCompleter;
  Completer<void>? _nextWriteCompleter;

  Future<void> Function()? beforeInitialize;
  Future<String> Function(DownloadTask task)? destinationResolver;
  Future<void> Function(OfflineCacheEntry entry)? onFileRegistered;

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, _CancellationToken> _activeCancellations = {};
  bool _initialized = false;
  Future<void>? _initialization;
  bool _isDisposed = false;

  OfflineDownloadManager({
    required OfflineCacheService cacheService,
    required DownloadTransport transport,
    File? persistenceFile,
    Directory? persistenceDir,
    this.maxConcurrency = 2,
    DateTime Function()? nowProvider,
    @visibleForTesting this.c1RegisterSeam,
    @visibleForTesting this.onBeforePersistWrite,
  })  : _cacheService = cacheService,
        _transport = transport,
        _persistenceFile = persistenceFile,
        _persistenceDir = persistenceDir,
        _now = nowProvider ?? DateTime.now,
        assert(maxConcurrency > 0, 'maxConcurrency must be positive');

  OfflineCacheService get cacheService => _cacheService;
  DownloadTransport get transport => _transport;
  bool get isInitialized => _initialized;

  /// Returns the deterministic, filesystem-safe temporary [File] path for a download task.
  /// Basename is derived exclusively from opaque safe scope and [OfflineCacheService.safeTrackSegment].
  ///
  /// Con [attemptId] el nombre es único por intento: pausar y reanudar rápido
  /// no deja que el intento viejo borre el temporal del nuevo.
  Future<File> getTempFile(String serverScope, String trackId,
      {String? attemptId}) async {
    final root = await _cacheService.getCacheRootDir();
    final tmpDir = Directory(p.join(root.path, 'download_tmp'));
    if (!await tmpDir.exists()) {
      await tmpDir.create(recursive: true);
    }
    final scope = OfflineCacheService.safeScopeSegment(serverScope);
    final safeTrack = OfflineCacheService.safeTrackSegment(trackId, '.tmp');
    final tempFileName = attemptId == null
        ? '${scope}_$safeTrack'
        : '${scope}_$safeTrack.$attemptId.tmp';
    final tempFilePath =
        normalizePathKeepCase(p.join(tmpDir.path, tempFileName));
    return File(tempFilePath);
  }

  /// Returns an immutable snapshot of all known download tasks.
  List<DownloadTask> get tasks => List.unmodifiable(_tasks.values);

  /// Number of active downloading tasks.
  int get activeCount => _tasks.values
      .where((t) => t.status == DownloadTaskStatus.downloading)
      .length;

  /// Number of queued tasks waiting for a concurrency slot.
  int get queuedCount =>
      _tasks.values.where((t) => t.status == DownloadTaskStatus.queued).length;

  /// Looks up a task by its canonical `serverScope` and `trackId`.
  DownloadTask? getTask(String serverScope, String trackId) {
    final scope = OfflineCacheService.safeScopeSegment(serverScope);
    return _tasks['$scope:$trackId'];
  }

  /// Looks up a task by its composite key (`$serverScope:$trackId`).
  DownloadTask? getTaskByKey(String compoundKey) => _tasks[compoundKey];

  /// Initializes the manager, loads non-sensitive pending tasks from persistence,
  /// converts any previously downloading tasks to paused, cleans temp files, and starts queue processing.
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (_initialized) return;
    await beforeInitialize?.call();
    await _cacheService.initialize();
    await _cleanOrphanedTempFiles();
    await _loadPersistedTasks();
    _initialized = true;
    _processQueue();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Queues an individual canonical [Track] for offline download.
  /// Coalesces duplicate requests for the same nonterminal task.
  Future<DownloadTask> queueTrack(
    Track track, {
    String? serverScope,
    AudioQuality? quality,
    String? sourceMarker,
  }) async {
    await _ensureInitialized();

    final effectiveScope = serverScope ??
        (_transport is NavidromeDownloadTransport
            ? (_transport as NavidromeDownloadTransport).serverScope
            : null);

    if (effectiveScope == null || effectiveScope.trim().isEmpty) {
      throw ArgumentError(
        'serverScope must be provided when transport has no active server scope',
      );
    }

    final canonicalScope = OfflineCacheService.safeScopeSegment(effectiveScope);
    final key = '$canonicalScope:${track.id}';

    // Duplicate coalescing: if task already exists and is nonterminal, return existing
    final existing = _tasks[key];
    if (existing != null && existing.isNonTerminal) {
      return existing;
    }

    // Consultar siempre el archivo, aunque la tarea no sobreviviera al reinicio.
    final cachedEntry = await _cacheService.lookup(canonicalScope, track.id);
    // Otra solicitud puede haber encolado la canción durante la consulta.
    final concurrent = _tasks[key];
    if (concurrent != null && concurrent.isNonTerminal) return concurrent;
    if (cachedEntry != null) {
      final completed = DownloadTask(
        serverScope: canonicalScope,
        trackId: track.id,
        status: DownloadTaskStatus.completed,
        title: track.title,
        artist: track.artist,
        album: track.album,
        downloadedBytes: cachedEntry.byteSize,
        totalBytes: cachedEntry.byteSize,
      );
      _tasks[key] = completed;
      notifyListeners();
      return completed;
    }

    final effectiveMarker = sourceMarker ?? quality?.name;
    final durationSecs = _parseDuration(track.duration);

    final newTask = DownloadTask(
      serverScope: canonicalScope,
      trackId: track.id,
      status: DownloadTaskStatus.queued,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationSeconds: durationSecs,
      sourceMarker: effectiveMarker,
      createdAt: _now(),
    );

    _tasks[key] = newTask;
    notifyListeners();
    await _persistTasks();
    _processQueue();
    return newTask;
  }

  /// Pauses an active or queued download task. Stops active streaming transfer safely.
  Future<bool> pauseTask(String serverScope, String trackId) async {
    await _ensureInitialized();
    final scope = OfflineCacheService.safeScopeSegment(serverScope);
    final key = '$scope:$trackId';
    final task = _tasks[key];
    if (task == null) return false;

    if (task.status == DownloadTaskStatus.downloading) {
      final cancelToken = _activeCancellations[key];
      cancelToken?.cancel();
      _activeCancellations.remove(key);

      _updateTask(
        task.copyWith(
          status: DownloadTaskStatus.paused,
          updatedAt: _now(),
        ),
        persist: true,
      );
      _processQueue();
      return true;
    } else if (task.status == DownloadTaskStatus.queued) {
      _updateTask(
        task.copyWith(
          status: DownloadTaskStatus.paused,
          updatedAt: _now(),
        ),
        persist: true,
      );
      return true;
    }

    return false;
  }

  /// Resumes a paused download task.
  /// Restarts transfer safely from zero bytes rather than assuming byte-range support.
  Future<bool> resumeTask(String serverScope, String trackId) async {
    await _ensureInitialized();
    final scope = OfflineCacheService.safeScopeSegment(serverScope);
    final key = '$scope:$trackId';
    final task = _tasks[key];
    if (task == null) return false;

    if (task.status != DownloadTaskStatus.paused) {
      return false;
    }

    // Safe restart: restart transfer from zero bytes
    _updateTask(
      task.copyWith(
        status: DownloadTaskStatus.queued,
        downloadedBytes: 0,
        updatedAt: _now(),
      ),
      persist: true,
    );
    _processQueue();
    return true;
  }

  /// Cancels a nonterminal task, removes any partial file, and ensures no cache entry is created.
  Future<bool> cancelTask(String serverScope, String trackId) async {
    await _ensureInitialized();
    final scope = OfflineCacheService.safeScopeSegment(serverScope);
    final key = '$scope:$trackId';
    final task = _tasks[key];
    if (task == null) return false;

    if (task.isTerminal) {
      return false;
    }

    if (task.status == DownloadTaskStatus.downloading) {
      final cancelToken = _activeCancellations[key];
      cancelToken?.cancel();
      _activeCancellations.remove(key);
    }

    _updateTask(
      task.copyWith(
        status: DownloadTaskStatus.cancelled,
        updatedAt: _now(),
      ),
      persist: true,
    );
    _processQueue();

    // Remove any partial temp files for this task using exact safe task temp path
    try {
      final tempFile = await getTempFile(scope, trackId);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}

    return true;
  }

  /// Retries a failed task. Retrying works strictly from [DownloadTaskStatus.failed].
  Future<bool> retryTask(String serverScope, String trackId) async {
    await _ensureInitialized();
    final scope = OfflineCacheService.safeScopeSegment(serverScope);
    final key = '$scope:$trackId';
    final task = _tasks[key];
    if (task == null) return false;

    if (task.status != DownloadTaskStatus.failed) {
      return false;
    }

    _updateTask(
      task.copyWith(
        status: DownloadTaskStatus.queued,
        downloadedBytes: 0,
        retryCount: task.retryCount + 1,
        clearFailureCategory: true,
        clearFailureMessage: true,
        updatedAt: _now(),
      ),
      persist: true,
    );
    _processQueue();
    return true;
  }

  void _updateTask(DownloadTask task, {bool persist = true}) {
    _tasks[task.compoundKey] = task;
    if (!_isDisposed) {
      notifyListeners();
    }
    if (persist) {
      _persistTasks();
    }
  }

  void _processQueue() {
    if (!_initialized || _isDisposed) return;

    final activeCount = _tasks.values
        .where((t) => t.status == DownloadTaskStatus.downloading)
        .length;

    final availableSlots = maxConcurrency - activeCount;
    if (availableSlots <= 0) return;

    final candidates = _tasks.values
        .where((t) => t.status == DownloadTaskStatus.queued)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final toStart = candidates.take(availableSlots).toList();
    for (final task in toStart) {
      // Mark as downloading synchronously before async dispatch to prevent race conditions
      final downloadingTask = task.copyWith(
        status: DownloadTaskStatus.downloading,
        updatedAt: _now(),
      );
      _tasks[downloadingTask.compoundKey] = downloadingTask;
      notifyListeners();
      _persistTasks();
      _executeDownload(downloadingTask);
    }
  }

  Future<void> _executeDownload(DownloadTask task) async {
    final key = task.compoundKey;
    final cancelToken = _CancellationToken();
    _activeCancellations[key] = cancelToken;
    final attemptId = '${++_attemptSeq}';

    File? tempFile;
    try {
      // Una tarea restaurada puede tener ya su archivo completo en disco.
      final cached = await _cacheService.lookup(task.serverScope, task.trackId);
      if (cancelToken.isCancelled) return;
      if (cached != null) {
        _updateTask(
            task.copyWith(
              status: DownloadTaskStatus.completed,
              downloadedBytes: cached.byteSize,
              totalBytes: cached.byteSize,
              clearFailureCategory: true,
              clearFailureMessage: true,
              updatedAt: _now(),
            ),
            persist: true);
        return;
      }
      // Comprobar el destino antes de transferir o escribir el audio.
      final resolvedTarget =
          destinationResolver != null ? await destinationResolver!(task) : null;
      if (cancelToken.isCancelled) return;
      tempFile = await getTempFile(task.serverScope, task.trackId,
          attemptId: attemptId);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      if (cancelToken.isCancelled) {
        return;
      }

      await _transport.download(
        serverScope: task.serverScope,
        trackId: task.trackId,
        destinationFile: tempFile,
        sourceMarker: task.sourceMarker,
        onProgress: (received, total) {
          if (cancelToken.isCancelled) return;
          final current = _tasks[key];
          if (current != null &&
              current.status == DownloadTaskStatus.downloading) {
            _updateTask(
              current.copyWith(
                downloadedBytes: received,
                totalBytes: total,
              ),
              persist: false,
            );
          }
        },
        isCancelled: () => cancelToken.isCancelled,
      );

      if (cancelToken.isCancelled) {
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        return;
      }

      if (!await tempFile.exists() || (await tempFile.length()) == 0) {
        throw const DownloadException(
          'Downloaded file is empty or missing',
          category: DownloadFailureCategory.storage,
        );
      }

      // Safe transfer: target file atomically replaced with rollback
      final targetPath = resolvedTarget ??
          await _cacheService.getAudioFilePath(task.serverScope, task.trackId);
      final targetFile = File(targetPath);
      final targetDir = targetFile.parent;
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final backupPath = normalizePathKeepCase(
          p.join(targetDir.path, '${p.basename(targetPath)}.bak'));
      final backupFile = File(backupPath);
      final bool hadExistingTarget = await targetFile.exists();

      if (await backupFile.exists()) {
        try {
          await backupFile.delete();
        } catch (_) {}
      }

      bool swapped = false;
      try {
        if (hadExistingTarget) {
          try {
            await targetFile.rename(backupPath);
          } catch (_) {
            await targetFile.copy(backupPath);
            await targetFile.delete();
          }
        }

        try {
          await tempFile.rename(targetPath);
        } catch (_) {
          await tempFile.copy(targetPath);
          await tempFile.delete();
        }
        swapped = true;

        // Register verified file with C1 cache service
        final entry = await (c1RegisterSeam != null
            ? c1RegisterSeam!(
                serverScope: task.serverScope,
                trackId: task.trackId,
                localPath: targetPath,
                title: task.title,
                artist: task.artist,
                album: task.album,
                durationSeconds: task.durationSeconds,
                sourceMarker: task.sourceMarker,
              )
            : _cacheService.registerFile(
                serverScope: task.serverScope,
                trackId: task.trackId,
                localPath: targetPath,
                title: task.title,
                artist: task.artist,
                album: task.album,
                durationSeconds: task.durationSeconds,
                sourceMarker: task.sourceMarker,
              ));

        await onFileRegistered?.call(entry);

        // Delete backup upon successful registration
        if (hadExistingTarget && await backupFile.exists()) {
          try {
            await backupFile.delete();
          } catch (_) {}
        }

        final current = _tasks[key];
        if (current != null && !cancelToken.isCancelled) {
          _updateTask(
            current.copyWith(
              status: DownloadTaskStatus.completed,
              downloadedBytes: entry.byteSize,
              totalBytes: entry.byteSize,
              clearFailureCategory: true,
              clearFailureMessage: true,
              updatedAt: _now(),
            ),
            persist: true,
          );
        }
      } catch (e) {
        // Rollback atomic swap if swap or registration failed
        if (swapped) {
          if (hadExistingTarget && await backupFile.exists()) {
            try {
              if (await targetFile.exists()) {
                await targetFile.delete();
              }
              try {
                await backupFile.rename(targetPath);
              } catch (_) {
                await backupFile.copy(targetPath);
                await backupFile.delete();
              }
            } catch (e) {
              debugPrint(
                  'OfflineDownloadManager: no se pudo restaurar la copia previa de la descarga: $e');
            }
          } else if (!hadExistingTarget && await targetFile.exists()) {
            try {
              await targetFile.delete();
            } catch (_) {}
          }
        } else {
          if (hadExistingTarget &&
              await backupFile.exists() &&
              !await targetFile.exists()) {
            try {
              await backupFile.rename(targetPath);
            } catch (_) {
              await backupFile.copy(targetPath);
              await backupFile.delete();
            }
          }
        }

        if (await backupFile.exists()) {
          try {
            await backupFile.delete();
          } catch (_) {}
        }

        rethrow;
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        if (tempFile != null && await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        return;
      }

      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      final sanitized = sanitizeError(e);
      final current = _tasks[key];
      if (current != null && current.status == DownloadTaskStatus.downloading) {
        _updateTask(
          current.copyWith(
            status: DownloadTaskStatus.failed,
            failureCategory: sanitized.category,
            failureMessage: sanitized.message,
            updatedAt: _now(),
          ),
          persist: true,
        );
      }
    } finally {
      // Solo quitar el propio token: una reanudación rápida ya registró el suyo.
      if (identical(_activeCancellations[key], cancelToken)) {
        _activeCancellations.remove(key);
      }
      _processQueue();
    }
  }

  int _attemptSeq = 0;

  Future<File> _getPersistenceFile() async {
    if (_persistenceFile != null) return _persistenceFile!;
    if (_persistenceDir != null) {
      return File(p.join(_persistenceDir!.path, 'download_tasks.json'));
    }
    final root = await _cacheService.getCacheRootDir();
    return File(p.join(root.path, 'downloads', 'tasks.json'));
  }

  /// Serializes persistence writes so that an older snapshot can never overwrite
  /// newer persisted state. Returns a [Future] that completes when the state at the time
  /// of the call (or a newer state) has been committed to disk.
  Future<void> _persistTasks() {
    if (!_isPersisting) {
      _isPersisting = true;
      _currentWriteCompleter = Completer<void>();
      final fut = _currentWriteCompleter!.future;
      _runPersistLoop();
      return fut;
    } else {
      _hasPendingWrite = true;
      _nextWriteCompleter ??= Completer<void>();
      return _nextWriteCompleter!.future;
    }
  }

  Future<void> _runPersistLoop() async {
    while (true) {
      final activeCompleter = _currentWriteCompleter;
      try {
        await _writeTasksToDisk();
        if (activeCompleter != null && !activeCompleter.isCompleted) {
          activeCompleter.complete();
        }
      } catch (e, st) {
        if (activeCompleter != null && !activeCompleter.isCompleted) {
          activeCompleter.completeError(e, st);
        }
      }

      if (_hasPendingWrite) {
        _hasPendingWrite = false;
        _currentWriteCompleter = _nextWriteCompleter;
        _nextWriteCompleter = null;
      } else {
        _isPersisting = false;
        _currentWriteCompleter = null;
        _nextWriteCompleter = null;
        break;
      }
    }
  }

  Future<void> _writeTasksToDisk() async {
    try {
      if (onBeforePersistWrite != null) {
        await onBeforePersistWrite!();
      }

      final file = await _getPersistenceFile();
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Only pending/paused/failed/downloading tasks need to survive restart
      final persistentTasks = _tasks.values
          .where((t) =>
              t.status == DownloadTaskStatus.queued ||
              t.status == DownloadTaskStatus.downloading ||
              t.status == DownloadTaskStatus.paused ||
              t.status == DownloadTaskStatus.failed)
          .map((t) => t.toMap())
          .toList();

      final jsonStr = jsonEncode({
        'version': 1,
        'tasks': persistentTasks,
      });

      File? tmpFile;
      try {
        tmpFile = File('${file.path}.${++_persistCounter}.tmp');
        await tmpFile.writeAsString(jsonStr, flush: true);
        try {
          await tmpFile.rename(file.path);
        } catch (_) {
          await tmpFile.copy(file.path);
          await tmpFile.delete();
        }
      } finally {
        if (tmpFile != null && await tmpFile.exists()) {
          try {
            await tmpFile.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // Persistence error must not crash the manager
    }
  }

  /// Waits until all active and pending persistence disk writes have finished.
  Future<void> flushPersistence() async {
    while (_isPersisting || _hasPendingWrite) {
      final fut = _nextWriteCompleter?.future ?? _currentWriteCompleter?.future;
      if (fut != null) {
        try {
          await fut;
        } catch (_) {}
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _loadPersistedTasks() async {
    try {
      final file = await _getPersistenceFile();
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final dynamic data = jsonDecode(content);
      if (data is! Map<String, dynamic>) return;

      final rawTasks = data['tasks'];
      if (rawTasks is! List) return;

      for (final raw in rawTasks) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          var task = DownloadTask.fromMap(raw);
          // Requirement 6: never restore downloading as active automatically—
          // convert it to paused/retryable and require explicit resume.
          if (task.status == DownloadTaskStatus.downloading) {
            task = task.copyWith(
              status: DownloadTaskStatus.paused,
              clearFailureCategory: true,
              clearFailureMessage: true,
              updatedAt: _now(),
            );
          }
          // Completed/cancelled tasks do not survive restart
          if (task.status == DownloadTaskStatus.completed ||
              task.status == DownloadTaskStatus.cancelled) {
            continue;
          }
          _tasks[task.compoundKey] = task;
        } catch (_) {
          // Individual corrupt task entry skipped
        }
      }
    } catch (_) {
      // Corrupt persistence fails closed without touching C1 cache files
      _tasks.clear();
    }
  }

  Future<void> _cleanOrphanedTempFiles() async {
    try {
      final root = await _cacheService.getCacheRootDir();
      final tmpDir = Directory(p.join(root.path, 'download_tmp'));
      if (await tmpDir.exists()) {
        final entities = await tmpDir.list().toList();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static int _parseDuration(String? duration) {
    if (duration == null || duration.trim().isEmpty) return 0;
    final trimmed = duration.trim();
    final numVal = num.tryParse(trimmed);
    if (numVal != null) {
      final intVal = numVal.toInt();
      return intVal >= 0 ? intVal : 0;
    }
    final parts = trimmed.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      final total = m * 60 + s;
      return total >= 0 ? total : 0;
    }
    return 0;
  }

  /// Sanitizes caught exceptions to prevent leaking URLs, credentials, or sensitive headers.
  static ({String message, DownloadFailureCategory category}) sanitizeError(
      dynamic error) {
    if (error is DownloadException) {
      var msg = error.message;
      if (msg.contains('://') ||
          msg.contains('&t=') ||
          msg.contains('&s=') ||
          msg.contains('token=') ||
          msg.contains('password=')) {
        msg = 'Download failed';
      }
      return (message: msg, category: error.category);
    }
    if (error is TimeoutException) {
      return (
        message: 'Connection timed out',
        category: DownloadFailureCategory.timeout,
      );
    }
    if (error is SocketException) {
      return (
        message: 'Network connection failed',
        category: DownloadFailureCategory.network,
      );
    }
    if (error is HttpException) {
      return (
        message: 'HTTP transport error',
        category: DownloadFailureCategory.network,
      );
    }
    if (error is HandshakeException) {
      return (
        message: 'Secure connection failed',
        category: DownloadFailureCategory.network,
      );
    }
    if (error is FileSystemException) {
      return (
        message: 'Local storage error',
        category: DownloadFailureCategory.storage,
      );
    }
    return (
      message: 'Download failed',
      category: DownloadFailureCategory.unknown,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final cancellation in _activeCancellations.values) {
      cancellation.cancel();
    }
    _activeCancellations.clear();
    super.dispose();
  }
}
