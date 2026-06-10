import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Recovery sheet for the sleep-data-loss bug. Explains what happened in plain
/// language, shows how many sessions can be brought back, and restores them on
/// confirmation. Opened from the sleep-view banner and the Sleep settings tile.
///
/// [recoverableCount] is a snapshot taken at open time (both callers already
/// hold it). The sheet does not watch the count provider — a confirm surface
/// should show a stable number, and watching would flash "0" as the count
/// clears during the exit animation.
class SleepRecoverySheet extends ConsumerStatefulWidget {
  const SleepRecoverySheet({super.key, required this.recoverableCount});

  final int recoverableCount;

  static Future<void> show(
    BuildContext context, {
    required int recoverableCount,
  }) {
    return PrismSheet.show(
      context: context,
      builder: (_) => SleepRecoverySheet(recoverableCount: recoverableCount),
    );
  }

  @override
  ConsumerState<SleepRecoverySheet> createState() => _SleepRecoverySheetState();
}

class _SleepRecoverySheetState extends ConsumerState<SleepRecoverySheet> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);

    final int restored;
    try {
      restored = await ref
          .read(sleepNotifierProvider.notifier)
          .restoreDeletedSleepSessions();
    } catch (_) {
      if (!mounted) return;
      // Stay open and let the user retry — popping would strand them.
      setState(() => _restoring = false);
      PrismToast.error(
        context,
        message: context.l10n.featureSleepRestoreFailed,
      );
      return;
    }

    if (!mounted) return;
    ref.invalidate(deletedSleepSessionCountProvider);

    // Only pop if this sheet is still the topmost route. If the user dismissed
    // it mid-restore (barrier tap / back), the State stays mounted through the
    // exit animation, so an unconditional pop would punch through to a parent
    // route. (Same over-pop class as the archive-spam fix.)
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    }

    if (restored > 0) {
      Haptics.success();
      PrismToast.success(
        context,
        message: context.l10n.featureSleepRestoreSuccess(restored),
      );
    } else {
      PrismToast.show(context, message: context.l10n.featureSleepRestoreNone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sleepColor = AppColors.sleep(theme.brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: sleepColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.history, color: sleepColor),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.featureSleepRestoreDeleted,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.featureSleepRestoreDeletedSubtitle(widget.recoverableCount),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.featureSleepRestoreConfirmMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrismButton(
            label: _restoring
                ? l10n.featureSleepRecoverySheetRestoring
                : l10n.featureSleepRestoreConfirmAction,
            icon: AppIcons.history,
            tone: PrismButtonTone.filled,
            expanded: true,
            isLoading: _restoring,
            enabled: !_restoring,
            onPressed: _restore,
          ),
          const SizedBox(height: 8),
          PrismButton(
            label: l10n.cancel,
            tone: PrismButtonTone.subtle,
            expanded: true,
            enabled: !_restoring,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
