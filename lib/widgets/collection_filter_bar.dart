import 'package:flutter/material.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Opciones de ordenamiento para listas de canciones en playlists y favoritos.
enum CollectionSort {
  defaultOrder('Orden original', Icons.format_list_numbered_rounded),
  titleAz('Título (A - Z)', Icons.sort_by_alpha_rounded),
  titleZa('Título (Z - A)', Icons.sort_by_alpha_rounded),
  artistAz('Artista (A - Z)', Icons.person_outline_rounded),
  yearNewest('Año (Más recientes)', Icons.calendar_today_rounded),
  rating('Calificación (Estrellas)', Icons.star_rounded),
  durationDesc('Duración (Mayor a menor)', Icons.timer_outlined);

  final String label;
  final IconData icon;
  const CollectionSort(this.label, this.icon);
}

/// Helper para filtrar y ordenar listas de pistas en memoria.
class CollectionFilterHelper {
  static List<Track> filterAndSort(
    List<Track> source, {
    required String query,
    required CollectionSort sort,
    String? genre,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    final cleanGenre = genre?.trim().toLowerCase();

    // 1. Filtrado
    final filtered = source.where((track) {
      if (cleanGenre != null && cleanGenre.isNotEmpty) {
        final tg = track.genre?.trim().toLowerCase();
        if (tg == null || tg != cleanGenre) return false;
      }

      if (cleanQuery.isNotEmpty) {
        final title = track.title.toLowerCase();
        final artist = track.artist.toLowerCase();
        final album = track.album.toLowerCase();
        if (!title.contains(cleanQuery) &&
            !artist.contains(cleanQuery) &&
            !album.contains(cleanQuery)) {
          return false;
        }
      }

      return true;
    }).toList();

    // 2. Ordenamiento
    switch (sort) {
      case CollectionSort.defaultOrder:
        break;
      case CollectionSort.titleAz:
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case CollectionSort.titleZa:
        filtered.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case CollectionSort.artistAz:
        filtered.sort((a, b) {
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case CollectionSort.yearNewest:
        filtered.sort((a, b) => (b.year ?? -1).compareTo(a.year ?? -1));
        break;
      case CollectionSort.rating:
        filtered.sort((a, b) => b.userRating.compareTo(a.userRating));
        break;
      case CollectionSort.durationDesc:
        filtered.sort((a, b) {
          final da = int.tryParse(a.duration) ?? 0;
          final db = int.tryParse(b.duration) ?? 0;
          return db.compareTo(da);
        });
        break;
    }

    return filtered;
  }
}

/// Barra visual de búsqueda, ordenamiento y filtros de género para playlists y favoritos.
class CollectionFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final CollectionSort currentSort;
  final ValueChanged<CollectionSort> onSortChanged;
  final String? selectedGenre;
  final ValueChanged<String?> onGenreChanged;
  final List<String> availableGenres;
  final int totalCount;
  final int filteredCount;

  const CollectionFilterBar({
    super.key,
    required this.searchController,
    required this.onQueryChanged,
    required this.currentSort,
    required this.onSortChanged,
    required this.selectedGenre,
    required this.onGenreChanged,
    required this.availableGenres,
    required this.totalCount,
    required this.filteredCount,
  });

  @override
  Widget build(BuildContext context) {
    final isFiltered = searchController.text.isNotEmpty ||
        selectedGenre != null ||
        currentSort != CollectionSort.defaultOrder;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Buscador de canciones
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: context.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.themeBorder),
                  ),
                  child: TextField(
                    controller: searchController,
                    onChanged: onQueryChanged,
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar canciones, artistas o álbumes...',
                      hintStyle: TextStyle(color: context.textMuted, fontSize: 13),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: context.textMuted,
                        size: 18,
                      ),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: context.textMuted,
                                size: 16,
                              ),
                              onPressed: () {
                                searchController.clear();
                                onQueryChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botón de ordenamiento
              PopupMenuButton<CollectionSort>(
                tooltip: 'Ordenar canciones',
                color: context.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: context.themeBorder),
                ),
                initialValue: currentSort,
                onSelected: onSortChanged,
                itemBuilder: (ctx) => [
                  for (final sort in CollectionSort.values)
                    PopupMenuItem<CollectionSort>(
                      value: sort,
                      child: Row(
                        children: [
                          Icon(
                            sort.icon,
                            size: 18,
                            color: currentSort == sort
                                ? context.accent
                                : context.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              sort.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: currentSort == sort
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: currentSort == sort
                                    ? context.accent
                                    : context.textPrimary,
                              ),
                            ),
                          ),
                          if (currentSort == sort)
                            Icon(Icons.check_rounded,
                                size: 16, color: context.accent),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: currentSort != CollectionSort.defaultOrder
                        ? context.accent.withValues(alpha: 0.15)
                        : context.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: currentSort != CollectionSort.defaultOrder
                          ? context.accent
                          : context.themeBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        currentSort.icon,
                        size: 16,
                        color: currentSort != CollectionSort.defaultOrder
                            ? context.accent
                            : context.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        currentSort == CollectionSort.defaultOrder
                            ? 'Ordenar'
                            : currentSort.label.split(' ').first,
                        style: TextStyle(
                          fontSize: 12,
                          color: currentSort != CollectionSort.defaultOrder
                              ? context.accent
                              : context.textPrimary,
                          fontWeight:
                              currentSort != CollectionSort.defaultOrder
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Chips de género (si hay al menos 2 géneros) y contador de resultados
          if (availableGenres.length > 1 || isFiltered) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (isFiltered) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Mostrando $filteredCount de $totalCount',
                        style: TextStyle(
                          color: context.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (availableGenres.isNotEmpty) ...[
                    ChoiceChip(
                      label: const Text('Todos'),
                      labelStyle: const TextStyle(fontSize: 11),
                      selected: selectedGenre == null,
                      onSelected: (_) => onGenreChanged(null),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    for (final g in availableGenres.take(6)) ...[
                      ChoiceChip(
                        label: Text(g),
                        labelStyle: const TextStyle(fontSize: 11),
                        selected: selectedGenre == g,
                        onSelected: (val) =>
                            onGenreChanged(val ? g : null),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
