import 'package:flutter/material.dart';

import '../services/crotolink_controller.dart';
import '../utils/app_colors.dart';

/// Historial de la CrotoLink: lista, resumen, filtro por participante y "Guardar como
/// playlist". El invitado ve lo que sonó desde que entró y puede guardar solo
/// lo que añadió él.
class CrotoLinkHistoryDialog extends StatefulWidget {
  final CrotoLinkController crotoLink;

  const CrotoLinkHistoryDialog({super.key, required this.crotoLink});

  static Future<void> show(
          BuildContext context, CrotoLinkController crotoLink) =>
      showDialog<void>(
        context: context,
        builder: (_) => CrotoLinkHistoryDialog(crotoLink: crotoLink),
      );

  @override
  State<CrotoLinkHistoryDialog> createState() => _CrotoLinkHistoryDialogState();
}

class _CrotoLinkHistoryDialogState extends State<CrotoLinkHistoryDialog> {
  String? _participantId;
  bool _saving = false;
  String? _message;

  Future<void> _save({bool mine = false}) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final n = mine
          ? await widget.crotoLink.saveMyContributionsAsPlaylist()
          : await widget.crotoLink.saveHistoryAsPlaylist(
              participantId: _participantId,
            );
      if (!mounted) return;
      setState(() => _message = n == 0
          ? 'No hay pistas que guardar.'
          : 'Playlist creada con $n pistas.');
    } catch (e) {
      if (mounted) setState(() => _message = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.crotoLink.history;
    final summary = history.summary();
    final entries = _participantId == null
        ? history.entries
        : history.byParticipant(_participantId!);
    final contributors = <String, String>{
      for (final e in history.entries)
        if (e.addedBy != null) e.addedBy!.id: e.addedBy!.name,
    };
    final minutes = summary.totalDuration.inMinutes;

    return AlertDialog(
      backgroundColor: context.bgApp,
      title: Text('Historial del CrotoLink',
          style: TextStyle(color: context.textPrimary)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.trackCount} pistas · $minutes min'
              '${summary.topContributor != null ? ' · más aportó: ${summary.topContributor} (${summary.topContributorCount})' : ''}'
              '${summary.mostVoted != null ? '\nMás votada: ${summary.mostVoted!.title} (+${summary.mostVotes})' : ''}',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            if (contributors.length > 1)
              DropdownButton<String?>(
                value: _participantId,
                isExpanded: true,
                dropdownColor: context.bgElevated,
                hint: const Text('Todos los participantes'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Todos los participantes')),
                  for (final e in contributors.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _participantId = v),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: entries.isEmpty
                  ? Text('Aún no hay pistas en el historial.',
                      style: TextStyle(color: context.textMuted))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.textPrimary)),
                          subtitle: Text(
                              '${e.track.artist}${e.addedBy != null ? ' · ${e.addedBy!.name}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.textMuted)),
                        );
                      },
                    ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!,
                    style: TextStyle(color: context.textSecondary)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        if (widget.crotoLink.historyOwnerName != null)
          TextButton(
            onPressed: _saving || widget.crotoLink.myContributions.isEmpty
                ? null
                : () => _save(mine: true),
            child: const Text('Guardar mis aportaciones'),
          ),
        FilledButton.icon(
          onPressed: _saving || entries.isEmpty ? null : _save,
          icon: const Icon(Icons.playlist_add_rounded, size: 18),
          label: Text(_saving ? 'Guardando…' : 'Guardar como playlist'),
        ),
      ],
    );
  }
}
