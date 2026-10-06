import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/jam_models.dart';
import '../services/jam_controller.dart';

/// Escucha enlaces de invitación (`scrotify://join?...` y `https://<relay>/j/<PIN>`)
/// y ofrece unirse a la Jam. Si la plataforma no soporta enlaces, no hace nada.
class JamDeepLinkListener extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const JamDeepLinkListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<JamDeepLinkListener> createState() => _JamDeepLinkListenerState();
}

class _JamDeepLinkListenerState extends State<JamDeepLinkListener> {
  StreamSubscription<Uri>? _sub;
  String? _lastHandled;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _onLink(initial);
      _sub = links.uriLinkStream.listen(_onLink, onError: (_) {});
    } catch (e) {
      debugPrint('JamDeepLinkListener: enlaces no soportados ($e)');
    }
  }

  void _onLink(Uri uri) {
    final raw = uri.toString();
    final invite = JamInviteLink.parse(raw);
    if (invite == null || raw == _lastHandled) return;
    _lastHandled = raw;
    // Esperar a que haya Navigator (el enlace inicial llega antes del primer frame).
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask(invite, raw));
  }

  Future<void> _ask(JamInviteLink invite, String raw) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final jam = ctx.read<JamController>();
    final password = TextEditingController();
    final accepted = await showDialog<bool>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unirte a la Jam ${invite.code}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(invite.server == null
                ? 'Se usará el servidor Jam configurado en Ajustes.'
                : 'Servidor: ${invite.server}'),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Contraseña de la sala (si tiene)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unirme'),
          ),
        ],
      ),
    );
    final pass = password.text;
    password.dispose();
    _lastHandled = null;
    if (accepted != true) return;
    final ok = await jam.joinByLink(raw, password: pass.isEmpty ? null : pass);
    final after = widget.navigatorKey.currentContext;
    if (!ok && after != null && after.mounted) {
      ScaffoldMessenger.maybeOf(after)?.showSnackBar(SnackBar(
        content: Text(jam.lastJoinError ?? 'No se pudo unir a la Jam.'),
      ));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
