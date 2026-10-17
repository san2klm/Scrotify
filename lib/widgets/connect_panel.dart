import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connect/connect_protocol.dart';
import '../services/connect/connect_service.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/settings_controller.dart';
import '../services/theme_controller.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';

/// Selector de dispositivos de CrotoWave Connect (estilo Spotify): lista los
/// dispositivos del usuario por LAN y por el servidor Jam y permite pasarles
/// la reproducción o traerla de vuelta.
class ConnectPanel extends StatelessWidget {
  const ConnectPanel({super.key});

  static void show(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < Responsive.mobileBreakpoint;
    if (compact) {
      final theme = context.read<ThemeController>().active;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: theme.bgApp,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: theme.bgElevated, width: 1.2),
        ),
        builder: (_) => const FractionallySizedBox(
            heightFactor: 0.7, child: ConnectPanel()),
      );
      return;
    }
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 96),
          child: Material(
            color: ctx.bgCard,
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child:
                const SizedBox(width: 380, height: 460, child: ConnectPanel()),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connect = context.watch<ConnectService>();
    final signedIn = context.watch<NavidromeService>().connected;
    final player = context.watch<PlayerController>();
    final here = connect.controlled == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Connect',
                style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: Icon(Icons.close, color: context.textSecondary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ]),
        const SizedBox(height: 4),
        _DeviceRow(
          icon: _isMobile(context) ? Icons.smartphone : Icons.computer,
          title: connect.selfName != connect.defaultName
              ? connect.selfName
              : _isMobile(context)
                  ? 'Este teléfono'
                  : 'Esta computadora',
          trailing: IconButton(
            tooltip: 'Cambiar nombre del dispositivo',
            icon: Icon(Icons.edit_outlined,
                color: context.textSecondary, size: 18),
            onPressed: () => _rename(context, connect),
          ),
          subtitle: here && player.currentTrack != null && player.playing
              ? 'Reproduciendo aquí'
              : null,
          selected: here,
          onTap: here ? null : () => _run(context, connect.bringHere),
        ),
        if (connect.lastError != null) ...[
          const SizedBox(height: 8),
          Text(connect.lastError!,
              style: TextStyle(color: context.warning, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        Expanded(child: _devices(context, connect, signedIn)),
      ]),
    );
  }

  static Future<void> _rename(
      BuildContext context, ConnectService connect) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
          current: connect.selfName, fallback: connect.defaultName),
    );
    if (name != null) await connect.rename(name);
  }

  static bool _isMobile(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.android ||
      Theme.of(context).platform == TargetPlatform.iOS;

  Widget _devices(BuildContext context, ConnectService connect, bool signedIn) {
    if (!signedIn) {
      return const _Hint(
        icon: Icons.login,
        title: 'Conecta tus dispositivos',
        body: 'Inicia sesión para ver los otros dispositivos con tu mismo '
            'usuario.',
      );
    }
    if (connect.devices.isEmpty) {
      return ListView(children: [
        Text('No se encontraron otros dispositivos',
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        if (connect.problem != null) ...[
          const SizedBox(height: 8),
          Text(connect.problem!,
              style: TextStyle(color: context.warning, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        const _Tip(
            Icons.wifi,
            'Verifica tu conexión',
            'Abre CrotoWave en el otro dispositivo con tu mismo usuario, en la '
                'misma red o con internet.'),
        const _Tip(Icons.devices_other, 'Reproduce desde otro dispositivo',
            'Va a aparecer aquí de forma automática.'),
      ]);
    }
    final names = <String, int>{};
    for (final d in connect.devices) {
      names[d.name] = (names[d.name] ?? 0) + 1;
    }
    return ListView(children: [
      for (final d in connect.devices)
        _DeviceRow(
          icon: switch (d.kind) {
            ConnectKind.phone => Icons.smartphone,
            ConnectKind.tablet => Icons.tablet,
            ConnectKind.desktop => Icons.computer,
            ConnectKind.other => Icons.speaker,
          },
          title: names[d.name]! > 1
              ? '${d.name} (${d.id.substring(0, 4)})'
              : d.name,
          subtitle: _subtitle(connect, d),
          selected: connect.controlled?.id == d.id,
          onTap: () => _run(context, () => connect.transferTo(d.id)),
        ),
    ]);
  }

  static String _subtitle(ConnectService connect, ConnectDevice d) {
    final state = connect.stateOf(d.id);
    final title = state?.track?.title;
    final where = d.viaLan ? 'Red local' : 'Internet';
    if (state != null && state.playing && title != null) {
      return '$where · Reproduciendo: $title';
    }
    return where;
  }

  Future<void> _run(
      BuildContext context, Future<void> Function() action) async {
    await action();
    if (context.mounted && context.read<ConnectService>().lastError == null) {
      Navigator.of(context).maybePop();
    }
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current, required this.fallback});
  final String current;
  final String fallback;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _input = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nombre del dispositivo'),
        content: TextField(
          controller: _input,
          autofocus: true,
          maxLength: SettingsController.maxDeviceNameLength,
          decoration: InputDecoration(
              hintText: widget.fallback,
              helperText: 'Así te verán tus otros dispositivos. '
                  'Vacío = ${widget.fallback}.'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, _input.text),
              child: const Text('Guardar')),
        ],
      );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.icon,
    required this.title,
    required this.selected,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.accent : context.textPrimary;
    return Material(
      color: selected ? context.bgElevated : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w500)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: selected
                                  ? context.accent
                                  : context.textSecondary,
                              fontSize: 12.5)),
                  ]),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: context.textSecondary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(color: context.textPrimary, fontSize: 14)),
              Text(body,
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: context.textSecondary, size: 36),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 13)),
        ]),
      );
}
