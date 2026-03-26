import 'package:flutter/material.dart';

import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

/// Shows a dialog with available delete strategies.
///
/// Returns the chosen [FrontingDeleteStrategy], or `null` if dismissed.
Future<FrontingDeleteStrategy?> showDeleteStrategyDialog(
  BuildContext context, {
  required FrontingDeleteContext deleteContext,
}) async {
  return PrismDialog.show<FrontingDeleteStrategy>(
    context: context,
    title: 'What should happen to this time?',
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...deleteContext.availableStrategies.map((strategy) {
            final isRecommended =
                strategy == FrontingDeleteStrategy.convertToUnknown;
            final icon = switch (strategy) {
              FrontingDeleteStrategy.extendPrevious => Icons.arrow_back,
              FrontingDeleteStrategy.extendNext => Icons.arrow_forward,
              FrontingDeleteStrategy.splitBetweenNeighbors =>
                Icons.swap_horiz,
              FrontingDeleteStrategy.convertToUnknown => Icons.help_outline,
              FrontingDeleteStrategy.leaveGap => Icons.delete_outline,
            };
            final theme = Theme.of(ctx);
            final color = strategy == FrontingDeleteStrategy.leaveGap
                ? theme.colorScheme.error
                : null;

            return ListTile(
              contentPadding: EdgeInsets.zero,
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
                        'Recommended',
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
              label: 'Cancel',
              onPressed: () => Navigator.of(ctx).pop(null),
            ),
          ),
        ],
      );
    },
  );
}
