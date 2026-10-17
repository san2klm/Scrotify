import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/add_playlist_tracks_dialog.dart';
import 'package:crotowave/widgets/cover_art.dart';

class _Playlists extends NavidromeService {
  final searches = <String, Completer<SearchResults>>{};
  List<String>? added;
  bool failSave = false;
  List<Track> existingTracks = [];

  @override
  Future<List<Track>> getPlaylistTracks(String playlistId) async =>
      existingTracks;

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
  testWidgets(
      'existing songs with covers stay disabled without narrow overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final nav = _Playlists();
    final result = _result('Canción existente');
    nav.existingTracks = result.songs;
    await _open(tester, nav);
    await tester.enterText(find.byType(TextField), 'existente');
    await tester.pump(const Duration(milliseconds: 350));
    nav.searches['existente']!.complete(result);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull);
    expect(find.textContaining('Ya en esta playlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results show uniform covers and a placeholder without artwork',
      (tester) async {
    final nav = _Playlists();
    await _open(tester, nav);
    await tester.enterText(find.byType(TextField), 'portadas');
    await tester.pump(const Duration(milliseconds: 350));
    nav.searches['portadas']!.complete(SearchResults(songs: [
      Track(
          id: 'cover',
          title: 'Con portada',
          artist: 'Artista',
          album: 'Álbum',
          duration: '10',
          albumArtUrl: 'https://example.com/cover.jpg'),
      Track(
          id: 'empty',
          title: 'Sin portada',
          artist: 'Otro',
          album: '',
          duration: '10'),
    ], albums: [], artists: []));
    await tester.pumpAndSettle();
    final covers = tester.widgetList<CoverArt>(find.byType(CoverArt)).toList();
    expect(covers, hasLength(2));
    expect(covers.first.url, 'https://example.com/cover.jpg');
    expect(covers.last.url, isNull);
    for (final cover in covers) {
      expect(cover.width, 44);
      expect(cover.height, 44);
      expect(cover.borderRadius, 6);
    }
    expect(find.byIcon(Icons.music_note_rounded), findsWidgets);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    expect(find.text('Añadir (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
}
