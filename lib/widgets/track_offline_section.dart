part of 'track_context_menu.dart';

/// Estados de UI para la acción de descarga sin conexión de una pista.
enum TrackOfflineUiState {
  notDownloaded,
  queued,
  downloading,
  paused,
  failed,
  availableOffline,
}

/// Representación del estado resuelto para la acción de descarga sin conexión.
class TrackOfflineActionState {
  final TrackOfflineUiState status;
  final DownloadTask? task;
  final double? progress;
  final String? failureMessage;

  const TrackOfflineActionState({
    required this.status,
    this.task,
    this.progress,
    this.failureMessage,
  });

  /// Resuelve el estado de UI considerando tanto el estado del gestor de descargas
  /// como la verificación real de caché C1.
  ///
  /// Un estado completado en el gestor por sí solo NO se considera prueba de
  /// disponibilidad sin conexión; se requiere [hasVerifiedCache] == true.
  static TrackOfflineActionState resolve({
    required DownloadTask? task,
    required bool hasVerifiedCache,
  }) {
    if (task != null && task.isNonTerminal) {
      switch (task.status) {
        case DownloadTaskStatus.queued:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.queued,
            task: task,
            progress: task.progress,
          );
        case DownloadTaskStatus.downloading:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.downloading,
            task: task,
            progress: task.progress,
          );
        case DownloadTaskStatus.paused:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.paused,
            task: task,
            progress: task.progress,
          );
        case DownloadTaskStatus.failed:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.failed,
            task: task,
            progress: task.progress,
            failureMessage: task.failureMessage,
          );
        case DownloadTaskStatus.completed:
        case DownloadTaskStatus.cancelled:
          break;
      }
    }

    if (hasVerifiedCache) {
      return TrackOfflineActionState(
        status: TrackOfflineUiState.availableOffline,
        task: task,
      );
    }

    // Sin tarea, cancelada, o completada pero sin registro verificado en caché
    return const TrackOfflineActionState(
      status: TrackOfflineUiState.notDownloaded,
    );
  }
}

/// Sección interactiva de acciones y estado de descarga sin conexión para una pista.
class TrackOfflineSection extends StatefulWidget {
  final Track track;
  final String? serverScope;
  final OfflineDownloadManager? downloadManager;
  final OfflineCacheService? cacheService;

  const TrackOfflineSection({
    super.key,
    required this.track,
    this.serverScope,
    this.downloadManager,
    this.cacheService,
  });

  @override
  State<TrackOfflineSection> createState() => _TrackOfflineSectionState();
}

