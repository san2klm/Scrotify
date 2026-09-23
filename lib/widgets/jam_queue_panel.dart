import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/jam_models.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';
import '../utils/app_colors.dart';

/// Panel / Modal de Cola Compartida para sesiones Jam y reproducción general.
class JamQueuePanel extends StatelessWidget {
  const JamQueuePanel({super.key});

  static void show(BuildContext context) {
    final theme = context.read<ThemeController>().active;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
      ),
      builder: (ctx) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: JamQueuePanel(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final jam = context.watch<JamController>();
    final currentTrack = jam.isGuest
        ? jam.session?.currentTrack ?? player.currentTrack
        : player.currentTrack;

    // Si estamos en Jam, usamos jam.jamQueue, sino usamos la cola de player.orderedQueue
    final inJam = jam.inJam;
    final canManageJamQueue =
        jam.isHost || (jam.localParticipant?.canManageQueue ?? false);
    final List<dynamic> queueItems = inJam
        ? jam.jamQueue
        : [
            for (var i = player.currentOrderPos + 1;
                i < player.orderedQueue.length;
                i++)
              player.orderedQueue[i]
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.themeBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Título y controles
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: inJam
                      ? context.accent.withValues(alpha: 0.15)
                      : context.accent2.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  inJam
                      ? Icons.speaker_group_rounded
                      : Icons.queue_music_rounded,
                  color: inJam ? context.accent : context.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inJam ? 'Cola Colaborativa Jam' : 'Cola de Reproducción',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (inJam)
                      Text(
                        '${jam.participants.length} participante${jam.participants.length == 1 ? "" : "s"} agregando música',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (queueItems.isNotEmpty && (!inJam || canManageJamQueue))
                TextButton(
                  onPressed: () {
                    if (inJam) {
                      // El Host puede limpiar los elementos
                      for (final item in List.of(jam.jamQueue)) {
                        jam.removeTrackFromJam(item.id);
                      }
                    } else {
                      player.clearQueue();
                    }
                  },
                  child: Text('Limpiar',
                      style: TextStyle(color: context.textMuted, fontSize: 12)),
                ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: context.textMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Canción en reproducción actual
          if (currentTrack != null) ...[
            Text(
              'SONANDO AHORA',
              style: TextStyle(
                color: context.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.bgElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: inJam
                      ? context.accent.withValues(alpha: 0.3)
                      : context.bgElevated,
                ),
              ),
              child: Row(
                children: [
                  CoverArt(
                    url: currentTrack.albumArtUrl,
                    artist: currentTrack.artist,
                    album: currentTrack.album,
                    title: currentTrack.title,
                    width: 44,
                    height: 44,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentTrack.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentTrack.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 11.5),
                        ),
                        if (inJam && jam.currentTrackAddedBy != null) ...[
                          const SizedBox(height: 3),
                          _buildAddedByBadge(jam.currentTrackAddedBy!),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.graphic_eq_rounded,
                      color: context.accent, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Lista Siguiente en la Cola
          Text(
            'A CONTINUACIÓN',
            style: TextStyle(
              color: context.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: queueItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue_music_rounded,
                            color: context.textPrimary.withValues(alpha: 0.15),
                            size: 48),
                        const SizedBox(height: 10),
                        Text(
                          'La cola está vacía',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Añade canciones desde el buscador o tu biblioteca',
                          style:
                              TextStyle(color: context.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : inJam
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: queueItems.length,
                        onReorderItem: canManageJamQueue
                            ? (oldIndex, newIndex) {
                                jam.reorderJamQueue(oldIndex, newIndex);
                              }
                            : (_, __) {},
                        itemBuilder: (ctx, i) {
                          final item = queueItems[i] as JamQueueItem;
                          final canRemove = canManageJamQueue;

                          return Container(
                            key: ValueKey(item.id),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: context.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.bgElevated),
                            ),
                            child: Row(
                              children: [
                                if (canManageJamQueue)
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Icon(Icons.drag_handle_rounded,
                                          color: context.textMuted, size: 20),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Icon(Icons.lock_outline_rounded,
                                        color: context.textMuted, size: 17),
                                  ),
                                CoverArt(
                                  url: item.track.albumArtUrl,
                                  artist: item.track.artist,
                                  album: item.track.album,
                                  title: item.track.title,
                                  width: 40,
                                  height: 40,
                                  borderRadius: 8,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        item.track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: context.textMuted,
                                            fontSize: 11),
                                      ),
                                      if (item.addedBy != null) ...[
                                        const SizedBox(height: 3),
                                        _buildAddedByBadge(item.addedBy!),
                                      ],
                                    ],
                                  ),
                                ),
                                if (canRemove)
                                  IconButton(
                                    icon: Icon(Icons.close_rounded,
                                        color: context.textMuted, size: 18),
                                    onPressed: () => jam.removeTrackFromJam(
                                        item.id,
                                        orderIndex: i),
                                  ),
                              ],
                            ),
                          );
                        },
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: queueItems.length,
                        onReorderItem: (oldIndex, newIndex) {
                          final realOld = player.currentOrderPos + 1 + oldIndex;
                          final realNew = player.currentOrderPos + 1 + newIndex;
                          player.reorderQueue(realOld, realNew);
                        },
                        itemBuilder: (ctx, i) {
                          final track = queueItems[i] as Track;
                          return Container(
                            key: ValueKey('${track.id}_$i'),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: context.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.bgElevated),
                            ),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 10),
                                    child: Icon(Icons.drag_handle_rounded,
                                        color: context.textMuted, size: 20),
                                  ),
                                ),
                                CoverArt(
                                  url: track.albumArtUrl,
                                  artist: track.artist,
                                  album: track.album,
                                  title: track.title,
                                  width: 40,
                                  height: 40,
                                  borderRadius: 8,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: context.textMuted,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close_rounded,
                                      color: context.textMuted, size: 18),
                                  onPressed: () {
                                    final realIdx =
                                        player.currentOrderPos + 1 + i;
                                    player.removeFromQueue(realIdx);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddedByBadge(JamParticipant participant) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: Color(participant.avatarColorValue).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 4,
            backgroundColor: Color(participant.avatarColorValue),
          ),
          const SizedBox(width: 4),
          Text(
            'Añadido por ${participant.name}',
            style: TextStyle(
              color: Color(participant.avatarColorValue),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
