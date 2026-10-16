import 'package:flutter/material.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';
import 'cover_art.dart';
import 'interactive_artist_text.dart';
import 'track_context_menu.dart';
import 'local_download_button.dart';

/// Listado existente de Explorar, compartido por ambos diseños responsive.
class ExploreTracksView extends StatelessWidget {
  const ExploreTracksView({
    super.key,
    required this.tracks,
    required this.pageSize,
    required this.page,
    required this.onPageSizeChanged,
    required this.onPageChanged,
    required this.onPlay,
  });

  final List<Track> tracks;
  final int pageSize;
  final int page;
  final ValueChanged<int> onPageSizeChanged;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPlay;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return Center(
        child: Text(
          'No hay canciones en tu biblioteca',
          style: TextStyle(color: context.textMuted),
        ),
      );
    }

    final totalPages = (tracks.length / pageSize).ceil();
    final currentPage = page.clamp(0, totalPages - 1).toInt();
    final firstTrack = currentPage * pageSize;
    final pageTracks = tracks.skip(firstTrack).take(pageSize).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: pageTracks.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explorar',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        if (index == pageTracks.length + 1) {
          return _explorePagination(context, totalPages, currentPage);
        }

        final trackIndex = firstTrack + index - 1;
        final track = pageTracks[index - 1];
        return InkWell(
          onTap: () => onPlay(trackIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CoverArt(
                  url: track.albumArtUrl,
                  artist: track.artist,
                  album: track.album,
                  title: track.title,
                  width: 40,
                  height: 40,
                  borderRadius: 4,
                  fallbackIcon: Icons.music_note,
                  fallbackIconSize: 20,
                  fallbackColor: context.bgCard,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InteractiveArtistText(
                            artistString: track.artist,
                            fontSize: 11.5,
                          ),
                          Text(
                            ' · ${track.album}',
                            style: TextStyle(
                                color: context.textMuted, fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                LocalDownloadButton(tracks: [track], compact: true),
                IconButton(
                  tooltip: 'Más opciones',
                  icon: Icon(Icons.more_horiz, color: context.textMuted),
                  onPressed: () => TrackContextMenu.show(context, track),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(track.duration),
                  style: TextStyle(color: context.textMuted, fontSize: 11.5),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _explorePagination(
      BuildContext context, int totalPages, int currentPage) {
    final pages = <int>{0, totalPages - 1, currentPage};
    if (totalPages <= 5) {
      pages.addAll(List.generate(totalPages, (index) => index));
    } else {
      for (var page = currentPage - 1; page <= currentPage + 1; page++) {
        if (page >= 0 && page < totalPages) pages.add(page);
      }
      if (currentPage <= 2) pages.addAll([1, 2, 3]);
      if (currentPage >= totalPages - 3) {
        pages.addAll([totalPages - 4, totalPages - 3, totalPages - 2]);
      }
    }
    final sortedPages = pages.toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 28),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.end,
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                border: Border.all(color: context.inputBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: pageSize,
                  isDense: true,
                  dropdownColor: context.bgCard,
                  icon: Icon(Icons.keyboard_arrow_down_rounded,
                      color: context.textMuted),
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [10, 25, 50, 100]
                      .map(
                        (pageSize) => DropdownMenuItem(
                          value: pageSize,
                          child: Text('$pageSize'),
                        ),
                      )
                      .toList(),
                  onChanged: (pageSize) {
                    if (pageSize == null) return;
                    onPageSizeChanged(pageSize);
                  },
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: currentPage > 0
                      ? () => onPageChanged(currentPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                for (var index = 0; index < sortedPages.length; index++) ...[
                  if (index > 0 &&
                      sortedPages[index] != sortedPages[index - 1] + 1)
                    Text('…', style: TextStyle(color: context.textMuted)),
                  ChoiceChip(
                    label: Text('${sortedPages[index] + 1}'),
                    selected: sortedPages[index] == currentPage,
                    selectedColor: context.accent.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: sortedPages[index] == currentPage
                          ? context.accent
                          : context.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => onPageChanged(sortedPages[index]),
                  ),
                ],
                IconButton(
                  tooltip: 'Página siguiente',
                  onPressed: currentPage < totalPages - 1
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(String raw) {
    final s = int.tryParse(raw) ?? 0;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}