class _TrackOfflineSectionState extends State<TrackOfflineSection> {
  Future<OfflineCacheEntry?>? _lookupFuture;
  DownloadTaskStatus? _lastTaskStatus;
  OfflineCacheService? _cachedService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = widget.cacheService ??
        Provider.of<OfflineCacheService?>(context, listen: false);
    if (service != _cachedService) {
      _cachedService = service;
      _triggerLookup();
    }
  }

  @override
  void didUpdateWidget(TrackOfflineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.serverScope != widget.serverScope ||
        oldWidget.cacheService != widget.cacheService) {
      _cachedService = widget.cacheService ?? _cachedService;
      _triggerLookup();
    }
  }

  void _triggerLookup() {
    final scope = widget.serverScope;
    final service = widget.cacheService ?? _cachedService;
    if (scope != null && scope.trim().isNotEmpty && service != null) {
      _lookupFuture = service.lookup(scope, widget.track.id);
    } else {
      _lookupFuture = Future.value(null);
    }
  }

  Future<void> _handleQueue(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null) return;
    if (serverScope == null || serverScope.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('No hay un servidor conectado para descargar.'),
          backgroundColor: bg,
        ),
      );
      return;
    }

    try {
      final music = Provider.of<LocalMusicService?>(context, listen: false);
      if (music != null) {
        await music.download(manager, track, serverScope);
      } else {
        await manager.queueTrack(track, serverScope: serverScope);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Descarga añadida para "${track.title}"'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al solicitar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handlePause(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.pauseTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al pausar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handleResume(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.resumeTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al reanudar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handleRetry(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.retryTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al reintentar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handleCancel(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.cancelTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al cancelar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager =
        widget.downloadManager ?? Provider.of<OfflineDownloadManager?>(context);

    if (manager != null) {
      return AnimatedBuilder(
        animation: manager,
        builder: (context, _) => _buildWithManager(context, manager),
      );
    }
    return _buildWithManager(context, null);
  }

  Widget _buildWithManager(
    BuildContext context,
    OfflineDownloadManager? manager,
  ) {
    final scope = widget.serverScope;
    final task = (scope != null && manager != null)
        ? manager.getTask(scope, widget.track.id)
        : null;

    if (task?.status != _lastTaskStatus) {
      if (task?.status == DownloadTaskStatus.completed) {
        _triggerLookup();
      }
      _lastTaskStatus = task?.status;
    }

    return FutureBuilder<OfflineCacheEntry?>(
      future: _lookupFuture,
      builder: (context, snapshot) {
        final hasVerifiedCache = snapshot.data != null;
        final uiState = TrackOfflineActionState.resolve(
          task: task,
          hasVerifiedCache: hasVerifiedCache,
        );

        return _buildActionTiles(context, manager, scope, uiState);
      },
    );
  }

  Widget _buildActionTiles(
    BuildContext context,
    OfflineDownloadManager? manager,
    String? scope,
    TrackOfflineActionState uiState,
  ) {
    final theme = Provider.of<ThemeController?>(context)?.active;
    final accent = theme?.accent ?? Theme.of(context).colorScheme.primary;
    final textPrimary =
        theme?.textPrimary ?? Theme.of(context).colorScheme.onSurface;
    final textSecondary = theme?.textSecondary ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    final textMuted = theme?.textMuted ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);

    switch (uiState.status) {
      case TrackOfflineUiState.notDownloaded:
        return ListTile(
          leading: Icon(Icons.download_rounded, color: textSecondary),
          title: Text(
            'Descargar sin conexión',
            style: TextStyle(color: textPrimary, fontSize: 14),
          ),
          onTap: () => _handleQueue(manager, scope, widget.track),
        );

      case TrackOfflineUiState.queued:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: false,
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textMuted,
                ),
              ),
              title: Text(
                'En cola de descarga',
                style: TextStyle(color: textMuted, fontSize: 14),
              ),
            ),
            ListTile(
              leading: Icon(Icons.pause_circle_outline_rounded,
                  color: textSecondary),
              title: Text(
                'Pausar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handlePause(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.downloading:
        final progress = uiState.progress;
        final progressPercent =
            progress != null ? (progress * 100).toInt() : null;
        final titleText = progressPercent != null
            ? 'Descargando ($progressPercent%)'
            : 'Descargando...';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: false,
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
              title: Text(
                titleText,
                style: TextStyle(color: textMuted, fontSize: 14),
              ),
            ),
            ListTile(
              leading: Icon(Icons.pause_circle_outline_rounded,
                  color: textSecondary),
              title: Text(
                'Pausar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handlePause(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.paused:
        final progress = uiState.progress;
        final progressPercent =
            progress != null ? (progress * 100).toInt() : null;
        final subtitleText = progressPercent != null
            ? 'Pausada ($progressPercent%)'
            : 'Descarga pausada';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.play_circle_outline_rounded, color: accent),
              title: Text(
                'Reanudar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              subtitle: Text(
                subtitleText,
                style: TextStyle(color: textMuted, fontSize: 11),
              ),
              onTap: () => _handleResume(manager, scope, widget.track),
            ),
            ListTile(
              leading: Icon(Icons.cancel_outlined, color: textSecondary),
              title: Text(
                'Cancelar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handleCancel(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.failed:
        final failureMsg = uiState.failureMessage;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.refresh_rounded, color: accent),
              title: Text(
                'Reintentar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              subtitle: failureMsg != null && failureMsg.isNotEmpty
                  ? Text(
                      failureMsg,
                      style: TextStyle(color: textMuted, fontSize: 11),
                    )
                  : null,
              onTap: () => _handleRetry(manager, scope, widget.track),
            ),
            ListTile(
              leading: Icon(Icons.cancel_outlined, color: textSecondary),
              title: Text(
                'Cancelar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handleCancel(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.availableOffline:
        return ListTile(
          enabled: false,
          leading: Icon(Icons.check_circle_rounded, color: accent),
          title: Text(
            'Disponible sin conexión',
            style: TextStyle(color: textMuted, fontSize: 14),
          ),
          subtitle: Text(
            'Guardada en este dispositivo',
            style: TextStyle(color: textMuted, fontSize: 11),
          ),
          onTap: null,
        );
    }
  }
}
