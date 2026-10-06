import 'package:flutter/material.dart';

import '../services/jam_controller.dart';
import '../services/jam_social.dart';
import '../utils/app_colors.dart';

/// Barra de reacciones efímeras + acceso al chat ligero de la Jam.
class JamSocialBar extends StatelessWidget {
  final JamController jam;

  const JamSocialBar({super.key, required this.jam});

  @override
  Widget build(BuildContext context) {
    if (!jam.reactionsAvailable && !jam.chatSupported) {
      return const SizedBox.shrink();
    }
    final active = jam.activeReactions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 8,
              children: [
                for (final r in active.reversed.take(6))
                  Text('${r.emoji} ${r.from}',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        Row(
          children: [
            if (jam.reactionsAvailable)
              Expanded(
                child: Wrap(
                  spacing: 2,
                  children: [
                    for (final e in kJamReactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => jam.sendReaction(e),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
              )
            else
              const Spacer(),
            if (jam.isHost && jam.chatSupported)
              IconButton(
                tooltip: jam.chatRoomEnabled
                    ? 'Desactivar el chat de esta sala'
                    : 'Activar el chat de esta sala',
                icon: Icon(
                    jam.chatRoomEnabled
                        ? Icons.speaker_notes_rounded
                        : Icons.speaker_notes_off_rounded,
                    size: 18),
                onPressed: () => jam.setChatEnabled(!jam.chatRoomEnabled),
              ),
            if (jam.chatAvailable)
              TextButton.icon(
                onPressed: () => JamChatDialog.show(context, jam),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Chat'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Chat sin historial persistente: solo los últimos mensajes de esta sesión.
class JamChatDialog extends StatefulWidget {
  final JamController jam;

  const JamChatDialog({super.key, required this.jam});

  static Future<void> show(BuildContext context, JamController jam) =>
      showDialog<void>(
        context: context,
        builder: (_) => JamChatDialog(jam: jam),
      );

  @override
  State<JamChatDialog> createState() => _JamChatDialogState();
}

class _JamChatDialogState extends State<JamChatDialog> {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.jam.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.jam.removeListener(_refresh);
    _input.dispose();
    super.dispose();
  }

  void _send() {
    widget.jam.sendChat(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.jam.chatMessages;
    return AlertDialog(
      backgroundColor: context.bgApp,
      title: Row(
        children: [
          Expanded(
              child: Text('Chat de la Jam',
                  style: TextStyle(color: context.textPrimary))),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 320,
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text('Sin mensajes. No se guarda historial.',
                          style: TextStyle(color: context.textMuted)))
                  : ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[messages.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '${m.mine ? 'Tú' : m.from}: ',
                                style: TextStyle(
                                    color: context.accent,
                                    fontWeight: FontWeight.bold)),
                            TextSpan(
                                text: m.text,
                                style: TextStyle(color: context.textPrimary)),
                          ])),
                        );
                      },
                    ),
            ),
            TextField(
              controller: _input,
              maxLength: kJamChatMaxLength,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _send,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
