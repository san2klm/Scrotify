import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/jam_models.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import 'cover_art.dart';

/// Panel / Modal de Cola Compartida para sesiones Jam y reproducción general.
class JamQueuePanel extends StatelessWidget {
  const JamQueuePanel({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C0C10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0xFF1E1E28), width: 1.2),
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
    final currentTrack = player.currentTrack;

    // Si estamos en Jam, usamos jam.jamQueue, sino usamos la cola de player.orderedQueue
    final inJam = jam.inJam;
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
                color: Colors.white24,
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
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFF7C3AED).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  inJam ? Icons.speaker_group_rounded : Icons.queue_music_rounded,
                  color: inJam ? const Color(0xFF10B981) : const Color(0xFFA855F7),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (inJam)
                      Text(
                        '${jam.participants.length} participante${jam.participants.length == 1 ? "" : "s"} agregando música',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (queueItems.isNotEmpty && (!inJam || jam.isHost))
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
                  child: const Text('Limpiar',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Canción en reproducción actual
          if (currentTrack != null) ...[
            const Text(
              'SONANDO AHORA',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF14141E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: inJam
                      ? const Color(0xFF10B981).withValues(alpha: 0.3)
                      : const Color(0xFF222232),
                ),
              ),
              child: Row(
                children: [
                  CoverArt(
                    url: currentTrack.albumArtUrl,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentTrack.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                        ),
                        if (inJam && jam.currentTrackAddedBy != null) ...[
                          const SizedBox(height: 3),
                          _buildAddedByBadge(jam.currentTrackAddedBy!),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.graphic_eq_rounded,
                      color: Color(0xFF10B981), size: 20),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Lista Siguiente en la Cola
          const Text(
            'A CONTINUACIÓN',
            style: TextStyle(
              color: Colors.white38,
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
                            color: Colors.white.withValues(alpha: 0.15), size: 48),
                        const SizedBox(height: 10),
                        const Text(
                          'La cola está vacía',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Añade canciones desde el buscador o tu biblioteca',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : inJam
                    ? ReorderableListView.builder(
                        itemCount: queueItems.length,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) newIndex -= 1;
                          jam.reorderJamQueue(oldIndex, newIndex);
                        },
                        itemBuilder: (ctx, i) {
                          final item = queueItems[i] as JamQueueItem;
                          final canRemove = jam.isHost ||
                              item.addedBy?.id == jam.localParticipant?.id;

                          return Container(
                            key: ValueKey(item.id),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF12121A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF1E1E28)),
                            ),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 10),
                                    child: Icon(Icons.drag_handle_rounded,
                                        color: Colors.white38, size: 20),
                                  ),
                                ),
                                CoverArt(
                                  url: item.track.albumArtUrl,
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
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        item.track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white54,
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
                                    icon: const Icon(Icons.close_rounded,
                                        color: Colors.white38, size: 18),
                                    onPressed: () =>
                                        jam.removeTrackFromJam(item.id, orderIndex: i),
                                  ),
                              ],
                            ),
                          );
                        },
                      )
                    : ReorderableListView.builder(
                        itemCount: queueItems.length,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) newIndex -= 1;
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
                              color: const Color(0xFF12121A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF1E1E28)),
                            ),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 10),
                                    child: Icon(Icons.drag_handle_rounded,
                                        color: Colors.white38, size: 20),
                                  ),
                                ),
                                CoverArt(
                                  url: track.albumArtUrl,
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
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      color: Colors.white38, size: 18),
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
