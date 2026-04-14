import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Displays a single [FrontingValidationIssue] as a tappable list tile.
///
/// Shows a severity-coloured left accent, an issue-type chip, summary text,
/// time range, and affected session count.
class ValidationIssueTile extends StatelessWidget {
  const ValidationIssueTile({
    super.key,
    required this.issue,
    this.onTap,
  });

  final FrontingValidationIssue issue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severityColor = _severityColor(theme);

    return PrismSurface(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.zero,
      borderColor: severityColor.withValues(alpha: 0.4),
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Severity accent bar
            Container(
              width: 4,
              color: severityColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type badge + session count
                    Row(
                      children: [
                        _TypeChip(type: issue.type, color: severityColor),
                        const Spacer(),
                        if (issue.sessionIds.isNotEmpty)
                          Text(
                            context.l10n.frontingIssueSessionCount(issue.sessionIds.length),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Summary
                    Text(
                      issue.summary,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    // Time range
                    Text(
                      _formatRange(context, issue.rangeStart, issue.rangeEnd),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Chevron
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  AppIcons.chevronRight,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(ThemeData theme) {
    return switch (issue.severity) {
      FrontingIssueSeverity.error => theme.colorScheme.error,
      FrontingIssueSeverity.warning => Colors.amber,
      FrontingIssueSeverity.info => Colors.blue,
    };
  }

  static String _formatRange(BuildContext context, DateTime start, DateTime end) {
    final locale = context.dateLocale;
    final dateFmt = DateFormat('MMM d', locale);
    final timeFmt = DateFormat('h:mm a', locale);
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;

    if (sameDay) {
      return '${dateFmt.format(start)}  ${timeFmt.format(start)} – ${timeFmt.format(end)}';
    }
    return '${dateFmt.format(start)} ${timeFmt.format(start)} – '
        '${dateFmt.format(end)} ${timeFmt.format(end)}';
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, required this.color});

  final FrontingIssueType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _label(context, type),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _label(BuildContext context, FrontingIssueType type) {
    final l10n = context.l10n;
    return switch (type) {
      FrontingIssueType.overlap => l10n.frontingIssueTypeOverlap,
      FrontingIssueType.gap => l10n.frontingIssueTypeGap,
      FrontingIssueType.duplicate => l10n.frontingIssueTypeDuplicate,
      FrontingIssueType.mergeableAdjacent => l10n.frontingIssueTypeMergeable,
      FrontingIssueType.invalidRange => l10n.frontingIssueTypeInvalidRange,
      FrontingIssueType.futureSession => l10n.frontingIssueTypeFutureSession,
    };
  }
}
