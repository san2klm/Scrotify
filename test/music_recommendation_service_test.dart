import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:navidrome_client/services/music_recommendation_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

class _FakeNavidromeService extends NavidromeService {
  final List<Track> starred;
  final List<Track> randomSongs;
  final String scope;

  _FakeNavidromeService({
    this.starred = const [],
    this.randomSongs = const [],
    this.scope = 'user_1',
  });

  @override
  bool get connected => true;

  @override
  bool get offlineMode => false;

  @override
  String get userScope => scope;

  @override
  String get serverScope => 'server_1';

  @override
  Future<List<Track>> getStarred() async => starred;

  @override
  Future<List<Track>> getRecentlyAddedTracks({int limit = 20}) async =>
      const [];

  @override
  Future<List<Track>> getRandomSongs({int size = 50, String? genre}) async =>
      randomSongs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MusicRecommendationService - Normalización y Exclusión de Duplicados', () {
    test('normalizeTitle elimina sufijos comunes de versiones y remasterizaciones', () {
      expect(
        MusicRecommendationService.normalizeTitle('Lose Control (Live at the Ryman)'),
        'lose control',
      );
      expect(
        MusicRecommendationService.normalizeTitle('Get Lucky (Radio Edit - feat. Pharrell Williams)'),
        'get lucky',
      );
      expect(
        MusicRecommendationService.normalizeTitle('Starboy - Remastered 2020'),
        'starboy',
      );
      expect(
        MusicRecommendationService.normalizeTitle('One More Time [Deluxe Edition]'),
        'one more time',
      );
      expect(
        MusicRecommendationService.normalizeTitle('Canción con Tildes Épicas'),
        'cancion con tildes epicas',
      );
    });

    test('normalizeArtist limpia nombres y colaboradores', () {
      expect(
        MusicRecommendationService.normalizeArtist('Daft Punk feat. Pharrell Williams'),
        'daft punk',
      );
      expect(
        MusicRecommendationService.normalizeArtist('The Weeknd, Daft Punk'),
        'the weeknd',
      );
      expect(
        MusicRecommendationService.normalizeArtist('ROSALÍA & Rauw Alejandro'),
        'rosalia',
      );
    });

