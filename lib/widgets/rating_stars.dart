import 'package:flutter/material.dart';

class RatingStars extends StatelessWidget {
  final int rating;
  final double size;
  final Color? color;
  final bool interactive;
  final ValueChanged<int>? onRatingChanged;

  const RatingStars({
    super.key,
    required this.rating,
    this.size = 20.0,
    this.color,
    this.interactive = false,
    this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).iconTheme.color;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isFilled = index < rating;
        final icon = isFilled
            ? Icons.star
            : Icons.star_border;

        if (!interactive) {
          return Icon(
            icon,
            size: size,
            color: effectiveColor,
          );
        }

        return GestureDetector(
          onTap: () {
            if (onRatingChanged != null) {
              onRatingChanged!(index + 1);
            }
          },
          child: Icon(
            icon,
            size: size,
            color: effectiveColor,
          ),
        );
      }),
    );
  }
}