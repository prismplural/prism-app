import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
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
  final previousSessionName = await _resolveSessionName(
    context,
    deleteContext.previous,
  );
  if (!context.mounted) return null;

  return _showStrategyDialog(
    context,
    title: 'Delete Session',
    strategies: deleteContext.availableStrategies,
    previousSessionName: previousSessionName,
  );
}

/// Period-level variant of [showDeleteStrategyDialog]. Copy stays
/// generic since a period can have multiple previous fronters.
Future<FrontingDeleteStrategy?> showDeletePeriodStrategyDialog(
  BuildContext context, {
  required FrontingDeletePeriodContext deleteContext,
}) {
  return _showStrategyDialog(
    context,
    title: 'Delete Period',
    strategies: deleteContext.availableStrategies,
    previousSessionName: null,
  );
}

Future<FrontingDeleteStrategy?> _showStrategyDialog(
  BuildContext context, {
  required String title,
  required List<FrontingDeleteStrategy> strategies,
  required String? previousSessionName,
}) {
  return PrismDialog.show<FrontingDeleteStrategy>(
    context: context,
    title: title,
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...strategies.map((strategy) {
            final copy = _copyForStrategy(
              strategy,
              previousSessionName: previousSessionName,
            );
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

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PrismListRow(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                leading: Icon(icon, color: color),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        copy.title,
                        style: color != null ? TextStyle(color: color) : null,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(copy.subtitle),
                onTap: () => Navigator.of(ctx).pop(strategy),
              ),
            );
          }),
          const SizedBox(height: 4),
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

Future<String?> _resolveSessionName(
  BuildContext context,
  FrontingSessionSnapshot? session,
) async {
  final memberId = session?.memberId;
  if (memberId == null) return null;

  final container = ProviderScope.containerOf(context, listen: false);
  final memberRepo = container.read(memberRepositoryProvider);
  final member = await memberRepo.getMemberById(memberId);
  if (member?.isDeleted == true) return null;
  return member?.name;
}

({String title, String subtitle}) _copyForStrategy(
  FrontingDeleteStrategy strategy, {
  String? previousSessionName,
}) {
  return switch (strategy) {
    FrontingDeleteStrategy.extendPrevious => (
      title: 'Extend Previous Session',
      subtitle: previousSessionName == null
          ? 'Add this time to the previous session.'
          : 'Add this time to $previousSessionName\'s session.',
    ),
    FrontingDeleteStrategy.convertToUnknown => (
      title: 'Mark as Unknown',
      subtitle: 'Keep this time, but mark it as Unknown.',
    ),
    FrontingDeleteStrategy.leaveGap => (
      title: 'Delete session',
      subtitle:
          'Remove this session. If nothing else covers this time, it will leave a gap.',
    ),
    FrontingDeleteStrategy.extendNext => (
      title: strategy.label,
      subtitle: strategy.description,
    ),
    FrontingDeleteStrategy.splitBetweenNeighbors => (
      title: strategy.label,
      subtitle: strategy.description,
    ),
  };
}
