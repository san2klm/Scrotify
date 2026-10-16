import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/player_controller.dart';

/// Reconstruye [builder] solo cuando cambia el dato elegido del
/// [PlayerController], no con cada notificación del reproductor (play/pausa,
/// posición, buffering…).
///
/// `context.select` solo vale dentro del `build` del propio widget; esto
/// funciona también desde métodos auxiliares y `FutureBuilder`.
class PlayerSelector extends StatelessWidget {
  const PlayerSelector._(this._selector, this.builder);

  /// Solo los contadores de «más escuchado».
  const PlayerSelector.mostPlayed({
    Key? key,
    required Widget Function(BuildContext context, PlayerController player)
        builder,
  }) : this._(_mostPlayed, builder);

  /// Solo el historial reciente.
  const PlayerSelector.recents({
    Key? key,
    required Widget Function(BuildContext context, PlayerController player)
        builder,
  }) : this._(_recents, builder);

  static String _mostPlayed(PlayerController p) => p.mostPlayedSignature;
  static String _recents(PlayerController p) => p.recentlyPlayedSignature;

  final String Function(PlayerController) _selector;
  final Widget Function(BuildContext context, PlayerController player) builder;

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerController, String>(
      selector: (_, p) => _selector(p),
      builder: (ctx, _, __) => builder(ctx, ctx.read<PlayerController>()),
    );
  }
}
