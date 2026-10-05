import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/playlist_importer.dart';

/// Biblioteca simulada: título → (id, artista).
const _library = {
  'Song A': ('1', 'Artist One'),
  'Song B': ('2', 'Artist Two'),
  'Song C': ('3', 'Artist Three'),
};

Map<String, dynamic> _ok(Map<String, dynamic> body) => {
      'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body},
    };

void main() {
  late NavidromeService nav;
  late List<Uri> calls;
  Set<String> failingQueries = {};
  Set<String> hangingQueries = {};
  List<Map<String, String>> existingEntries = [];

  setUp(() {
    calls = [];
    failingQueries = {};
    hangingQueries = {};
    existingEntries = [];
    final client = MockClient((req) async {
      calls.add(req.url);
      final path = req.url.path;
      if (path.endsWith('search3.view')) {
        final q = req.url.queryParameters['query']!;
        if (hangingQueries.any(q.contains)) {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        if (failingQueries.any(q.contains)) {
          return http.Response('boom', 500);
        }
        final songs = [
          for (final e in _library.entries)
            if (q.toLowerCase().contains(e.key.toLowerCase()))
              {
                'id': e.value.$1,
                'title': e.key,
                'artist': e.value.$2,
                'album': 'Album',
                'duration': 200,
              },
        ];
        return http.Response(
            jsonEncode(_ok({'searchResult3': {'song': songs}})), 200);
      }
      if (path.endsWith('createPlaylist.view')) {
        return http.Response(
            jsonEncode(_ok({
              'playlist': {'id': 'new1', 'name': 'x', 'songCount': 0}
            })),
            200);
      }
      if (path.endsWith('getPlaylist.view')) {
        return http.Response(
            jsonEncode(_ok({
              'playlist': {
                'id': 'old1',
                'name': 'Vieja',
                'entry': existingEntries
                    .map((e) => {
                          'id': e['id'],
                          'title': 'T',
                          'artist': 'A',
                          'album': 'B',
                          'duration': 1,
                        })
                    .toList(),
              }
            })),
            200);
      }
      return http.Response(jsonEncode(_ok({})), 200);
    });
    nav = NavidromeService();
    nav.setConnectedForTesting(
        url: 'https://nd.example', username: 'u', password: 'p', client: client);
  });

  List<String> addedIds() => calls
      .where((u) => u.path.endsWith('updatePlaylist.view'))
      .expand((u) => u.queryParametersAll['songIdToAdd'] ?? <String>[])
      .toList();

  const tracks = [
    ImportTrack(title: 'Song A', artist: 'Artist One'),
    ImportTrack(title: 'No Existe', artist: 'Nadie'),
    ImportTrack(title: 'Song B', artist: 'Artist Two'),
  ];

  test('salta las no encontradas, sigue con la siguiente y reporta el total',
      () async {
    final result =
        await PlaylistImporter.import(tracks: tracks, nav: nav, name: 'Mi PL');
    expect(result.matched, 2);
    expect(result.unmatched.map((t) => t.title), ['No Existe']);
    expect(addedIds(), ['1', '2']);
    expect(result.playlistTouched, isTrue);
    expect(result.toExisting, isFalse);
  });

  test('informa progreso hasta 100 %', () async {
    final seen = <int>[];
    await PlaylistImporter.import(
      tracks: tracks,
      nav: nav,
      name: 'PL',
      onProgress: (p) => seen.add(p.percent),
    );
    expect(seen.first, 0);
    expect(seen.last, 100);
    expect(seen, orderedEquals([...seen]..sort()));
  });

  test('un error del servidor en una canción no aborta la importación',
      () async {
    failingQueries = {'Song B'};
    final result =
        await PlaylistImporter.import(tracks: tracks, nav: nav, name: 'PL');
    expect(result.matched, 1);
    expect(result.unmatched.length, 2);
  });

  test('una búsqueda colgada se salta por timeout', () async {
    hangingQueries = {'Song A'};
    final result = await PlaylistImporter.import(
      tracks: tracks,
      nav: nav,
      name: 'PL',
      searchTimeout: const Duration(milliseconds: 100),
    );
    expect(result.unmatched.map((t) => t.title), contains('Song A'));
    expect(result.matched, 1);
  });

  test('si no se encuentra ninguna no crea la playlist ni lanza', () async {
    final result = await PlaylistImporter.import(
      tracks: const [ImportTrack(title: 'Nada', artist: 'Nadie')],
      nav: nav,
      name: 'PL',
    );
    expect(result.matched, 0);
    expect(result.playlistTouched, isFalse);
    expect(result.unmatched.length, 1);
    expect(calls.any((u) => u.path.endsWith('createPlaylist.view')), isFalse);
  });

  test('si el servidor falla en todas, lanza un error claro', () async {
    failingQueries = {'Song', 'No'};
    expect(
      PlaylistImporter.import(tracks: tracks, nav: nav, name: 'PL'),
      throwsA(isA<Exception>()),
    );
  });

  test('agrega a una playlist existente sin duplicar ni crear otra', () async {
    existingEntries = [
      {'id': '1'}
    ];
    final result = await PlaylistImporter.import(
      tracks: tracks,
      nav: nav,
      existingPlaylistId: 'old1',
      existingPlaylistName: 'Vieja',
    );
    expect(result.toExisting, isTrue);
    expect(result.playlistId, 'old1');
    expect(result.alreadyInPlaylist, 1);
    expect(result.added, 1);
    expect(addedIds(), ['2']);
    expect(calls.any((u) => u.path.endsWith('createPlaylist.view')), isFalse);
  });

  test('cancelar detiene la importación sin tocar playlists', () async {
    var cancel = false;
    expect(
      PlaylistImporter.import(
        tracks: tracks,
        nav: nav,
        name: 'PL',
        isCancelled: () => cancel,
        onProgress: (_) => cancel = true,
      ),
      throwsA(isA<PlaylistImportCancelled>()),
    );
  });

  test('el CSV de faltantes se puede volver a importar', () {
    final csv = PlaylistImporter.tracksToCsv(const [
      ImportTrack(title: 'Hola, mundo', artist: 'Ñandú', album: 'Álbum "X"'),
    ]);
    final parsed = PlaylistImporter.parseCsv(csv);
    expect(parsed.tracks.single.title, 'Hola, mundo');
    expect(parsed.tracks.single.artist, 'Ñandú');
    expect(parsed.tracks.single.album, 'Álbum "X"');
  });

  test('CSV de Exportify con varios artistas se parsea', () {
    final parsed = PlaylistImporter.parseCsv(
        'Track Name,Artist Name(s),Album Name\n"Song A","Artist One;Artist Two","Alb"');
    expect(parsed.tracks.single.artist, 'Artist One;Artist Two');
  });
}