    test('isAlreadyInLibrary detecta duplicados directos y versiones alternativas', () {
      final existingKeys = {
        MusicRecommendationService.createTrackKey('Get Lucky', 'Daft Punk'),
        MusicRecommendationService.createTrackKey('Lose Control', 'Teddy Swims'),
      };
      final existingIds = {'id_existing_1'};

      // 1. Mismo ID
      final sameIdTrack = Track(
        id: 'id_existing_1',
        title: 'Cualquier Titulo',
        artist: 'Cualquier Artista',
        album: '',
        duration: '100',
      );
      expect(
        MusicRecommendationService.isAlreadyInLibrary(
            sameIdTrack, existingKeys, existingIds),
        isTrue,
      );

      // 2. Misma canción versión Live o Radio Edit
      final liveTrack = Track(
        id: 'external_id_2',
        title: 'Lose Control (Live at the Ryman)',
        artist: 'Teddy Swims',
        album: 'Live Album',
        duration: '120',
      );
      expect(
        MusicRecommendationService.isAlreadyInLibrary(
            liveTrack, existingKeys, existingIds),
        isTrue,
      );

      // 3. Misma canción con colaboración añadida
      final featTrack = Track(
        id: 'external_id_3',
        title: 'Get Lucky (feat. Pharrell Williams)',
        artist: 'Daft Punk',
        album: 'Random Access Memories',
        duration: '240',
      );
      expect(
        MusicRecommendationService.isAlreadyInLibrary(
            featTrack, existingKeys, existingIds),
        isTrue,
      );

      // 4. Canción nueva que el usuario NO posee
      final newTrack = Track(
        id: 'external_id_4',
        title: 'Waters of Nazareth',
        artist: 'Justice',
        album: 'Cross',
        duration: '260',
      );
      expect(
        MusicRecommendationService.isAlreadyInLibrary(
            newTrack, existingKeys, existingIds),
        isFalse,
      );
    });
  });

  group('MusicRecommendationService - Descubrimiento y Hábitos', () {
    test('descubre artistas similares vía API externa y excluye canciones ya poseídas', () async {
      // Mock HTTP Client que simula respuestas de Deezer
      final mockClient = MockClient((request) async {
        final path = request.url.path;

        // Búsqueda de artista: Daft Punk -> id 27
        if (path.contains('/search/artist')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 27, 'name': 'Daft Punk'}
              ]
            }),
            200,
          );
        }

        // Artistas relacionados a Daft Punk -> Justice (id 6404)
        if (path.contains('/artist/27/related')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 6404, 'name': 'Justice'},
                {'id': 2049, 'name': 'Cassius'},
              ]
            }),
            200,
          );
        }

        // Top tracks de Justice (artista similar nuevo)
        if (path.contains('/artist/6404/top')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 1001,
                  'title': 'D.A.N.C.E',
                  'title_short': 'D.A.N.C.E',
                  'preview': 'https://preview.deezer.com/dance.mp3',
                  'duration': 210,
                  'artist': {'name': 'Justice'},
                  'album': {
                    'title': 'Cross',
                    'cover_big': 'https://cover.com/justice.jpg'
                  }
                },
                {
                  'id': 1002,
                  'title': 'Genesis',
                  'title_short': 'Genesis',
                  'preview': 'https://preview.deezer.com/genesis.mp3',
                  'duration': 234,
                  'artist': {'name': 'Justice'},
                  'album': {
                    'title': 'Cross',
                    'cover_big': 'https://cover.com/genesis.jpg'
                  }
                }
              ]
            }),
            200,
          );
        }

        // Top tracks de Daft Punk: incluye "Get Lucky" (ya en biblioteca) y "Giorgio by Moroder" (nueva)
        if (path.contains('/artist/27/top')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 2001,
                  'title': 'Get Lucky (Radio Edit)',
                  'title_short': 'Get Lucky',
                  'preview': 'https://preview.deezer.com/getlucky.mp3',
                  'duration': 240,
                  'artist': {'name': 'Daft Punk'},
                  'album': {
                    'title': 'Random Access Memories',
                    'cover_big': 'https://cover.com/ram.jpg'
                  }
                },
                {
                  'id': 2002,
                  'title': 'Giorgio by Moroder',
                  'title_short': 'Giorgio by Moroder',
                  'preview': 'https://preview.deezer.com/giorgio.mp3',
                  'duration': 544,
                  'artist': {'name': 'Daft Punk'},
                  'album': {
                    'title': 'Random Access Memories',
                    'cover_big': 'https://cover.com/ram.jpg'
                  }
                }
              ]
            }),
            200,
          );
        }

        // Búsqueda genérica
        return http.Response(jsonEncode({'data': []}), 200);
      });

      // El usuario tiene "Get Lucky" de Daft Punk en su biblioteca
      final nav = _FakeNavidromeService(
        starred: [
          Track(
            id: 'lib_track_1',
            title: 'Get Lucky',
            artist: 'Daft Punk',
            album: 'Random Access Memories',
            duration: '240',
            genre: 'Electronic',
          ),
        ],
        scope: 'usuario_santi',
      );

      final service = MusicRecommendationService(
        nav: nav,
        client: mockClient,
      );

      final recommendations = await service.getRecommendations(forceRefresh: true);

      // Verificaciones:
      expect(recommendations, isNotEmpty);

      // 1. "Get Lucky" NUNCA debe estar recomendada porque el usuario ya la tiene
      final titles = recommendations.map((t) => t.title.toLowerCase()).toList();
      expect(titles.any((t) => t.contains('get lucky')), isFalse);

      // 2. Artistas similares no poseídos (Justice) deben estar recomendados
      final artists = recommendations.map((t) => t.artist).toList();
      expect(artists.contains('Justice'), isTrue);

      // 3. Canción no poseída del artista favorito ("Giorgio by Moroder") sí puede estar
      expect(titles.contains('giorgio by moroder'), isTrue);

      // 4. Las canciones de descubrimiento tienen URL de streaming directo en su ID
      final danceTrack = recommendations.firstWhere((t) => t.title == 'D.A.N.C.E');
      expect(danceTrack.id, 'https://preview.deezer.com/dance.mp3');
      expect(danceTrack.albumArtUrl, 'https://cover.com/justice.jpg');
    });

    test('las recomendaciones se aíslan individualmente por usuario (userScope)', () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        final query = request.url.queryParameters['q'] ?? '';

        if (path.contains('/search/artist')) {
          if (query.contains('Rock')) {
            return http.Response(
                jsonEncode({
                  'data': [
                    {'id': 301, 'name': 'Rock Artist'}
                  ]
                }),
                200);
          } else {
            return http.Response(
                jsonEncode({
                  'data': [
                    {'id': 401, 'name': 'Jazz Artist'}
                  ]
                }),
                200);
          }
        }

        if (path.contains('/artist/301/related')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 302, 'name': 'Similar Rocker'}
                ]
              }),
              200);
        }

        if (path.contains('/artist/401/related')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 402, 'name': 'Similar Jazzer'}
                ]
              }),
              200);
        }

        if (path.contains('/artist/302/top') || path.contains('/artist/301/top')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 3001,
                    'title': 'Rock Discovery Track',
                    'preview': 'https://preview.com/rock.mp3',
                    'duration': 210,
                    'artist': {'name': 'Similar Rocker'},
                    'album': {'title': 'Rock Album'},
                  }
                ]
              }),
              200);
        }

        if (path.contains('/artist/402/top') || path.contains('/artist/401/top')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 4001,
                    'title': 'Jazz Discovery Track',
                    'preview': 'https://preview.com/jazz.mp3',
                    'duration': 240,
                    'artist': {'name': 'Similar Jazzer'},
                    'album': {'title': 'Jazz Album'},
                  }
                ]
              }),
              200);
        }

        return http.Response(jsonEncode({'data': []}), 200);
      });

      final userRockNav = _FakeNavidromeService(
        starred: [
          Track(id: 'r1', title: 'Song R', artist: 'Rock Artist', album: '', duration: '10', genre: 'Rock')
        ],
        scope: 'user_rock',
      );

      final userJazzNav = _FakeNavidromeService(
        starred: [
          Track(id: 'j1', title: 'Song J', artist: 'Jazz Artist', album: '', duration: '10', genre: 'Jazz')
        ],
        scope: 'user_jazz',
      );

      final service = MusicRecommendationService(client: mockClient);

      final rockRecs = await service.getRecommendations(navOverride: userRockNav, forceRefresh: true);
      final jazzRecs = await service.getRecommendations(navOverride: userJazzNav, forceRefresh: true);

      expect(rockRecs, isNotEmpty);
      expect(jazzRecs, isNotEmpty);
      // Las recomendaciones de cada usuario son independientes
      expect(rockRecs.first.id, isNot(equals(jazzRecs.first.id)));
    });

    test('en modo offline o sin red externa recurre a temas no escuchados de la biblioteca sin error', () async {
      final offlineClient = MockClient((_) async => throw http.ClientException('Offline'));

      final nav = _FakeNavidromeService(
        starred: [
          Track(id: 'starred_1', title: 'Star Song', artist: 'Known Artist', album: '', duration: '100')
        ],
        randomSongs: [
          Track(id: 'random_1', title: 'Unplayed Discovery', artist: 'New Band', album: 'Album', duration: '150'),
        ],
        scope: 'offline_user',
      );

      final service = MusicRecommendationService(
        nav: nav,
        client: offlineClient,
      );

      final recs = await service.getRecommendations(forceRefresh: true);
      expect(recs, isNotEmpty);
      expect(recs.first.title, 'Unplayed Discovery');
    });
  });
}
