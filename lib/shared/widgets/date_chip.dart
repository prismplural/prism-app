import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A frosted-glass pill displaying a date label.
///
/// Use this as the single date section header across all list views.
/// Formats: "Today", "Yesterday", "April 7" (current year), or
/// "April 7, 2025" (different year).
class DateChip extends StatelessWidget {
  const DateChip({
    super.key,
    required this.date,
    this.semanticHeader = true,
    this.semanticLabel,
    this.includeSemantics = true,
    this.maxWidth,
  });

  final DateTime date;
  final bool semanticHeader;
  final String? semanticLabel;
  final bool includeSemantics;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = TintedGlassSurface(
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(999)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Text(
        date.toDayHeaderLabel(context.dateLocale),
        overflow: maxWidth == null ? null : TextOverflow.ellipsis,
        softWrap: maxWidth == null,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );

    final sizedChip = maxWidth == null
        ? UnconstrainedBox(child: chip)
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: chip,
          );

    if (!includeSemantics) {
      return ExcludeSemantics(child: sizedChip);
    }

    return Semantics(
      header: semanticHeader,
      label: semanticLabel,
      child: semanticLabel == null
          ? sizedChip
          : ExcludeSemantics(child: sizedChip),
    );
  }
}
