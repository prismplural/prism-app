import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A centered date label with horizontal lines on either side.
///
/// Displays "Today", "Yesterday", or a formatted date like "March 5, 2026".
class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});

  final DateTime date;

  String _formatDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) return 'Today';
    if (dateDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat.yMMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: UnconstrainedBox(
        child: TintedGlassSurface(
          borderRadius: BorderRadius.circular(999),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            _formatDate(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
