import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';
import 'package:prism_plurality/features/reminders/widgets/create_reminder_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

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
            onPressed: () => _showCreateSheet(context),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: remindersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text(context.l10n.remindersLoadError(e.toString()))),
        data: (reminders) {
          if (reminders.isEmpty) {
            return EmptyState(
              icon: Icon(AppIcons.notificationsNoneRounded),
              title: context.l10n.remindersEmptyTitle,
              subtitle: context.l10n.remindersEmptySubtitle,
              actionLabel: context.l10n.remindersEmptyAction,
              onAction: () => _showCreateSheet(context),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(
              top: 8,
              bottom: NavBarInset.of(context),
            ),
            itemCount: reminders.length,
            itemBuilder: (context, index) {
              final reminder = reminders[index];
              return _ReminderTile(reminder: reminder);
            },
          );
        },
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateReminderSheet(
        scrollController: scrollController,
      ),
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
        PrismToast.show(context, message: context.l10n.remindersDeletedSnackbar(reminder.name));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: PrismGroupedSectionCard(
          child: PrismListRow(
            padding: EdgeInsets.zero,
            leading: Icon(
              reminder.trigger == ReminderTrigger.scheduled
                  ? AppIcons.schedule
                  : AppIcons.swapHorizRounded,
              color: reminder.isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            title: Text(
              reminder.name,
              style: TextStyle(
                color: reminder.isActive
                    ? null
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            subtitle: Text(
              _formatReminderSubtitle(context, reminder),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            trailing: Switch.adaptive(
              value: reminder.isActive,
              onChanged: (_) => notifier.toggleActive(reminder),
            ),
            onTap: () => PrismSheet.showFullScreen(
              context: context,
              builder: (context, scrollController) => CreateReminderSheet(
                editing: reminder,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatReminderSubtitle(BuildContext context, Reminder r) {
  final l10n = context.l10n;
  if (r.trigger == ReminderTrigger.onFrontChange) {
    final delay = r.delayHours ?? 0;
    if (delay == 0) return l10n.remindersSubtitleOnFrontChange;
    return l10n.remindersSubtitleOnFrontChangeDelay(delay);
  }

  final time = r.timeOfDay;
  final prefix = time == null || time.isEmpty ? '' : '$time · ';

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

bool _reminderDaysEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
