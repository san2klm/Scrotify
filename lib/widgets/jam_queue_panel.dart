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
                  color: inJam ? context.accent : context.accent2,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inJam ? 'Cola Colaborativa CrotoLink' : 'Cola de Reproducción',
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
              if (inJam && jam.isHost)
                PopupMenuButton<Object>(
                  tooltip: 'Modo de cola',
                  icon: Icon(Icons.tune_rounded,
                      color: context.textMuted, size: 20),
                  onSelected: (v) {
                    if (v is JamQueueMode) {
                      jam.setQueueMode(v, requireApproval: jam.requireApproval);
                    } else {
                      jam.setQueueMode(
                        jam.queueMode == JamQueueMode.approval
                            ? JamQueueMode.free
                            : jam.queueMode,
                        requireApproval: !jam.approvalActive,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    for (final m in [
                      JamQueueMode.free,
                      JamQueueMode.fairTurns,
                      JamQueueMode.voting,
                    ])
                      CheckedPopupMenuItem<Object>(
                        value: m,
                        checked: jam.queueMode == m ||
                            (m == JamQueueMode.free &&
                                jam.queueMode == JamQueueMode.approval),
                        child: Text(m.label),
                      ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem<Object>(
                      value: 'approval',
                      checked: jam.approvalActive,
                      child: const Text('Aprobar canciones de invitados'),
                    ),
                  ],
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
                tooltip: 'Cerrar',
                icon: Icon(Icons.close_rounded,
                    color: context.textMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (inJam && jam.lastError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.danger.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: context.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      jam.lastError!,
                      style: TextStyle(color: context.danger, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

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

          if (inJam) _JamRequestsTray(jam: jam),
          if (inJam && jam.unavailableNotice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(jam.unavailableNotice!,
                  style: TextStyle(color: context.textMuted, fontSize: 11)),
            ),

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
                                final adjustedNew = newIndex > oldIndex
                                    ? newIndex - 1
                                    : newIndex;
                                jam.reorderJamQueue(oldIndex, adjustedNew);
                              }
                            : (_, __) {},
                        itemBuilder: (ctx, i) {
                          final item = queueItems[i] as JamQueueItem;
                          final canRemove = canManageJamQueue;
                          final isDuplicate = queueItems
                                  .where((qi) =>
                                      (qi is JamQueueItem
                                          ? qi.track.id
                                          : (qi as Track).id) ==
                                      item.track.id)
                                  .length >
                              1;

                          final unavailable =
                              jam.isUnavailableForMe(item.track.id);
                          return Opacity(
                            key: ValueKey(item.id),
                            opacity: unavailable ? 0.45 : 1,
                            child: Container(
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
                                        padding:
                                            const EdgeInsets.only(right: 10),
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
                                        if (unavailable)
                                          Text(
                                            'No disponible en tu biblioteca',
                                            style: TextStyle(
                                                color: context.textMuted,
                                                fontSize: 10.5,
                                                fontStyle: FontStyle.italic),
                                          ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.track.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: context.textMuted,
                                                    fontSize: 11),
                                              ),
                                            ),
                                            if (isDuplicate) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: context.accent2
                                                      .withValues(alpha: 0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: context.accent2
                                                        .withValues(alpha: 0.4),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Text(
                                                  'Repetida',
                                                  style: TextStyle(
                                                    color: context.accent2,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (item.addedBy != null) ...[
                                          const SizedBox(height: 3),
                                          _buildAddedByBadge(item.addedBy!),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (jam.queueMode == JamQueueMode.voting)
                                    _VoteControls(jam: jam, item: item),
                                  if (jam.isHost)
                                    IconButton(
                                      tooltip:
                                          item.pinned ? 'Desfijar' : 'Fijar',
                                      icon: Icon(
                                          item.pinned
                                              ? Icons.push_pin_rounded
                                              : Icons.push_pin_outlined,
                                          color: item.pinned
                                              ? context.accent
                                              : context.textMuted,
                                          size: 18),
                                      onPressed: () => jam.pinQueueItem(
                                          item.id, !item.pinned),
                                    )
                                  else if (item.pinned)
                                    Icon(Icons.push_pin_rounded,
                                        color: context.accent, size: 16),
                                  if (canRemove)
                                    IconButton(
                                      tooltip: 'Cerrar',
                                      icon: Icon(Icons.close_rounded,
                                          color: context.textMuted, size: 18),
                                      onPressed: () => jam.removeTrackFromJam(
                                          item.id,
                                          orderIndex: i),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: queueItems.length,
                        onReorderItem: (oldIndex, newIndex) {
                          final adjustedNew =
                              newIndex > oldIndex ? newIndex - 1 : newIndex;
                          final playerOffset = player.currentOrderPos >= 0
                              ? player.currentOrderPos + 1
                              : 0;
                          final realOld = playerOffset + oldIndex;
                          final realNew = playerOffset + adjustedNew;
                          player.reorderQueue(realOld, realNew);
                        },
                        itemBuilder: (ctx, i) {
                          final track = queueItems[i] as Track;
                          final isDuplicate = queueItems
                                  .where((qi) => (qi as Track).id == track.id)
                                  .length >
                              1;
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
                                    padding: const EdgeInsets.only(right: 10),
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
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: context.textMuted,
                                                  fontSize: 11),
                                            ),
                                          ),
                                          if (isDuplicate) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: context.accent2
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: context.accent2
                                                      .withValues(alpha: 0.4),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                'Repetida',
                                                style: TextStyle(
                                                  color: context.accent2,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar',
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

/// Botones ▲/▼ con contador (modo votación).
class _VoteControls extends StatelessWidget {
  final JamController jam;
  final JamQueueItem item;

  const _VoteControls({required this.jam, required this.item});

  @override
  Widget build(BuildContext context) {
    final mine = jam.myVoteFor(item.id);
    Widget arrow(IconData icon, int value) => InkWell(
          onTap: () => jam.voteOnItem(item.id, mine == value ? 0 : value),
          child: Icon(icon,
              size: 22,
              color: mine == value ? context.accent : context.textMuted),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.keyboard_arrow_up_rounded, 1),
        Text('${item.votes}',
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        arrow(Icons.keyboard_arrow_down_rounded, -1),
      ],
    );
  }
}

/// Bandeja de solicitudes: el host aprueba/rechaza; el invitado ve las suyas
/// como "pendientes".
class _JamRequestsTray extends StatelessWidget {
  final JamController jam;

  const _JamRequestsTray({required this.jam});

  @override
  Widget build(BuildContext context) {
    final requests = jam.isHost ? jam.pendingRequests : jam.myPendingRequests;
    if (requests.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.accent2.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  jam.isHost
                      ? 'SOLICITUDES PENDIENTES (${requests.length})'
                      : 'PENDIENTE DE APROBACIÓN',
                  style: TextStyle(
                      color: context.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1),
                ),
              ),
              if (jam.isHost && requests.length > 1)
                TextButton(
                  onPressed: jam.approveAllRequests,
                  child: const Text('Aceptar todas',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          for (final r in requests)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      jam.isHost
                          ? '${r.track.title} · ${r.track.artist} — ${r.requestedByName}'
                          : '${r.track.title} · ${r.track.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.textPrimary, fontSize: 12),
                    ),
                  ),
                  if (jam.isHost) ...[
                    IconButton(
                      tooltip: 'Aceptar',
                      icon: Icon(Icons.check_rounded,
                          color: context.accent, size: 20),
                      onPressed: () => jam.approveRequest(r.id),
                    ),
                    IconButton(
                      tooltip: 'Rechazar',
                      icon: Icon(Icons.close_rounded,
                          color: context.textMuted, size: 20),
                      onPressed: () => jam.rejectRequest(r.id),
                    ),
                  ] else
                    Text('pendiente',
                        style: TextStyle(
                            color: context.accent2,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
