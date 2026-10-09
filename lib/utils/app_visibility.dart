import 'package:flutter/widgets.dart';

/// Si la app está a la vista (o a punto de estarlo).
///
/// Para no gastar batería ni datos: los temporizadores que solo alimentan la
/// interfaz se saltan su trabajo mientras esto sea `false`. La reproducción,
/// la Jam y la sincronización no deben consultarlo: siguen en segundo plano.
/// Sin estado conocido (arranque, tests) se considera visible.
bool get isAppVisible {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;
}
