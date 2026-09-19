import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/create_playlist_dialog.dart';

class _Playlists extends NavidromeService {
  final pending = Completer<Playlist?>();

  @override
  Future<Playlist?> createPlaylist(String name,
          {List<int>? coverBytes, String? coverFileName}) =>
      pending.future;
}

Future<_Playlists> _open(WidgetTester tester, TargetPlatform platform) async {
  final nav = _Playlists();
  final theme = ThemeController();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NavidromeService>.value(value: nav),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showCreatePlaylistDialog(context),
            child: const Text('Abrir'),
          );
        }),
      ),
    ),
  ));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return nav;
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('cancel closes a focused playlist dialog on $platform',
        (tester) async {
      await _open(tester, platform);
      await tester.enterText(find.byType(TextField), 'Mi lista');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('create closes and refreshes playlists on $platform',
        (tester) async {
      final nav = await _open(tester, platform);
      await tester.enterText(find.byType(TextField), 'Mi lista');
      await tester.tap(find.text('Crear'));
      await tester.pump();
      nav.pending.complete(Playlist(
        id: 'playlist-1',
        name: 'Mi lista',
        songCount: 0,
        duration: 0,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(nav.playlistVersion, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
