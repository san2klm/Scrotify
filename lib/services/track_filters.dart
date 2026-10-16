import 'navidrome_service.dart';

/// Orden de los resultados de búsqueda.
enum TrackSort { relevance, title, artist, year, recentlyAdded, playCount }

/// Filtros locales sobre los resultados de `search3` (el servidor no los
/// admite): año, género, formato, favoritas y puntuación mínima.
class TrackFilter {
  const TrackFilter({
    this.yearFrom,
    this.yearTo,
    this.genres = const {},
    this.formats = const {},
    this.onlyStarred = false,
    this.minRating = 0,
    this.sort = TrackSort.relevance,
  });

  final int? yearFrom;
  final int? yearTo;

  /// Géneros aceptados (sin distinguir mayúsculas). Vacío = todos.
  final Set<String> genres;

  /// Extensiones aceptadas (`flac`, `mp3`…). Vacío = todas.
  final Set<String> formats;
  final bool onlyStarred;
  final int minRating;
  final TrackSort sort;

  bool get isEmpty =>
      yearFrom == null &&
      yearTo == null &&
      genres.isEmpty &&
      formats.isEmpty &&
      !onlyStarred &&
      minRating <= 0 &&
      sort == TrackSort.relevance;

  bool matches(Track t, {bool Function(String id)? isStarred}) {
    final year = t.year;
    if (yearFrom != null && (year == null || year < yearFrom!)) return false;
    if (yearTo != null && (year == null || year > yearTo!)) return false;
    if (genres.isNotEmpty) {
      final g = t.genre?.trim().toLowerCase();
      if (g == null || !genres.any((x) => x.trim().toLowerCase() == g)) {
        return false;
      }
    }
    if (formats.isNotEmpty) {
      final f = t.suffix?.trim().toLowerCase();
      if (f == null || !formats.any((x) => x.trim().toLowerCase() == f)) {
        return false;
      }
    }
    if (onlyStarred && !(isStarred?.call(t.id) ?? false)) return false;
    if (t.userRating < minRating) return false;
    return true;
  }

  /// Aplica filtro y orden. `relevance` conserva el orden del servidor.
  List<Track> apply(List<Track> tracks, {bool Function(String id)? isStarred}) {
    final out = [
      for (final t in tracks)
        if (matches(t, isStarred: isStarred)) t,
    ];
    int byText(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    switch (sort) {
      case TrackSort.relevance:
        break;
      case TrackSort.title:
        out.sort((a, b) => byText(a.title, b.title));
      case TrackSort.artist:
        out.sort((a, b) {
          final c = byText(a.artist, b.artist);
          return c != 0 ? c : byText(a.title, b.title);
        });
      case TrackSort.year:
        // Sin año al final; más recientes primero.
        out.sort((a, b) => (b.year ?? -1).compareTo(a.year ?? -1));
      case TrackSort.recentlyAdded:
        out.sort((a, b) {
          final da = a.createdAt, db = b.createdAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      case TrackSort.playCount:
        out.sort((a, b) => b.playCount.compareTo(a.playCount));
    }
    return out;
  }

  /// Géneros y formatos presentes en [tracks]: opciones para la interfaz.
  static ({List<String> genres, List<String> formats}) facets(
      Iterable<Track> tracks) {
    final genres = <String>{}, formats = <String>{};
    for (final t in tracks) {
      final g = t.genre?.trim();
      if (g != null && g.isNotEmpty) genres.add(g);
      final f = t.suffix?.trim().toLowerCase();
      if (f != null && f.isNotEmpty) formats.add(f);
    }
    return (
      genres: genres.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      formats: formats.toList()..sort(),
    );
  }
}
