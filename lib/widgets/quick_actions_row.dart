import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/liked_songs_screen.dart';
import '../screens/stats_screen.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';
import 'jam_dialog.dart';

/// Fila de acciones rápidas para el inicio del teléfono: mezclar la
/// biblioteca, abrir "Me gusta", iniciar/unirse a una Jam y ver estadísticas.
/// Hace scroll horizontal si no caben (pantallas muy angostas o texto grande).
class QuickActionsRow extends StatelessWidget {
  /// Pistas con las que se arma la mezcla.
  final List<Track> tracks;

  const QuickActionsRow({super.key, required this.tracks});

  @override
  Widget build(BuildContext context) {
    final actions = <_Action>[
      _Action(
        icon: Icons.shuffle_rounded,
        label: 'Mezclar todo',
        onTap: tracks.isEmpty
            ? null
            : () => context.read<PlayerController>().playShuffledQueue(tracks),
      ),
      _Action(
        icon: Icons.favorite_rounded,
        label: 'Me gusta',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const LikedSongsScreen())),
      ),
      _Action(
        icon: Icons.groups_rounded,
        label: 'Jam',
        onTap: () => JamDialog.showAsBottomSheet(context),
      ),
      _Action(
        icon: Icons.bar_chart_rounded,
        label: 'Estadísticas',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const StatsScreen())),
      ),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = actions[i];
          return ActionChip(
            avatar: Icon(a.icon, size: 18, color: context.accent),
            label: Text(a.label),
            labelStyle: TextStyle(color: context.textPrimary, fontSize: 13),
            backgroundColor: context.bgCard,
            side: BorderSide.none,
            onPressed: a.onTap,
          );
        },
      ),
    );
  }
}

class _Action {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Action({required this.icon, required this.label, this.onTap});
}
