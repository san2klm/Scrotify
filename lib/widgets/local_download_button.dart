import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/local_music_service.dart';
import '../services/navidrome_service.dart';
import '../services/offline_download_manager.dart';

/// Acción común de descarga para canciones, favoritos y playlists.
class LocalDownloadButton extends StatefulWidget {
  const LocalDownloadButton({super.key, required this.tracks, this.collection, this.compact = false});
  final List<Track> tracks;
  final String? collection;
  final bool compact;

  @override
  State<LocalDownloadButton> createState() => _LocalDownloadButtonState();
}

class _LocalDownloadButtonState extends State<LocalDownloadButton> {
  bool _adding = false;

  Future<void> _download(LocalMusicService music, OfflineDownloadManager manager,
      String scope) async {
    setState(() => _adding = true);
    try {
      for (final track in widget.tracks) {
        await music.download(manager, track, scope, collection: widget.collection);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Descargas añadidas. Se omiten las canciones que ya tienes.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo descargar. Comprueba la conexión y los permisos de la carpeta.')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<LocalMusicService?>();
    final manager = context.watch<OfflineDownloadManager?>();
    final nav = context.watch<NavidromeService>();
    if (music == null || manager == null) return const SizedBox.shrink();
    final scope = nav.serverScope;
    final total = widget.tracks.length;
    final downloaded = scope == null ? 0 : widget.tracks.where((track) =>
        music.localPath(scope, track.id) != null).length;
    final complete = total > 0 && downloaded == total;
    final tasks = scope == null ? <DownloadTask>[] : widget.tracks
        .map((track) => manager.getTask(scope, track.id)).whereType<DownloadTask>().toList();
    final busy = _adding || tasks.any((task) =>
        task.status == DownloadTaskStatus.downloading || task.status == DownloadTaskStatus.queued);
    final paused = tasks.where((task) => task.status == DownloadTaskStatus.paused).toList();
    final failed = tasks.where((task) => task.status == DownloadTaskStatus.failed).toList();
    final label = complete ? (total == 1 ? 'Descargada' : 'Descargadas ($downloaded/$total)')
        : busy ? 'Descargando ($downloaded/$total)'
        : paused.isNotEmpty ? 'Reanudar descarga'
        : failed.isNotEmpty ? 'Reintentar descarga'
        : downloaded > 0 ? 'Descargar restantes ($downloaded/$total)' : 'Descargar';
    final icon = Icon(complete ? Icons.download_done_rounded
        : busy ? Icons.downloading_rounded : Icons.download_rounded, size: 20);
    final enabled = nav.connected && scope != null && total > 0 && !complete && !busy;
    Future<void> action() async {
      if (scope == null) return;
      for (final task in paused) {
        await manager.resumeTask(scope, task.trackId);
      }
      for (final task in failed) {
        await manager.retryTask(scope, task.trackId);
      }
      await _download(music, manager, scope);
    }
    if (widget.compact) {
      return IconButton(tooltip: label, visualDensity: VisualDensity.compact,
          icon: icon, onPressed: enabled ? action : null);
    }
    return TextButton.icon(icon: icon, label: Text(label), onPressed: enabled ? action : null);
  }
}
