import 'package:flutter/material.dart';

import '../services/duplicate_detector.dart';
import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';
import 'cover_art.dart';

/// Diálogo interactivo que muestra las canciones duplicadas encontradas
/// en una playlist y permite eliminarlas de forma segura.
class DuplicateTracksDialog extends StatefulWidget {
  final String playlistName;
  final List<Track> allTracks;
  final Future<void> Function(List<int> indicesToRemove) onRemoveDuplicates;

  const DuplicateTracksDialog({
    super.key,
    required this.playlistName,
    required this.allTracks,
    required this.onRemoveDuplicates,
  });

  static Future<void> show(
    BuildContext context, {
    required String playlistName,
    required List<Track> allTracks,
    required Future<void> Function(List<int> indicesToRemove) onRemoveDuplicates,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DuplicateTracksDialog(
        playlistName: playlistName,
        allTracks: allTracks,
        onRemoveDuplicates: onRemoveDuplicates,
      ),
    );
  }

  @override
  State<DuplicateTracksDialog> createState() => _DuplicateTracksDialogState();
}

class _DuplicateTracksDialogState extends State<DuplicateTracksDialog> {
  bool _matchMetadata = true;
  late List<DuplicateGroup> _groups;
  final Set<int> _selectedIndicesToRemove = <int>{};
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recomputeDuplicates();
  }

  void _recomputeDuplicates() {
    _groups = DuplicateDetector.findDuplicates(
      widget.allTracks,
      matchMetadata: _matchMetadata,
    );
    _selectedIndicesToRemove.clear();
    for (final g in _groups) {
      _selectedIndicesToRemove.addAll(g.indicesToRemove);
    }
  }

  Future<void> _handleConfirm() async {
    if (_selectedIndicesToRemove.isEmpty) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      // Ordenar de mayor a menor para eliminar sin desfasar índices
      final sortedIndices = _selectedIndicesToRemove.toList()
        ..sort((a, b) => b.compareTo(a));
      await widget.onRemoveDuplicates(sortedIndices);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${sortedIndices.length} canción(es) duplicada(s) eliminada(s).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processing = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selectedIndicesToRemove.length;

    return AlertDialog(
      backgroundColor: context.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.themeBorder),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.copy_all_rounded, color: context.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Canciones duplicadas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.playlistName,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textMuted,
                    fontWeight: FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Switch de modo de detección
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: context.bgElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: context.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _matchMetadata
                          ? 'Detección inteligente (título y artista similares)'
                          : 'Detección exacta (mismo identificador de pista)',
                      style: TextStyle(fontSize: 12, color: context.textPrimary),
                    ),
                  ),
                  Switch(
                    value: _matchMetadata,
                    onChanged: _processing
                        ? null
                        : (val) {
                            setState(() {
                              _matchMetadata = val;
                              _recomputeDuplicates();
                            });
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.danger, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Lista de duplicados o mensaje vacío
            Expanded(
              child: _groups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 48, color: context.accent),
                          const SizedBox(height: 12),
                          Text(
                            '¡No se encontraron canciones duplicadas!',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Todas las canciones en esta lista son únicas.',
                            style: TextStyle(
                              color: context.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _groups.length,
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        return _buildGroupCard(group);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (_groups.isNotEmpty)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: context.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: (_processing || count == 0) ? null : _handleConfirm,
            icon: _processing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_sweep_rounded, size: 18),
            label: Text('Eliminar $count duplicada${count == 1 ? "" : "s"}'),
          ),
      ],
    );
  }

  Widget _buildGroupCard(DuplicateGroup group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.themeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${group.primaryTrack.title} — ${group.primaryTrack.artist}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${group.tracks.length} copias',
                  style: TextStyle(
                    color: context.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Pista original (Conservar)
          _buildTrackRow(
            track: group.primaryTrack,
            badgeLabel: 'Conservar',
            badgeColor: Colors.green,
            isOriginal: true,
            isSelected: false,
            onChanged: null,
          ),

          const Divider(height: 12),

          // Pistas duplicadas (Eliminar)
          for (var i = 1; i < group.tracks.length; i++) ...[
            _buildTrackRow(
              track: group.tracks[i],
              badgeLabel: 'Duplicado',
              badgeColor: context.danger,
              isOriginal: false,
              isSelected: _selectedIndicesToRemove.contains(group.indices[i]),
              onChanged: _processing
                  ? null
                  : (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedIndicesToRemove.add(group.indices[i]);
                        } else {
                          _selectedIndicesToRemove.remove(group.indices[i]);
                        }
                      });
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackRow({
    required Track track,
    required String badgeLabel,
    required Color badgeColor,
    required bool isOriginal,
    required bool isSelected,
    required ValueChanged<bool?>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (!isOriginal)
            Checkbox(
              value: isSelected,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          else
            const SizedBox(
              width: 40,
              child: Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 18),
            ),
          CoverArt(
            url: track.albumArtUrl,
            width: 32,
            height: 32,
            borderRadius: 6,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${track.album} • ${_formatDuration(track.duration)}',
                  style: TextStyle(fontSize: 10, color: context.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                color: badgeColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(String durationStr) {
    final sec = int.tryParse(durationStr) ?? 0;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
