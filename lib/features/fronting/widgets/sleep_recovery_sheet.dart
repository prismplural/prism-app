import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Recovery sheet for the sleep-data-loss bug. Explains what happened, lists
/// the sessions that can be brought back, and restores them on confirmation.
/// Opened from the sleep-view banner and the Sleep settings tile.
///
/// The recoverable list is loaded once at open and held in state, so it stays
/// stable while restoring and during the exit animation (no flash to empty).
class SleepRecoverySheet extends ConsumerStatefulWidget {
  const SleepRecoverySheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      maxHeightFactor: 0.8,
      builder: (_) => const SleepRecoverySheet(),
    );
  }

  @override
  ConsumerState<SleepRecoverySheet> createState() => _SleepRecoverySheetState();
}

class _SleepRecoverySheetState extends ConsumerState<SleepRecoverySheet> {
  bool _restoring = false;
  List<FrontingSession>? _sessions; // null while loading

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(
        recoverableDeletedSleepSessionsProvider.future,
      );
      if (mounted) setState(() => _sessions = list);
    } catch (_) {
      // Don't leave the sheet stuck on the spinner — close and surface it.
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
      PrismToast.error(
        context,
        message: context.l10n.featureSleepRestoreFailed,
      );
    }
  }

  Future<void> _restore() async {
    final sessions = _sessions;
    if (sessions == null || sessions.isEmpty) return;
    setState(() => _restoring = true);

    final int restored;
    try {
      restored = await ref
          .read(sleepNotifierProvider.notifier)
          .restoreSleepSessions(sessions);
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
    ref.invalidate(recoverableDeletedSleepSessionsProvider);

    // Only pop if this sheet is still the topmost route — if the user dismissed
    // it mid-restore, an unconditional pop would punch through to a parent.
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
    final sessions = _sessions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: SingleChildScrollView(
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
              l10n.featureSleepRestoreConfirmMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (sessions == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: PrismLoadingState()),
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.featureSleepRestoreDeletedSubtitle(sessions.length),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                  itemBuilder: (context, i) =>
                      _RecoverableSleepRow(session: sessions[i]),
                ),
              ),
            ],
            const SizedBox(height: 20),
            PrismButton(
              label: _restoring
                  ? l10n.featureSleepRecoverySheetRestoring
                  : l10n.featureSleepRestoreConfirmAction,
              icon: AppIcons.history,
              tone: PrismButtonTone.filled,
              expanded: true,
              isLoading: _restoring,
              enabled: !_restoring && sessions != null && sessions.isNotEmpty,
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
      ),
    );
  }
}

/// Read-only summary of one recoverable sleep session: date, time range,
/// duration, and quality.
class _RecoverableSleepRow extends StatelessWidget {
  const _RecoverableSleepRow({required this.session});

  final FrontingSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sleepColor = AppColors.sleep(theme.brightness);

    final dateLabel = DateFormat('EEE · MMM d').format(session.startTime);
    final startStr = context.formatTime(session.startTime);
    final endStr = session.endTime != null
        ? context.formatTime(session.endTime!)
        : '–';
    final durationLabel = session.duration.toShortString();
    final qualityLabel = session.quality?.localizedLabel(l10n);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(AppIcons.bedtimeRounded, size: 18, color: sleepColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '$startStr → $endStr',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(durationLabel, style: theme.textTheme.bodyMedium),
              if (qualityLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  qualityLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
