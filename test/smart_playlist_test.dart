import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/smart_playlist.dart';
import 'package:crotowave/services/track_filters.dart';

Track t(
  String id, {
  String? genre,
  String? suffix,
  int? year,
  int plays = 0,
  int rating = 0,
  DateTime? added,
  String artist = 'A',
}) =>
    Track(
      id: id,
      title: 'T$id',
      artist: artist,
      album: 'B',
      duration: '100',
      genre: genre,
      suffix: suffix,
      year: year,
      playCount: plays,
      userRating: rating,
      createdAt: added,
    );

void main() {
  final lib = [
    t('1', genre: 'Rock', suffix: 'flac', year: 1975, plays: 9, rating: 5),
    t('2', genre: 'rock', suffix: 'mp3', year: 1999, plays: 1),
    t('3', genre: 'Jazz', suffix: 'flac', year: 2010, plays: 4, rating: 3),
    t('4', suffix: 'ogg', plays: 0),
  ];

  group('TrackFilter', () {
    test('filtra por año, género (sin mayúsculas) y formato', () {
      expect(
          const TrackFilter(yearFrom: 1990, yearTo: 2005)
              .apply(lib)
              .map((e) => e.id),
          ['2']);
      expect(const TrackFilter(genres: {'ROCK'}).apply(lib).map((e) => e.id),
          ['1', '2']);
      expect(const TrackFilter(formats: {'FLAC'}).apply(lib).map((e) => e.id),
          ['1', '3']);
    });

    test('favoritas y puntuación mínima', () {
      expect(
          const TrackFilter(onlyStarred: true)
              .apply(lib, isStarred: (id) => id == '3')
              .map((e) => e.id),
          ['3']);
      expect(
          const TrackFilter(minRating: 4).apply(lib).map((e) => e.id), ['1']);
    });

    test('orden por año deja las pistas sin año al final', () {
      final out = const TrackFilter(sort: TrackSort.year).apply(lib);
      expect(out.map((e) => e.id), ['3', '2', '1', '4']);
    });

    test('facets lista géneros y formatos presentes', () {
      final f = TrackFilter.facets(lib);
      expect(f.genres, ['Jazz', 'Rock', 'rock']);
      expect(f.formats, ['flac', 'mp3', 'ogg']);
    });

    test('el filtro vacío no cambia nada', () {
      expect(const TrackFilter().isEmpty, isTrue);
      expect(const TrackFilter().apply(lib), lib);
    });
  });

  group('SmartPlaylist', () {
    test('reglas combinadas, límite y orden', () {
      final now = DateTime(2026, 10, 15);
      final library = [
        t('a', plays: 12, added: DateTime(2026, 10, 10)),
        t('b', plays: 8, added: DateTime(2026, 10, 1)),
        t('c', plays: 20, added: DateTime(2026, 5, 1)),
        t('d', plays: 15, added: DateTime(2026, 10, 12)),
      ];
      const smart = SmartPlaylist(
        id: 's',
        name: 'Novedades escuchadas',
        filter: TrackFilter(sort: TrackSort.playCount),
        minPlayCount: 10,
        addedWithinDays: 30,
        limit: 1,
      );
      expect(smart.evaluate(library, now: now).map((e) => e.id), ['d']);
    });

    test('shuffle usa el Random inyectado (determinista)', () {
      final library = [for (var i = 0; i < 20; i++) t('$i')];
      const smart = SmartPlaylist(id: 's', name: 'x', shuffle: true);
      final a = smart.evaluate(library, random: Random(7)).map((e) => e.id);
      final b = smart.evaluate(library, random: Random(7)).map((e) => e.id);
      expect(a.toList(), b.toList());
      expect(a.toList(), isNot(library.map((e) => e.id).toList()));
    });

    test('JSON: ida y vuelta conserva las reglas', () {
      const smart = SmartPlaylist(
        id: 'z',
        name: 'Rock favorito',
        filter: TrackFilter(
          yearFrom: 1970,
          genres: {'Rock'},
          onlyStarred: true,
          minRating: 4,
          sort: TrackSort.artist,
        ),
        maxPlayCount: 50,
        limit: 25,
      );
      final copy = SmartPlaylist.fromJson(smart.toJson());
      expect(copy.name, 'Rock favorito');
      expect(copy.filter.yearFrom, 1970);
      expect(copy.filter.genres, {'Rock'});
      expect(copy.filter.sort, TrackSort.artist);
      expect(copy.maxPlayCount, 50);
      expect(copy.limit, 25);
    });
  });
}
