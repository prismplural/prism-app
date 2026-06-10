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
class SleepRecoverySheet extends ConsumerStatefulWidget {
  const SleepRecoverySheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      builder: (_) => const SleepRecoverySheet(),
    );
  }

  @override
  ConsumerState<SleepRecoverySheet> createState() => _SleepRecoverySheetState();
}

class _SleepRecoverySheetState extends ConsumerState<SleepRecoverySheet> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final restored = await ref
          .read(sleepNotifierProvider.notifier)
          .restoreDeletedSleepSessions();
      ref.invalidate(deletedSleepSessionCountProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (restored > 0) {
        Haptics.success();
        PrismToast.success(
          context,
          message: context.l10n.featureSleepRestoreSuccess(restored),
        );
      } else {
        PrismToast.show(context, message: context.l10n.featureSleepRestoreNone);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _restoring = false);
      PrismToast.error(
        context,
        message: context.l10n.featureSleepRestoreFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sleepColor = AppColors.sleep(theme.brightness);
    // The banner only opens this sheet when count > 0; fall back to 0 while the
    // async count reloads so the copy never shows a stale number.
    final count = ref
        .watch(deletedSleepSessionCountProvider)
        .maybeWhen(data: (c) => c, orElse: () => 0);

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
            l10n.featureSleepRestoreDeletedSubtitle(count),
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
