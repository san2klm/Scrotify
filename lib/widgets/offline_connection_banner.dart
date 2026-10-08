import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Estado de la conexión y acceso a la reconexión del servidor.
class OfflineConnectionBanner extends StatefulWidget {
  const OfflineConnectionBanner({super.key});
  @override
  State<OfflineConnectionBanner> createState() =>
      _OfflineConnectionBannerState();
}

class _OfflineConnectionBannerState extends State<OfflineConnectionBanner> {
  bool _connecting = false;

  Future<void> _reconnect(NavidromeService nav) async {
    setState(() => _connecting = true);
    try {
      await nav.reconnect();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'El servidor sigue sin estar disponible. Puedes escuchar tus descargas.')));
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    if (!nav.offlineMode) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nav.offlineMode)
              Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Sin conexión · Música del dispositivo',
                        style: TextStyle(color: context.textSecondary)),
                    TextButton.icon(
                        onPressed: _connecting ? null : () => _reconnect(nav),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_connecting ? 'Conectando…' : 'Reconectar'))
                  ]),
          ],
        ));
  }
}
