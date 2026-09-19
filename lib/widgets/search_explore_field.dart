import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Mismo campo y acceso a Explorar en escritorio y móvil.
class SearchExploreField extends StatelessWidget {
  const SearchExploreField({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onExplore,
    this.onSubmitted,
    this.searching = false,
    this.exploring = false,
    this.hintText = '¿Qué quieres escuchar hoy?',
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onExplore;
  final bool searching;
  final bool exploring;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                Icon(Icons.search_rounded, color: context.textMuted, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                    textInputAction: TextInputAction.search,
                    onChanged: onSearch,
                    onSubmitted: onSubmitted ?? onSearch,
                    decoration: InputDecoration(
                      hintText: hintText,
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
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: Icon(Icons.close_rounded,
                              size: 16, color: context.textMuted),
                          onPressed: () {
                            controller.clear();
                            onSearch('');
                          },
                        )
                      : searching
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
          onPressed: onExplore,
          icon: Icon(Icons.explore_outlined,
              color: exploring ? context.accent : context.textSecondary,
              size: 21),
        ),
      ],
    );
  }
}
