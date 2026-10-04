import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Selector de géneros para filtrar el contenido principal (Fase 9).
///
/// Muestra inicialmente un subconjunto estable (5 géneros por defecto) más la
/// opción "Todos" y un control interactivo "Mostrar todos".
/// Al pulsar "Mostrar todos", se expande para mostrar todos los géneros y el control
/// pasa a ser "Ocultar".
/// Al contraerse con "Ocultar", se restaura exactamente el subconjunto inicial.
/// Si el género actualmente seleccionado queda fuera del subconjunto contraído,
/// se preserva visible para no ocultar la selección activa al usuario.
class GenreSelector extends StatefulWidget {
  final List<String> genres;
  final String? selectedGenre;
  final ValueChanged<String?> onGenreChanged;
  final int initialCount;

  const GenreSelector({
    super.key,
    required this.genres,
    this.selectedGenre,
    required this.onGenreChanged,
    this.initialCount = 5,
  });

  @override
  State<GenreSelector> createState() => _GenreSelectorState();
}

class _GenreSelectorState extends State<GenreSelector> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasOverflow = widget.genres.length > widget.initialCount;
    final List<String> visibleGenres;

    if (_expanded || !hasOverflow) {
      visibleGenres = widget.genres;
    } else {
      final subset = widget.genres.take(widget.initialCount).toList();
      // Preservar la visibilidad del género seleccionado aunque esté fuera
      // del subconjunto contraído inicial.
      if (widget.selectedGenre != null &&
          !subset.contains(widget.selectedGenre) &&
          widget.genres.contains(widget.selectedGenre)) {
        subset.add(widget.selectedGenre!);
      }
      visibleGenres = subset;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Botón "Todos" (sin filtro)
        _genreChip(
          context,
          label: 'Todos',
          isSelected: widget.selectedGenre == null,
          onTap: () => widget.onGenreChanged(null),
        ),

        // Chips de géneros visibles
        for (final genre in visibleGenres)
          _genreChip(
            context,
            label: genre,
            isSelected: widget.selectedGenre == genre,
            onTap: () => widget.onGenreChanged(genre),
          ),

        // Control expandir / contraer ("Mostrar todos" / "Ocultar")
        if (hasOverflow)
          Semantics(
            button: true,
            label: _expanded ? 'Ocultar' : 'Mostrar todos',
            child: InkWell(
              key: const ValueKey('genre_selector_toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.bgElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.accent.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'Ocultar' : 'Mostrar todos',
                      style: TextStyle(
                        color: context.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: context.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _genreChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Género $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? context.accent.withValues(alpha: 0.15)
                : context.bgElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? context.accent : context.bgCard,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? context.accent : context.textPrimary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
