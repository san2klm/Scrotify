import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crotowave/services/navidrome_service.dart';

String ok(Map<String, dynamic> payload) => jsonEncode({
      'subsonic-response': {'status': 'ok', ...payload}
    });

Map<String, dynamic> song(String id) =>
    {'id': id, 'title': 'T$id', 'artist': 'A', 'album': 'B', 'duration': 10};

void main() {
  late List<Uri> requests;
  late Map<String, String> responses; // endpoint -> body

  NavidromeService service() {
    final client = MockClient((req) async {
      requests.add(req.url);
      final endpoint = req.url.pathSegments.last.replaceAll('.view', '');
      final body = responses[endpoint];
      if (body == null) {
        return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'failed',
                'error': {'code': 70, 'message': 'no existe'}
              }
            }),
            200);
      }
      return http.Response(body, 200);
    });
    return NavidromeService(httpClient: client)
      ..setConnectedForTesting(
          url: 'https://musica.example.invalid',
          username: 'ana',
          password: 'clave',
          client: client);
  }

  setUp(() {
    requests = [];
    responses = {};
  });

  test('radio de artista: top + similares, sin repetidos y propios primero',
      () async {
    responses['getTopSongs'] = ok({
      'topSongs': {
        'song': [song('1'), song('2')]
      }
    });
    responses['getSimilarSongs2'] = ok({
      'similarSongs2': {
        'song': [song('2'), song('3')]
      }
    });
    final tracks = await service().getArtistRadio('ar1', 'Queen');
    expect(tracks.map((t) => t.id), ['1', '2', '3']);
    final top = requests.firstWhere((u) => u.path.contains('getTopSongs'));
    expect(top.queryParameters['artist'], 'Queen');
  });

  test('un servidor sin el endpoint devuelve listas vacías, no lanza',
      () async {
    final nav = service();
    expect(await nav.getSimilarSongs('x'), isEmpty);
    expect(await nav.getBookmarks(), isEmpty);
    expect(await nav.getInternetRadioStations(), isEmpty);
    expect(await nav.getSavedPlayQueue(), isNull);
    expect(await nav.getArtistBio('x'), isNull);
  });

  test('cola guardada: se envía con ids y posición y se recupera', () async {
    responses['savePlayQueue'] = ok({});
    final nav = service();
    expect(
        await nav
            .savePlayQueue(['a', 'b', 'c'], currentId: 'b', positionMs: 4200),
        isTrue);
    final sent = requests.single;
    expect(sent.queryParametersAll['id'], ['a', 'b', 'c']);
    expect(sent.queryParameters['current'], 'b');
    expect(sent.queryParameters['position'], '4200');

    responses['getPlayQueue'] = ok({
      'playQueue': {
        'current': 'b',
        'position': 4200,
        'changedBy': 'Pixel',
        'entry': [song('a'), song('b'), song('c')],
      }
    });
    final saved = await nav.getSavedPlayQueue();
    expect(saved!.tracks, hasLength(3));
    expect(saved.currentIndex, 1);
    expect(saved.positionMs, 4200);
    expect(saved.changedBy, 'Pixel');
  });

  test('una cola vacía no se guarda', () async {
    expect(await service().savePlayQueue([]), isFalse);
    expect(requests, isEmpty);
  });

  test('biografía: texto sin HTML y artistas similares', () async {
    responses['getArtistInfo2'] = ok({
      'artistInfo2': {
        'biography':
            'Banda británica. <a target="_blank" href="https://x">Leer más</a>',
        'largeImageUrl': 'https://img.example.invalid/q.jpg',
        'similarArtist': {'id': 'ar2', 'name': 'Genesis'},
      }
    });
    final bio = await service().getArtistBio('ar1');
    expect(bio!.biography, 'Banda británica. Leer más');
    expect(bio.imageUrl, 'https://img.example.invalid/q.jpg');
    expect(bio.similarArtists.single.name, 'Genesis',
        reason: 'un objeto suelto se trata como lista');
  });

  test('marcadores: lectura, creación y borrado', () async {
    responses['getBookmarks'] = ok({
      'bookmarks': {
        'bookmark': [
          {
            'position': 90000,
            'comment': 'capítulo 3',
            'entry': song('l1'),
          }
        ]
      }
    });
    responses['createBookmark'] = ok({});
    responses['deleteBookmark'] = ok({});
    final nav = service();
    final marks = await nav.getBookmarks();
    expect(marks.single.positionMs, 90000);
    expect(marks.single.track.id, 'l1');
    expect(await nav.createBookmark('l1', 120000, comment: 'x'), isTrue);
    expect(await nav.deleteBookmark('l1'), isTrue);
  });

  test('radios de internet y podcasts', () async {
    responses['getInternetRadioStations'] = ok({
      'internetRadioStations': {
        'internetRadioStation': [
          {'id': 'r1', 'name': 'Radio Uno', 'streamUrl': 'https://r.example/1'},
          {'id': 'r2', 'name': 'Sin stream', 'streamUrl': ''},
        ]
      }
    });
    responses['getPodcasts'] = ok({
      'podcasts': {
        'channel': {
          'id': 'p1',
          'title': 'Podcast',
          'episode': [song('e1'), song('e2')],
        }
      }
    });
    final nav = service();
    final stations = await nav.getInternetRadioStations();
    expect(stations.map((s) => s.name), ['Radio Uno']);
    final podcasts = await nav.getPodcasts();
    expect(podcasts.single.episodes, hasLength(2));
  });
}
