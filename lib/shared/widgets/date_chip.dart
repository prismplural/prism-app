import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A frosted-glass pill displaying a date label.
///
/// Use this as the single date section header across all list views.
/// Formats: "Today", "Yesterday", "April 7" (current year), or
/// "April 7, 2025" (different year).
class DateChip extends StatelessWidget {
  const DateChip({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: UnconstrainedBox(
        child: TintedGlassSurface(
          borderRadius: BorderRadius.circular(999),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            date.toDayHeaderLabel(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
