import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server_profile.dart';
import '../screens/server_profiles_screen.dart';
import '../services/navidrome_service.dart';
import '../services/server_profiles_controller.dart';
import '../utils/app_colors.dart';
import 'account_avatar.dart';
import 'profile_connection.dart';

/// Selector de cuentas anclado debajo del avatar de la cabecera.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme;
    final controller = context.watch<ServerProfilesController?>();
    final nav = context.watch<NavidromeService>();
    final profiles = controller?.profiles ?? const <ServerProfile>[];
    final activeId = controller?.activeProfileId;
    final matching = profiles.where((profile) => profile.id == activeId);
    final active = matching.isEmpty ? null : matching.first;
    return PopupMenuButton<Object>(
      tooltip: 'Cuentas y perfiles',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      color: colors.bgCard,
      icon: AccountAvatar(profile: active, username: nav.username ?? 'U'),
      iconSize: 32,
      padding: const EdgeInsets.all(8),
      onSelected: (selection) {
        if (selection == 'manage') {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServerProfilesScreen()));
        } else if (selection is ServerProfile &&
            (selection.id != activeId || !nav.connected)) {
          connectToServerProfile(context, selection);
        }
      },
      itemBuilder: (context) => [
        for (final profile in profiles)
          PopupMenuItem<Object>(
            value: profile,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                AccountAvatar(profile: profile, username: profile.username),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          profile.nickname.isEmpty
                              ? profile.username
                              : profile.nickname,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      Text(
                          '${profile.username} · ${Uri.tryParse(profile.url)?.host ?? profile.url}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (profile.id == activeId) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded,
                      color: colors.accent,
                      size: 18,
                      semanticLabel: 'Cuenta activa'),
                ],
              ]),
            ),
          ),
        if (profiles.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: 'manage',
          child: Row(children: [
            CircleAvatar(
                radius: 16,
                backgroundColor: colors.bgElevated,
                child: Icon(Icons.add_rounded, color: colors.accent)),
            const SizedBox(width: 12),
            Expanded(
                child: Text('Gestionar cuentas',
                    style: TextStyle(color: colors.textPrimary))),
          ]),
        ),
      ],
    );
  }
}
