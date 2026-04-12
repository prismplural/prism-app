import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Shows a dialog when editing creates gaps above the timing mode threshold.
///
/// Returns the chosen [GapResolution], or `null` if dismissed.
Future<GapResolution?> showGapResolutionDialog(
  BuildContext context, {
  required List<GapInfo> gaps,
}) async {
  final totalDuration = gaps.fold<Duration>(
    Duration.zero,
    (sum, g) => sum + g.duration,
  );

  return PrismDialog.show<GapResolution>(
    context: context,
    title: context.l10n.frontingGapDetectedTitle(gaps.length),
    message: context.l10n.frontingGapDetectedMessage(gaps.length, totalDuration.toShortString()),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gaps.length <= 5)
            ...gaps.map((gap) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.schedule,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        gap.duration.toShortString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 8),
          PrismListRow(
            padding: EdgeInsets.zero,
            leading: Icon(AppIcons.autoFixHigh),
            title: Text(ctx.l10n.frontingGapFillWithUnknown),
            subtitle: Text(ctx.l10n.frontingGapFillWithUnknownSubtitle),
            onTap: () =>
                Navigator.of(ctx).pop(GapResolution.fillWithUnknown),
          ),
          PrismListRow(
            padding: EdgeInsets.zero,
            leading: Icon(AppIcons.check),
            title: Text(ctx.l10n.frontingGapLeaveGaps),
            subtitle: Text(ctx.l10n.frontingGapLeaveGapsSubtitle),
            onTap: () => Navigator.of(ctx).pop(GapResolution.leaveGap),
          ),
        ],
      );
    },
  );
}
