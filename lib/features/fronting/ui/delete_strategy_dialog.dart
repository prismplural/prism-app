import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Shows a dialog with available delete strategies.
///
/// Returns the chosen [FrontingDeleteStrategy], or `null` if dismissed.
Future<FrontingDeleteStrategy?> showDeleteStrategyDialog(
  BuildContext context, {
  required FrontingDeleteContext deleteContext,
}) async {
  return PrismDialog.show<FrontingDeleteStrategy>(
    context: context,
    title: context.l10n.frontingDeleteStrategyTitle,
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...deleteContext.availableStrategies.map((strategy) {
            final isRecommended =
                strategy == FrontingDeleteStrategy.convertToUnknown;
            final icon = switch (strategy) {
              FrontingDeleteStrategy.extendPrevious => AppIcons.arrowBack,
              FrontingDeleteStrategy.extendNext => AppIcons.arrowForward,
              FrontingDeleteStrategy.splitBetweenNeighbors =>
                AppIcons.swapHoriz,
              FrontingDeleteStrategy.convertToUnknown => AppIcons.helpOutline,
              FrontingDeleteStrategy.leaveGap => AppIcons.deleteOutline,
            };
            final theme = Theme.of(ctx);
            final color = strategy == FrontingDeleteStrategy.leaveGap
                ? theme.colorScheme.error
                : null;

            return PrismListRow(
              padding: EdgeInsets.zero,
              leading: Icon(icon, color: color),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      strategy.label,
                      style:
                          color != null ? TextStyle(color: color) : null,
                    ),
                  ),
                  if (isRecommended)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        ctx.l10n.frontingDeleteStrategyRecommended,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(strategy.description),
              onTap: () => Navigator.of(ctx).pop(strategy),
            );
          }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: PrismButton(
              label: ctx.l10n.cancel,
              onPressed: () => Navigator.of(ctx).pop(null),
            ),
          ),
        ],
      );
    },
  );
}
