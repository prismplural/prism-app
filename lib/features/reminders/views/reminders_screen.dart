import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';
import 'package:prism_plurality/features/reminders/widgets/create_reminder_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Reminders',
        showBackButton: showBackButton,
        actions: [
          PrismTopBarAction(
            icon: Icons.add,
            onPressed: () => _showCreateSheet(context),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: remindersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (reminders) {
          if (reminders.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No reminders',
              subtitle: 'Create reminders for fronting changes or scheduled times',
              actionLabel: 'Add Reminder',
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
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      onDismissed: (_) {
        notifier.deleteReminder(reminder.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${reminder.name}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                notifier.createReminder(
                  name: reminder.name,
                  message: reminder.message,
                  trigger: reminder.trigger,
                  intervalDays: reminder.intervalDays,
                  timeOfDay: reminder.timeOfDay,
                  delayHours: reminder.delayHours,
                );
              },
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: PrismSectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              reminder.trigger == ReminderTrigger.scheduled
                  ? Icons.schedule
                  : Icons.swap_horiz_rounded,
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
              _subtitleText(reminder),
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

  String _subtitleText(Reminder r) {
    if (r.trigger == ReminderTrigger.onFrontChange) {
      final delay = r.delayHours ?? 0;
      if (delay == 0) return 'On front change';
      return 'On front change (${delay}h delay)';
    }
    final parts = <String>[];
    if (r.timeOfDay != null) parts.add(r.timeOfDay!);
    if (r.intervalDays != null) {
      if (r.intervalDays == 1) {
        parts.add('Daily');
      } else {
        parts.add('Every ${r.intervalDays} days');
      }
    }
    return parts.isEmpty ? 'Scheduled' : parts.join(' · ');
  }
}
