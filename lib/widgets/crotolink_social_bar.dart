import 'package:flutter/material.dart';

import '../services/crotolink_controller.dart';
import '../services/crotolink_social.dart';
import '../utils/app_colors.dart';

/// Barra de reacciones efímeras + acceso al chat ligero de la CrotoLink.
class CrotoLinkSocialBar extends StatelessWidget {
  final CrotoLinkController crotoLink;

  const CrotoLinkSocialBar({super.key, required this.crotoLink});

  @override
  Widget build(BuildContext context) {
    if (!crotoLink.reactionsAvailable && !crotoLink.chatSupported) {
      return const SizedBox.shrink();
    }
    final active = crotoLink.activeReactions;
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
            if (crotoLink.reactionsAvailable)
              Expanded(
                child: Wrap(
                  spacing: 2,
                  children: [
                    for (final e in kCrotoLinkReactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => crotoLink.sendReaction(e),
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
            if (crotoLink.isHost && crotoLink.chatSupported)
              IconButton(
                tooltip: crotoLink.chatRoomEnabled
                    ? 'Desactivar el chat de esta sala'
                    : 'Activar el chat de esta sala',
                icon: Icon(
                    crotoLink.chatRoomEnabled
                        ? Icons.speaker_notes_rounded
                        : Icons.speaker_notes_off_rounded,
                    size: 18),
                onPressed: () =>
                    crotoLink.setChatEnabled(!crotoLink.chatRoomEnabled),
              ),
            if (crotoLink.chatAvailable)
              TextButton.icon(
                onPressed: () => CrotoLinkChatDialog.show(context, crotoLink),
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
class CrotoLinkChatDialog extends StatefulWidget {
  final CrotoLinkController crotoLink;

  const CrotoLinkChatDialog({super.key, required this.crotoLink});

  static Future<void> show(
          BuildContext context, CrotoLinkController crotoLink) =>
      showDialog<void>(
        context: context,
        builder: (_) => CrotoLinkChatDialog(crotoLink: crotoLink),
      );

  @override
  State<CrotoLinkChatDialog> createState() => _CrotoLinkChatDialogState();
}

class _CrotoLinkChatDialogState extends State<CrotoLinkChatDialog> {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.crotoLink.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.crotoLink.removeListener(_refresh);
    _input.dispose();
    super.dispose();
  }

  void _send() {
    widget.crotoLink.sendChat(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.crotoLink.chatMessages;
    return AlertDialog(
      backgroundColor: context.bgApp,
      title: Row(
        children: [
          Expanded(
              child: Text('Chat del CrotoLink',
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
              maxLength: kCrotoLinkChatMaxLength,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje…',
                suffixIcon: IconButton(
                  tooltip: 'Enviar',
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
