import 'dart:math';

import 'navidrome_service.dart';
import 'track_filters.dart';

/// Playlist inteligente: reglas locales evaluadas sobre la biblioteca.
///
/// Las reglas se guardan como JSON ([toJson]/[fromJson]) para persistirlas
/// junto al resto de ajustes. No toca el servidor.
class SmartPlaylist {
  const SmartPlaylist({
    required this.id,
    required this.name,
    this.filter = const TrackFilter(),
    this.minPlayCount,
    this.maxPlayCount,
    this.addedWithinDays,
    this.limit = 100,
    this.shuffle = false,
  });

  final String id;
  final String name;

  /// Año, género, formato, favoritas, puntuación y orden.
  final TrackFilter filter;
  final int? minPlayCount;
  final int? maxPlayCount;

  /// Solo pistas añadidas en los últimos N días.
  final int? addedWithinDays;
  final int limit;
  final bool shuffle;

  /// Calcula el contenido de la playlist. [now] y [random] son inyectables
  /// para pruebas deterministas.
  List<Track> evaluate(
    Iterable<Track> library, {
    bool Function(String id)? isStarred,
    DateTime? now,
    Random? random,
  }) {
    final clock = now ?? DateTime.now();
    final since = addedWithinDays == null
        ? null
        : clock.subtract(Duration(days: addedWithinDays!));
    final candidates = [
      for (final t in library)
        if ((minPlayCount == null || t.playCount >= minPlayCount!) &&
            (maxPlayCount == null || t.playCount <= maxPlayCount!) &&
            (since == null ||
                (t.createdAt != null && !t.createdAt!.isBefore(since))))
          t,
    ];
    var result = filter.apply(candidates, isStarred: isStarred);
    if (shuffle) {
      result = [...result]..shuffle(random ?? Random());
    }
    return result.length > limit ? result.sublist(0, limit) : result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'yearFrom': filter.yearFrom,
        'yearTo': filter.yearTo,
        'genres': filter.genres.toList(),
        'formats': filter.formats.toList(),
        'onlyStarred': filter.onlyStarred,
        'minRating': filter.minRating,
        'sort': filter.sort.name,
        'minPlayCount': minPlayCount,
        'maxPlayCount': maxPlayCount,
        'addedWithinDays': addedWithinDays,
        'limit': limit,
        'shuffle': shuffle,
      };

  factory SmartPlaylist.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        raw is List ? raw.whereType<String>().toList() : const [];
    return SmartPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Playlist inteligente',
      filter: TrackFilter(
        yearFrom: (json['yearFrom'] as num?)?.toInt(),
        yearTo: (json['yearTo'] as num?)?.toInt(),
        genres: strings(json['genres']).toSet(),
        formats: strings(json['formats']).toSet(),
        onlyStarred: json['onlyStarred'] == true,
        minRating: (json['minRating'] as num?)?.toInt() ?? 0,
        sort: TrackSort.values.firstWhere(
          (s) => s.name == json['sort'],
          orElse: () => TrackSort.relevance,
        ),
      ),
      minPlayCount: (json['minPlayCount'] as num?)?.toInt(),
      maxPlayCount: (json['maxPlayCount'] as num?)?.toInt(),
      addedWithinDays: (json['addedWithinDays'] as num?)?.toInt(),
      limit: ((json['limit'] as num?)?.toInt() ?? 100).clamp(1, 5000),
      shuffle: json['shuffle'] == true,
    );
  }
}
