import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/sync/sync_service.dart';
import '../utils/app_colors.dart';

/// Ajustes → Servidor Jam → Sincronización entre dispositivos.
///
/// Activa la sincronización cifrada de temas, ajustes y datos de la
/// biblioteca, o vincula este dispositivo con la clave de otro.
class SyncSettings extends StatelessWidget {
  const SyncSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final secondary = TextStyle(color: context.textSecondary, fontSize: 13);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Sincronizar entre dispositivos',
            style: TextStyle(color: context.textPrimary, fontSize: 14)),
        subtitle: Text(
            'Activada por defecto con tu cuenta: temas, ajustes, artistas '
            'seguidos, valoraciones y orden de favoritos, cifrados de extremo '
            'a extremo. La música descargada no se sincroniza.',
            style: secondary),
        activeTrackColor: context.accent,
        activeThumbColor: context.textPrimary,
        value: sync.enabled,
        onChanged: (on) =>
            on ? _enable(context, sync) : _disable(context, sync),
      ),
      if (sync.enabled) ...[
        const SizedBox(height: 4),
        Text(_status(sync), style: secondary),
        if (sync.error != null) ...[
          const SizedBox(height: 4),
          Text(sync.error!,
              style: TextStyle(color: context.warning, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: sync.syncing ? null : sync.syncNow,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Sincronizar ahora'),
          ),
          OutlinedButton.icon(
            onPressed: () => _showKey(context, sync.keyText ?? ''),
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('Ver clave'),
          ),
          OutlinedButton.icon(
            onPressed: sync.syncing ? null : () => _randomKey(context, sync),
            icon: const Icon(Icons.shield_outlined, size: 18),
            label: const Text('Usar clave aleatoria'),
          ),
        ]),
      ] else ...[
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _link(context, sync),
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Ya tengo una clave de otro dispositivo'),
        ),
      ],
    ]);
  }

  static String _status(SyncService sync) {
    if (sync.syncing) return 'Sincronizando…';
    final last = sync.lastSync;
    if (last == null) return 'Aún sin sincronizar.';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Última sincronización: ${last.year}-${two(last.month)}-${two(last.day)} '
        '${two(last.hour)}:${two(last.minute)}';
  }

  Future<void> _enable(BuildContext context, SyncService sync) async {
    final key = await sync.enableNew();
    if (context.mounted) await _showKey(context, key, firstTime: true);
  }

  /// Alternativa más segura a la clave de la cuenta: una clave aleatoria que
  /// no depende de la contraseña, pero que hay que copiar a cada dispositivo.
  Future<void> _randomKey(BuildContext context, SyncService sync) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar clave aleatoria'),
        content: const Text(
            'Se generará una clave nueva que no depende de tu contraseña. '
            'Los demás dispositivos dejarán de recibir datos hasta que '
            'introduzcas esta clave en ellos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Generar clave')),
        ],
      ),
    );
    if (confirmed != true) return;
    final key = await sync.enableNew();
    if (context.mounted) await _showKey(context, key, firstTime: true);
  }

  Future<void> _disable(BuildContext context, SyncService sync) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dejar de sincronizar'),
        content: const Text(
            'Este dispositivo dejará de enviar y recibir datos. Los demás '
            'dispositivos y lo guardado en el servidor no se borran. Guarda '
            'la clave si quieres volver a vincularlo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dejar de sincronizar')),
        ],
      ),
    );
    if (confirmed == true) await sync.disable();
  }

  Future<void> _showKey(BuildContext context, String key,
      {bool firstTime = false}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            firstTime ? 'Sincronización activada' : 'Clave de sincronización'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Introduce esta clave en tus otros dispositivos (Ajustes → '
              'Servidor Jam) para que reciban los mismos datos. Quien la '
              'tenga puede leer lo sincronizado: guárdala en un lugar seguro.'),
          const SizedBox(height: 16),
          SelectableText(key,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 15, letterSpacing: 1)),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Clave copiada')));
              }
            },
            child: const Text('Copiar'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
        ],
      ),
    );
  }

  Future<void> _link(BuildContext context, SyncService sync) async {
    final controller = TextEditingController();
    String? error;
    final linked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Vincular con una clave'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'XXXX-XXXX-XXXX-…',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () async {
                final ok = await sync.link(controller.text);
                if (ok) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setState(() => error = 'La clave no es válida.');
                }
              },
              child: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (linked == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dispositivo vinculado. Sincronizando…')));
    }
  }
}
