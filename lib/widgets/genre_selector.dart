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
            child: TextButton.icon(
              key: const ValueKey('genre_selector_toggle'),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20),
              label: Text(_expanded ? 'Ocultar' : 'Mostrar todos'),
              style: TextButton.styleFrom(foregroundColor: context.accent),
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
    return Tooltip(
      message: label,
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: context.sidebarActiveBg,
        backgroundColor: context.bgElevated,
        labelStyle: TextStyle(
          color: isSelected ? context.sidebarActiveText : context.textPrimary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        side: BorderSide(
            color: isSelected ? context.accent : context.borderSubtle),
        shape: const StadiumBorder(),
      ),
    );
  }
}
