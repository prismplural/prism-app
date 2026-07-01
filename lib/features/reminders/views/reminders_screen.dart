import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';
import 'package:prism_plurality/features/reminders/widgets/create_reminder_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.remindersTitle,
        showBackButton: showBackButton,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.add,
            tooltip: context.l10n.remindersEmptyAction,
            onPressed: () => _showCreateSheet(context),
          ),
        ],
      ),
      topBarMaxWidth: PrismTokens.contentMaxWidth,
      bodyPadding: EdgeInsets.zero,
      body: remindersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) =>
            Center(child: Text(context.l10n.remindersLoadError(e.toString()))),
        data: (reminders) {
          if (reminders.isEmpty) {
            return ClampedBody(
              child: EmptyState(
                icon: Icon(AppIcons.notificationsNoneRounded),
                title: context.l10n.remindersEmptyTitle,
                subtitle: context.l10n.remindersEmptySubtitle,
                actionLabel: context.l10n.remindersEmptyAction,
                onAction: () => _showCreateSheet(context),
              ),
            );
          }

          return ClampedBody(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                24 + NavBarInset.of(context),
              ),
              itemCount: reminders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                return _ReminderTile(reminder: reminder);
              },
            ),
          );
        },
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          CreateReminderSheet(scrollController: scrollController),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(remindersNotifierProvider.notifier);
    final isActive = reminder.isActive;

    String? targetName;
    final targetId = reminder.targetMemberId;
    if (targetId != null) {
      final members = ref.watch(allMemberListProvider).value;
      if (members != null) {
        for (final m in members) {
          if (m.id == targetId) {
            targetName = m.name;
            break;
          }
        }
      }
    }

    return Dismissible(
      key: ValueKey(reminder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: Icon(AppIcons.delete, color: theme.colorScheme.onError),
      ),
      onDismissed: (_) {
        notifier.deleteReminder(reminder.id);
        PrismToast.show(
          context,
          message: context.l10n.remindersDeletedSnackbar(reminder.name),
        );
      },
      child: PrismSurface(
        key: Key('reminderCard-${reminder.id}'),
        padding: const EdgeInsets.all(16),
        tone: PrismSurfaceTone.strong,
        onTap: () => PrismSheet.showFullScreen(
          context: context,
          builder: (context, scrollController) => CreateReminderSheet(
            editing: reminder,
            scrollController: scrollController,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ReminderSummary(
                reminder: reminder,
                targetName: targetName,
                isActive: isActive,
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: isActive,
              onChanged: (value) =>
                  _setActive(context, notifier, reminder, value),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setActive(
    BuildContext context,
    RemindersNotifier notifier,
    Reminder reminder,
    bool enabled,
  ) async {
    if (!enabled) {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: context.l10n.remindersDisableTitle,
        message: context.l10n.remindersDisableMessage(reminder.name),
        confirmLabel: context.l10n.remindersDisableConfirm,
        cancelLabel: context.l10n.cancel,
      );
      if (!confirmed) return;
    }

    await notifier.toggleActive(reminder);
  }
}

class _ReminderSummary extends StatelessWidget {
  const _ReminderSummary({
    required this.reminder,
    required this.targetName,
    required this.isActive,
  });

  final Reminder reminder;
  final String? targetName;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledAlpha = isActive ? 1.0 : 0.52;
    final message = reminder.message.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reminder.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: disabledAlpha),
            height: 1.15,
          ),
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(
                alpha: isActive ? 0.88 : 0.52,
              ),
              height: 1.25,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _ReminderMetadata(
          text: _formatReminderSubtitle(context, reminder, targetName),
          isActive: isActive,
        ),
      ],
    );
  }
}

class _ReminderMetadata extends StatelessWidget {
  const _ReminderMetadata({required this.text, required this.isActive});

  final String text;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: isActive ? 0.76 : 0.48,
    );

    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
  }
}

String _formatReminderSubtitle(
  BuildContext context,
  Reminder r,
  String? targetName,
) {
  final l10n = context.l10n;
  if (r.trigger == ReminderTrigger.onFrontChange) {
    // If this reminder targets a specific member, the subtitle leads with
    // "When <name> fronts" so the target is visible at a glance. Falls back
    // to the any-front-change copy if the member can't be resolved (e.g.
    // deleted) or no target is set.
    final delay = r.delayHours ?? 0;
    if (targetName != null && targetName.isNotEmpty) {
      final prefix = l10n.remindersSubtitleTargetPrefix(targetName);
      if (delay == 0) return prefix;
      return '$prefix · ${l10n.remindersDelayHours(delay)}';
    }
    if (delay == 0) return l10n.remindersSubtitleOnFrontChange;
    return l10n.remindersSubtitleOnFrontChangeDelay(delay);
  }

  final time = _formatReminderTime(context, r.timeOfDay);
  final prefix = time.isEmpty ? '' : '$time · ';

  switch (r.frequency) {
    case ReminderFrequency.daily:
      return '$prefix${l10n.remindersSubtitleDaily}';

    case ReminderFrequency.weekly:
      final days = r.weeklyDays ?? const <int>[];
      if (days.isEmpty) return '$prefix${l10n.remindersFrequencyWeekly}';
      final sorted = [...days]..sort();
      if (sorted.length == 7) return '$prefix${l10n.remindersSubtitleEveryDay}';
      if (_reminderDaysEqual(sorted, const [1, 2, 3, 4, 5])) {
        return '$prefix${l10n.remindersSubtitleWeekdays}';
      }
      if (_reminderDaysEqual(sorted, const [0, 6])) {
        return '$prefix${l10n.remindersSubtitleWeekends}';
      }
      if (sorted.length <= 3) {
        final labels = [
          l10n.weekdayAbbreviationSun,
          l10n.weekdayAbbreviationMon,
          l10n.weekdayAbbreviationTue,
          l10n.weekdayAbbreviationWed,
          l10n.weekdayAbbreviationThu,
          l10n.weekdayAbbreviationFri,
          l10n.weekdayAbbreviationSat,
        ];
        return '$prefix${sorted.map((d) => labels[d]).join(', ')}';
      }
      return '$prefix${l10n.remindersSubtitleDaysPerWeek(sorted.length)}';

    case ReminderFrequency.interval:
      final interval = r.intervalDays ?? 1;
      if (interval == 1) return '$prefix${l10n.remindersSubtitleDaily}';
      return '$prefix${l10n.remindersSubtitleEveryNDays(interval)}';
  }
}

String _formatReminderTime(BuildContext context, String? timeOfDay) {
  final raw = timeOfDay?.trim() ?? '';
  if (raw.isEmpty) return '';

  final parts = raw.split(':');
  if (parts.length != 2) return raw;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return raw;
  }

  return context.formatTime(DateTime(2000, 1, 1, hour, minute));
}

bool _reminderDaysEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
