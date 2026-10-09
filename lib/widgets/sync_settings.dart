import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/biometric_auth_service.dart';
import '../services/sync/sync_key_link.dart';
import '../services/sync/sync_service.dart';
import '../utils/app_colors.dart';
import 'pairing_panel.dart' show QrScannerSheet;
import 'pairing_qr_code.dart';

/// Ajustes → Servidor Jam → Sincronización entre dispositivos.
///
/// Activa la sincronización cifrada de temas, ajustes y datos de la
/// biblioteca, o vincula este dispositivo con la clave de otro.
class SyncSettings extends StatelessWidget {
  const SyncSettings({super.key, this.authorize, this.canScan});

  /// Confirma la identidad antes de mostrar el QR con la clave. Por defecto
  /// usa la biometría del dispositivo si existe (y no pide nada si no).
  final Future<bool> Function()? authorize;

  /// Si se ofrece escanear un QR (por defecto, solo en móvil).
  final bool? canScan;

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<bool> _authorizeWithBiometrics() async {
    final biometrics = BiometricAuthService();
    if (!await biometrics.isBiometricsAvailable()) return true;
    final result = await biometrics.authenticate(
        localizedReason: 'Confirma para mostrar la clave de sincronización');
    return result.isSuccess;
  }

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
            onPressed: () => _showQr(context, sync.keyText ?? ''),
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: const Text('Mostrar QR'),
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

  /// Muestra la clave como QR para vincular otro dispositivo, tras avisar de
  /// que es un secreto y confirmar la identidad.
  Future<void> _showQr(BuildContext context, String key) async {
    final link = SyncKeyLink.build(key);
    if (link == null) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mostrar QR de la clave'),
        content: const Text(
            'El código contiene tu clave de sincronización. Quien lo escanee '
            'podrá leer lo que sincronizas. Muéstralo solo a tu propio '
            'dispositivo y en un lugar privado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mostrar')),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    if (!await (authorize ?? _authorizeWithBiometrics)()) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escanea desde el otro dispositivo'),
        // Ancho fijo: el QR usa LayoutBuilder, que no admite medidas intrínsecas
        // (AlertDialog las pide para calcular su tamaño).
        content: SizedBox(
          width: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: PairingQrCode(data: link, size: 240)),
            const SizedBox(height: 12),
            const Text(
                'En el otro dispositivo: Ajustes → Sincronización → «Ya tengo '
                'una clave» → Escanear QR.'),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _link(BuildContext context, SyncService sync) async {
    final linked = await showDialog<bool>(
      context: context,
      builder: (_) => _LinkDialog(sync: sync, canScan: canScan ?? _isMobile),
    );
    if (linked == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dispositivo vinculado. Sincronizando…')));
    }
  }
}

/// Diálogo para vincular este dispositivo con la clave de otro, escrita,
/// pegada o escaneada desde un QR.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.sync, required this.canScan});

  final SyncService sync;
  final bool canScan;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _linkWith(String text) async {
    final ok = await widget.sync.link(SyncKeyLink.parse(text) ?? text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'La clave no es válida.');
    }
  }

  Future<void> _scan() async {
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QrScannerSheet(
        prefix: SyncKeyLink.scheme,
        hint: 'Apunta al QR de «Mostrar QR» en tu otro dispositivo.',
      ),
    );
    if (scanned == null || !mounted) return;
    final key = SyncKeyLink.parse(scanned);
    if (key == null) {
      setState(() => _error = 'El QR no es una clave válida.');
    } else {
      await _linkWith(key);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Vincular con una clave'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'XXXX-XXXX-XXXX-…',
              errorText: _error,
            ),
          ),
          if (widget.canScan)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('Escanear QR'),
              ),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => _linkWith(_controller.text),
              child: const Text('Vincular')),
        ],
      );
}
