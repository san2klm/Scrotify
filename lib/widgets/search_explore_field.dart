import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Mismo campo y acceso a Explorar en escritorio y móvil, con soporte para
/// sugerencias/autocompletado de géneros musicales (Fase 9).
class SearchExploreField extends StatefulWidget {
  const SearchExploreField({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onExplore,
    this.onSubmitted,
    this.onGenreSelected,
    this.genreSuggestionsBuilder,
    this.searching = false,
    this.exploring = false,
    this.hintText = '¿Qué quieres escuchar hoy?',
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onExplore;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onGenreSelected;
  final List<String> Function(String query)? genreSuggestionsBuilder;
  final bool searching;
  final bool exploring;
  final String hintText;

  @override
  State<SearchExploreField> createState() => _SearchExploreFieldState();
}

class _SearchExploreFieldState extends State<SearchExploreField> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _hideOverlay();
    } else {
      _updateSuggestions(widget.controller.text);
    }
  }

  void _updateSuggestions(String text) {
    if (widget.genreSuggestionsBuilder == null ||
        text.trim().isEmpty ||
        !_focusNode.hasFocus) {
      _hideOverlay();
      return;
    }

    final suggestions = widget.genreSuggestionsBuilder!(text.trim());
    if (suggestions.isEmpty) {
      _hideOverlay();
      return;
    }

    _showOverlay(suggestions);
  }

  void _showOverlay(List<String> suggestions) {
    _hideOverlay();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? Size.zero;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          width: size.width > 0 ? size.width - 44 : 320,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 42),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: context.bgElevated,
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.accent.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(
                        children: [
                          Icon(Icons.label_outline_rounded,
                              size: 14, color: context.accent),
                          const SizedBox(width: 6),
                          Text(
                            'Géneros sugeridos',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final genre in suggestions.take(5))
                      InkWell(
                        onTap: () {
                          _hideOverlay();
                          widget.controller.text = genre;
                          if (widget.onGenreSelected != null) {
                            widget.onGenreSelected!(genre);
                          } else {
                            widget.onSearch(genre);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.music_note_rounded,
                                  size: 15, color: context.accent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  genre,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                'Filtrar',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.inputBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.inputBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      color: context.textMuted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      style:
                          TextStyle(color: context.textPrimary, fontSize: 13),
                      textInputAction: TextInputAction.search,
                      onChanged: (val) {
                        _updateSuggestions(val);
                        widget.onSearch(val);
                      },
                      onSubmitted: (val) {
                        _hideOverlay();
                        if (widget.onSubmitted != null) {
                          widget.onSubmitted!(val);
                        } else {
                          widget.onSearch(val);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle:
                            TextStyle(color: context.textMuted, fontSize: 13),
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) => value.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Limpiar búsqueda',
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: context.textMuted),
                            onPressed: () {
                              _hideOverlay();
                              widget.controller.clear();
                              widget.onSearch('');
                            },
                          )
                        : widget.searching
                            ? const SizedBox.square(
                                dimension: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 1.8),
                              )
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Explorar',
            onPressed: widget.onExplore,
            icon: Icon(
              Icons.explore_outlined,
              color: widget.exploring ? context.accent : context.textSecondary,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}
