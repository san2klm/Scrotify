import 'package:flutter/material.dart';

import '../services/navidrome_service.dart';
import '../services/track_filters.dart';
import '../utils/app_colors.dart';

/// Barra de orden y filtros para resultados de búsqueda de canciones.
///
/// Es «tonta»: recibe el [filter] actual y avisa con [onChanged]; el estado lo
/// guarda la pantalla. Las opciones de género/formato salen de [tracks].
class TrackFilterBar extends StatelessWidget {
  const TrackFilterBar({
    super.key,
    required this.filter,
    required this.tracks,
    required this.onChanged,
  });

  final TrackFilter filter;

  /// Resultados sin filtrar (de ellos salen los géneros y formatos).
  final List<Track> tracks;
  final ValueChanged<TrackFilter> onChanged;

  static const _sortLabels = {
    TrackSort.relevance: 'Relevancia',
    TrackSort.title: 'Título',
    TrackSort.artist: 'Artista',
    TrackSort.year: 'Año',
    TrackSort.recentlyAdded: 'Añadidas hace poco',
    TrackSort.playCount: 'Más escuchadas',
  };

  TrackFilter _with({
    Set<String>? genres,
    Set<String>? formats,
    bool? onlyStarred,
    TrackSort? sort,
  }) =>
      TrackFilter(
        yearFrom: filter.yearFrom,
        yearTo: filter.yearTo,
        genres: genres ?? filter.genres,
        formats: formats ?? filter.formats,
        onlyStarred: onlyStarred ?? filter.onlyStarred,
        minRating: filter.minRating,
        sort: sort ?? filter.sort,
      );

  Set<String> _toggle(Set<String> set, String value) {
    final lower = value.toLowerCase();
    final has = set.any((e) => e.toLowerCase() == lower);
    return has
        ? set.where((e) => e.toLowerCase() != lower).toSet()
        : {...set, value};
  }

  @override
  Widget build(BuildContext context) {
    final facets = TrackFilter.facets(tracks);
    final selectedGenres = filter.genres.map((e) => e.toLowerCase()).toSet();
    final selectedFormats = filter.formats.map((e) => e.toLowerCase()).toSet();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Ordenar:',
              style: TextStyle(color: context.textMuted, fontSize: 12)),
          DropdownButton<TrackSort>(
            value: filter.sort,
            isDense: true,
            underline: const SizedBox.shrink(),
            dropdownColor: context.bgElevated,
            style: TextStyle(color: context.textPrimary, fontSize: 12.5),
            items: [
              for (final entry in _sortLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (sort) {
              if (sort != null) onChanged(_with(sort: sort));
            },
          ),
          FilterChip(
            label: const Text('Favoritas'),
            selected: filter.onlyStarred,
            onSelected: (v) => onChanged(_with(onlyStarred: v)),
          ),
          for (final format in facets.formats)
            FilterChip(
              label: Text(format.toUpperCase()),
              selected: selectedFormats.contains(format),
              onSelected: (_) =>
                  onChanged(_with(formats: _toggle(filter.formats, format))),
            ),
          for (final genre in facets.genres.take(8))
            FilterChip(
              label: Text(genre),
              selected: selectedGenres.contains(genre.toLowerCase()),
              onSelected: (_) =>
                  onChanged(_with(genres: _toggle(filter.genres, genre))),
            ),
          if (!filter.isEmpty)
            TextButton(
              onPressed: () => onChanged(const TrackFilter()),
              child: const Text('Limpiar'),
            ),
        ],
      ),
    );
  }
}
