import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/settings_controller.dart';
import 'package:crotowave/utils/player_select.dart';
import 'package:provider/provider.dart';

import 'player_queue_test.dart' show SessionNavidrome;
import 'support/fake_audio_player.dart';

void main() {
  testWidgets('PlayerSelector no reconstruye con cambios ajenos a su dato',
      (tester) async {
    final player = PlayerController(
      SessionNavidrome(),
      SettingsController(),
      playerA: FakeAudioPlayer('a'),
      playerB: FakeAudioPlayer('b'),
    );
    addTearDown(player.dispose);

    var builds = 0;
    await tester.pumpWidget(ChangeNotifierProvider<PlayerController>.value(
      value: player,
      child: MaterialApp(
        home: PlayerSelector.recents(builder: (_, p) {
          builds++;
          return Text('${p.recentlyPlayed.length}');
        }),
      ),
    ));
    expect(builds, 1);

    await tester.runAsync(() async {
      await player.playQueue([
        Track(id: '1', title: 'T', artist: 'A', album: 'B', duration: '10'),
      ]);
    });
    await tester.pump();
    expect(builds, 2, reason: 'cambió el historial reciente');
    expect(find.text('1'), findsOneWidget);

    // Notificaciones que no tocan el historial (repetir, etc.).
    await player.toggleRepeat();
    await player.toggleRepeat();
    await tester.pump();
    expect(builds, 2);
  });
}
