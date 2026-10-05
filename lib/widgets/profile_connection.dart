import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server_profile.dart';
import '../services/navidrome_service.dart';
import '../services/server_profiles_controller.dart';
import '../services/theme_controller.dart';

/// Conserva el flujo de conexión existente para la gestión y el menú del avatar.
Future<void> connectToServerProfile(
    BuildContext context, ServerProfile profile) async {
  final colors = context.read<ThemeController>().active;
  final nav = context.read<NavidromeService>();
  final profilesController = context.read<ServerProfilesController>();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: colors.bgCard,
      content: Row(
        children: [
          CircularProgressIndicator(color: colors.accent),
          const SizedBox(width: 16),
          Text(
            'Conectando...',
            style: TextStyle(color: colors.textPrimary),
          ),
        ],
      ),
    ),
  );

  try {
    await nav.connectByUrl(profile.url, profile.username, profile.password);
    await profilesController.setActiveProfile(profile.id);

    if (context.mounted) {
      Navigator.of(context).pop(); // Cierra diálogo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: colors.bgElevated,
          content: Text(
            'Conectado a ${profile.nickname.isNotEmpty ? profile.nickname : profile.url}',
            style: TextStyle(color: colors.textPrimary),
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop(); // Cierra diálogo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: colors.danger,
          content: Text(
              'Error al conectar: ${e.toString().replaceAll("Exception: ", "")}'),
        ),
      );
    }
  }
}
