import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/add_playlist_tracks_dialog.dart';
import 'package:navidrome_client/widgets/cover_art.dart';

class _Playlists extends NavidromeService {
  final searches = <String, Completer<SearchResults>>{};
  List<String>? added;
  bool failSave = false;

  @override
  Future<SearchResults> search(String query) =>
      (searches[query] = Completer<SearchResults>()).future;

  @override
  Future<void> updatePlaylist({
    required String playlistId,
    String? name,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  }) async {
    if (failSave) throw Exception('Permiso denegado');
    added = songIdsToAdd;
  }
}

SearchResults _result(String title) => SearchResults(songs: [
      Track(
          id: title,
          title: title,
          artist: 'Artista',
          album: '',
          duration: '10'),
    ], albums: [], artists: []);

Future<void> _open(WidgetTester tester, _Playlists nav) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NavidromeService>.value(value: nav),
      ChangeNotifierProvider<ThemeController>.value(value: ThemeController()),
    ],
    child: MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showAddPlaylistTracksDialog(context,
              Playlist(id: 'list', name: 'Lista', songCount: 0, duration: 0)),
          child: const Text('Abrir'),
        );
      })),
    ),
  ));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adds selected tracks across searches and reports save failures',
      (tester) async {
    final nav = _Playlists();
    await _open(tester, nav);
    for (final title in ['Primera', 'Segunda']) {
      await tester.enterText(find.byType(TextField), title);
      await tester.pump(const Duration(milliseconds: 350));
      nav.searches[title]!.complete(_result(title));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
    }
    nav.failSave = true;
    await tester.tap(find.text('Añadir (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Permiso denegado'), findsOneWidget);
    expect(find.text('Añadir (2)'), findsOneWidget);
    expect(nav.added, isNull);
    nav.failSave = false;
    await tester.tap(find.text('Añadir (2)'));
    await tester.pumpAndSettle();
    expect(nav.added, ['Primera', 'Segunda']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older search response cannot replace newer results',
      (tester) async {
    final nav = _Playlists();
    await _open(tester, nav);
    await tester.enterText(find.byType(TextField), 'vieja');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'nueva');
    await tester.pump(const Duration(milliseconds: 350));
    nav.searches['nueva']!.complete(_result('Resultado nuevo'));
    await tester.pumpAndSettle();
    nav.searches['vieja']!.complete(_result('Resultado viejo'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado nuevo'), findsOneWidget);
    expect(find.text('Resultado viejo'), findsNothing);
  });

  testWidgets('closing while searching ignores a late result', (tester) async {
    final nav = _Playlists();
    await _open(tester, nav);
    await tester.enterText(find.byType(TextField), 'consulta');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    nav.searches['consulta']!.complete(_result('Resultado tardío'));
    await tester.pumpAndSettle();
    expect(nav.added, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders CoverArt to the left of title and artist in search results',
      (tester) async {
    final nav = _Playlists();
    await _open(tester, nav);
    await tester.enterText(find.byType(TextField), 'prueba');
    await tester.pump(const Duration(milliseconds: 350));
    nav.searches['prueba']!.complete(SearchResults(
      songs: [
        Track(
          id: 'song-1',
          title: 'Cancion Con Portada',
          artist: 'Artista Famoso',
          album: 'Album Uno',
          duration: '180',
          albumArtUrl: 'https://example.com/cover.jpg',
        ),
      ],
      albums: [],
      artists: [],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CoverArt), findsOneWidget);
    final coverFinder = find.byType(CoverArt);
    final titleFinder = find.text('Cancion Con Portada');
    expect(coverFinder, findsOneWidget);
    expect(titleFinder, findsOneWidget);

    // Verify CoverArt is to the left of the title
    final coverTopLeft = tester.getTopLeft(coverFinder);
    final titleTopLeft = tester.getTopLeft(titleFinder);
    expect(coverTopLeft.dx, lessThan(titleTopLeft.dx));

    final cover = tester.widget<CoverArt>(coverFinder);
    expect(cover.width, 44);
    expect(cover.height, 44);
    expect(cover.borderRadius, 6);
    expect(cover.fallbackIcon, Icons.music_note);
  });
}

