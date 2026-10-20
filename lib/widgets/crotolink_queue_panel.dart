import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/crotolink_models.dart';
import '../services/crotolink_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';
import '../utils/app_colors.dart';
import '../services/listening_stats_service.dart';

/// Panel / Modal de Cola Compartida para sesiones CrotoLink y reproducción general.
class CrotoLinkQueuePanel extends StatefulWidget {
  const CrotoLinkQueuePanel({super.key});

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
        child: CrotoLinkQueuePanel(),
      ),
    );
  }

  @override
  State<CrotoLinkQueuePanel> createState() => _CrotoLinkQueuePanelState();
}

class _CrotoLinkQueuePanelState extends State<CrotoLinkQueuePanel> {
  int _selectedTab = 0; // 0: Cola, 1: Historial reciente

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final crotoLink = context.watch<CrotoLinkController>();
    final currentTrack = crotoLink.isGuest
        ? crotoLink.session?.currentTrack ?? player.currentTrack
        : player.currentTrack;

    // Si estamos en CrotoLink, usamos crotoLink.crotoLinkQueue, sino usamos la cola de player.orderedQueue
    final inCrotoLink = crotoLink.inCrotoLink;
    final canManageCrotoLinkQueue = crotoLink.isHost ||
        (crotoLink.localParticipant?.canManageQueue ?? false);
    final List<dynamic> queueItems = inCrotoLink
        ? crotoLink.crotoLinkQueue
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
                  color: inCrotoLink
                      ? context.accent.withValues(alpha: 0.15)
                      : context.accent2.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  inCrotoLink
                      ? Icons.speaker_group_rounded
                      : Icons.queue_music_rounded,
                  color: inCrotoLink ? context.accent : context.accent2,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inCrotoLink
                          ? 'Cola Colaborativa CrotoLink'
                          : 'Cola de Reproducción',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (inCrotoLink)
                      Text(
                        '${crotoLink.participants.length} participante${crotoLink.participants.length == 1 ? "" : "s"} agregando música',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (inCrotoLink && crotoLink.isHost)
                PopupMenuButton<Object>(
                  tooltip: 'Modo de cola',
                  icon: Icon(Icons.tune_rounded,
                      color: context.textMuted, size: 20),
                  onSelected: (v) {
                    if (v is CrotoLinkQueueMode) {
                      crotoLink.setQueueMode(v,
                          requireApproval: crotoLink.requireApproval);
                    } else {
                      crotoLink.setQueueMode(
                        crotoLink.queueMode == CrotoLinkQueueMode.approval
                            ? CrotoLinkQueueMode.free
                            : crotoLink.queueMode,
                        requireApproval: !crotoLink.approvalActive,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    for (final m in [
                      CrotoLinkQueueMode.free,
                      CrotoLinkQueueMode.fairTurns,
                      CrotoLinkQueueMode.voting,
                    ])
                      CheckedPopupMenuItem<Object>(
                        value: m,
                        checked: crotoLink.queueMode == m ||
                            (m == CrotoLinkQueueMode.free &&
                                crotoLink.queueMode ==
                                    CrotoLinkQueueMode.approval),
                        child: Text(m.label),
                      ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem<Object>(
                      value: 'approval',
                      checked: crotoLink.approvalActive,
                      child: const Text('Aprobar canciones de invitados'),
                    ),
                  ],
                ),
              if (!inCrotoLink && queueItems.isNotEmpty)
                TextButton(
                  onPressed: () {
                    final removed = player.removeDuplicatesFromQueue();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(removed > 0
                            ? '$removed canción(es) duplicada(s) eliminada(s) de la cola.'
                            : 'No hay canciones duplicadas en la cola.'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Text('Sin duplicados',
                      style: TextStyle(color: context.textMuted, fontSize: 12)),
                ),
              if (queueItems.isNotEmpty &&
                  (!inCrotoLink || canManageCrotoLinkQueue))
                TextButton(
                  onPressed: () {
                    if (inCrotoLink) {
                      // El Host puede limpiar los elementos
                      for (final item in List.of(crotoLink.crotoLinkQueue)) {
                        crotoLink.removeTrackFromCrotoLink(item.id);
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
          const SizedBox(height: 12),

          Row(
            children: [
              ChoiceChip(
                label: Text('Cola (${queueItems.length})'),
                selected: _selectedTab == 0,
                onSelected: (val) {
                  if (val) setState(() => _selectedTab = 0);
                },
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Historial reciente'),
                selected: _selectedTab == 1,
                onSelected: (val) {
                  if (val) setState(() => _selectedTab = 1);
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_selectedTab == 1)
            Expanded(child: _buildHistoryTab(context, player))
          else ...[

          if (inCrotoLink && crotoLink.lastError != null) ...[
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
                      crotoLink.lastError!,
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
                  color: inCrotoLink
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
                        if (inCrotoLink &&
                            crotoLink.currentTrackAddedBy != null) ...[
                          const SizedBox(height: 3),
                          _buildAddedByBadge(crotoLink.currentTrackAddedBy!),
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

          if (inCrotoLink) _CrotoLinkRequestsTray(crotoLink: crotoLink),
          if (inCrotoLink && crotoLink.unavailableNotice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(crotoLink.unavailableNotice!,
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
                : inCrotoLink
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: queueItems.length,
                        onReorderItem: canManageCrotoLinkQueue
                            ? (oldIndex, newIndex) {
                                final adjustedNew = newIndex > oldIndex
                                    ? newIndex - 1
                                    : newIndex;
                                crotoLink.reorderCrotoLinkQueue(
                                    oldIndex, adjustedNew);
                              }
                            : (_, __) {},
                        itemBuilder: (ctx, i) {
                          final item = queueItems[i] as CrotoLinkQueueItem;
                          final canRemove = canManageCrotoLinkQueue;
                          final isDuplicate = queueItems
                                  .where((qi) =>
                                      (qi is CrotoLinkQueueItem
                                          ? qi.track.id
                                          : (qi as Track).id) ==
                                      item.track.id)
                                  .length >
                              1;

                          final unavailable =
                              crotoLink.isUnavailableForMe(item.track.id);
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
                                  if (canManageCrotoLinkQueue)
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
                                  if (crotoLink.queueMode ==
                                      CrotoLinkQueueMode.voting)
                                    _VoteControls(
                                        crotoLink: crotoLink, item: item),
                                  if (crotoLink.isHost)
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
                                      onPressed: () => crotoLink.pinQueueItem(
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
                                      onPressed: () => crotoLink
                                          .removeTrackFromCrotoLink(item.id,
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
        ],
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context, PlayerController player) {
    final stats = context.watch<ListeningStatsService>();
    final historyEvents = stats.getHistory(limit: 60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'REPRODUCIDAS RECIENTEMENTE',
              style: TextStyle(
                color: context.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            if (historyEvents.isNotEmpty)
              TextButton(
                onPressed: () => stats.clearHistory(),
                child: Text(
                  'Borrar historial',
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: historyEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded,
                          color: context.textPrimary.withValues(alpha: 0.15),
                          size: 48),
                      const SizedBox(height: 10),
                      Text(
                        'Sin reproducciones recientes',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Las canciones que escuches aparecerán aquí',
                        style: TextStyle(
                            color: context.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: historyEvents.length,
                  itemBuilder: (context, i) {
                    final item = historyEvents[i];
                    final timeAgo = _formatTimeAgo(item.timestamp);
                    final track = Track(
                      id: item.trackId,
                      title: item.title,
                      artist: item.artist,
                      album: item.album,
                      duration: item.durationSeconds.toString(),
                      genre: item.genre,
                    );

                    return Container(
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
                          CoverArt(
                            url: null,
                            artist: item.artist,
                            album: item.album,
                            title: item.title,
                            width: 40,
                            height: 40,
                            borderRadius: 8,
                            fallbackIcon: Icons.music_note,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${item.artist} • $timeAgo',
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
                            tooltip: 'Añadir a la cola',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.add_to_photos_rounded,
                                color: context.textMuted, size: 18),
                            onPressed: () {
                              player.addToQueue(track);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Añadida a la cola: ${item.title}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: 'Reproducir ahora',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.play_arrow_rounded,
                                color: context.accent, size: 22),
                            onPressed: () => player.playQueue([track]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildAddedByBadge(CrotoLinkParticipant participant) {
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
  final CrotoLinkController crotoLink;
  final CrotoLinkQueueItem item;

  const _VoteControls({required this.crotoLink, required this.item});

  @override
  Widget build(BuildContext context) {
    final mine = crotoLink.myVoteFor(item.id);
    Widget arrow(IconData icon, int value) => InkWell(
          onTap: () => crotoLink.voteOnItem(item.id, mine == value ? 0 : value),
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
class _CrotoLinkRequestsTray extends StatelessWidget {
  final CrotoLinkController crotoLink;

  const _CrotoLinkRequestsTray({required this.crotoLink});

  @override
  Widget build(BuildContext context) {
    final requests = crotoLink.isHost
        ? crotoLink.pendingRequests
        : crotoLink.myPendingRequests;
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
                  crotoLink.isHost
                      ? 'SOLICITUDES PENDIENTES (${requests.length})'
                      : 'PENDIENTE DE APROBACIÓN',
                  style: TextStyle(
                      color: context.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1),
                ),
              ),
              if (crotoLink.isHost && requests.length > 1)
                TextButton(
                  onPressed: crotoLink.approveAllRequests,
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
                      crotoLink.isHost
                          ? '${r.track.title} · ${r.track.artist} — ${r.requestedByName}'
                          : '${r.track.title} · ${r.track.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.textPrimary, fontSize: 12),
                    ),
                  ),
                  if (crotoLink.isHost) ...[
                    IconButton(
                      tooltip: 'Aceptar',
                      icon: Icon(Icons.check_rounded,
                          color: context.accent, size: 20),
                      onPressed: () => crotoLink.approveRequest(r.id),
                    ),
                    IconButton(
                      tooltip: 'Rechazar',
                      icon: Icon(Icons.close_rounded,
                          color: context.textMuted, size: 20),
                      onPressed: () => crotoLink.rejectRequest(r.id),
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
