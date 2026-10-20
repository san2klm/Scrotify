import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/widgets/collection_filter_bar.dart';

void main() {
  group('CollectionFilterBar helper', () {
    final t1 = Track(
      id: '1',
      title: 'Comfortably Numb',
      artist: 'Pink Floyd',
      album: 'The Wall',
      duration: '382',
      year: 1979,
      genre: 'Progressive Rock',
      userRating: 5,
    );
    final t2 = Track(
      id: '2',
      title: 'Time',
      artist: 'Pink Floyd',
      album: 'The Dark Side of the Moon',
      duration: '425',
      year: 1973,
      genre: 'Progressive Rock',
      userRating: 4,
    );
    final t3 = Track(
      id: '3',
      title: 'Billie Jean',
      artist: 'Michael Jackson',
      album: 'Thriller',
      duration: '294',
      year: 1982,
      genre: 'Pop',
      userRating: 5,
    );
    final t4 = Track(
      id: '4',
      title: 'Beat It',
      artist: 'Michael Jackson',
      album: 'Thriller',
      duration: '258',
      year: 1982,
      genre: 'Pop',
      userRating: 3,
    );

    final all = [t1, t2, t3, t4];

    test('filters tracks by title, artist, or album query', () {
      final queryPink = CollectionFilterHelper.filterAndSort(
        all,
        query: 'pink',
        sort: CollectionSort.defaultOrder,
      );
      expect(queryPink.map((t) => t.id), ['1', '2']);

      final queryThriller = CollectionFilterHelper.filterAndSort(
        all,
        query: 'thriller',
        sort: CollectionSort.defaultOrder,
      );
      expect(queryThriller.map((t) => t.id), ['3', '4']);

      final queryComfort = CollectionFilterHelper.filterAndSort(
        all,
        query: 'comfortably',
        sort: CollectionSort.defaultOrder,
      );
      expect(queryComfort.map((t) => t.id), ['1']);
    });

    test('filters tracks by genre', () {
      final pop = CollectionFilterHelper.filterAndSort(
        all,
        query: '',
        genre: 'Pop',
        sort: CollectionSort.defaultOrder,
      );
      expect(pop.map((t) => t.id), ['3', '4']);

      final rock = CollectionFilterHelper.filterAndSort(
        all,
        query: '',
        genre: 'Progressive Rock',
        sort: CollectionSort.defaultOrder,
      );
      expect(rock.map((t) => t.id), ['1', '2']);
    });

    test('sorts tracks by title (A-Z and Z-A)', () {
      final az = CollectionFilterHelper.filterAndSort(
        all,
        query: '',
        sort: CollectionSort.titleAz,
      );
      expect(az.map((t) => t.title), [
        'Beat It',
        'Billie Jean',
        'Comfortably Numb',
        'Time',
      ]);

      final za = CollectionFilterHelper.filterAndSort(
        all,
        query: '',
        sort: CollectionSort.titleZa,
      );
      expect(za.map((t) => t.title), [
        'Time',
        'Comfortably Numb',
        'Billie Jean',
        'Beat It',
      ]);
    });

    test('sorts tracks by rating and year', () {
      final byRating = CollectionFilterHelper.filterAndSort(
        all,
        query: '',
        sort: CollectionSort.rating,
      );
      // Ratings: t1=5, t3=5, t2=4, t4=3
      expect(byRating.map((t) => t.userRating), [5, 5, 4, 3]);

      final byYear = CollectionFilterHelper.filterAndSort(
        all,
        query: '',
        sort: CollectionSort.yearNewest,
      );
      // Years: 1982, 1982, 1979, 1973
      expect(byYear.map((t) => t.year), [1982, 1982, 1979, 1973]);
    });
  });
}
