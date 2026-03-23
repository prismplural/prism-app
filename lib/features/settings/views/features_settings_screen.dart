import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen for enabling/disabling app features.
class FeaturesSettingsScreen extends ConsumerWidget {
  const FeaturesSettingsScreen({super.key});

  static String _quickSwitchLabel(int seconds) {
    if (seconds == 0) return 'Off';
    if (seconds < 60) return '${seconds}s correction window';
    return '${seconds ~/ 60}m correction window';
  }

  static void _showQuickSwitchPicker(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    const options = [
      (0, 'Off'),
      (15, '15 seconds'),
      (30, '30 seconds'),
      (60, '1 minute'),
    ];
    PrismDialog.show<void>(
      context: context,
      title: 'Quick Switch Window',
      message: 'If you switch fronters within this window, it corrects '
          'the current session instead of creating a new one.',
      builder: (ctx) {
        return RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateQuickSwitchThreshold(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (opt) => RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: opt.$1,
                    title: Text(opt.$2),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Features', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            PrismSection(
              title: 'Features',
              description:
                  'Hides a feature from navigation without deleting any data.',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    PrismSwitchRow(
                      icon: Icons.chat_outlined,
                      iconColor: Colors.blue,
                      title: 'Chat',
                      subtitle: 'In-system messaging between members',
                      value: settings.chatEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFeatureToggle(chatEnabled: value),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSwitchRow(
                      icon: Icons.poll_outlined,
                      iconColor: Colors.purple,
                      title: 'Polls',
                      subtitle: 'Create polls for system decisions',
                      value: settings.pollsEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFeatureToggle(pollsEnabled: value),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSwitchRow(
                      icon: Icons.check_circle_outline,
                      iconColor: Colors.green,
                      title: 'Habits',
                      subtitle: 'Track daily routines and goals',
                      value: settings.habitsEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFeatureToggle(habitsEnabled: value),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSwitchRow(
                      icon: Icons.bedtime_outlined,
                      iconColor: Colors.indigo,
                      title: 'Sleep Tracking',
                      subtitle: 'Log and monitor sleep sessions',
                      value: settings.sleepTrackingEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFeatureToggle(sleepTrackingEnabled: value),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSwitchRow(
                      icon: Icons.sticky_note_2_outlined,
                      iconColor: Colors.teal,
                      title: 'Notes',
                      subtitle: 'Write notes and journal entries',
                      value: settings.notesEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateNotesEnabled(value),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSwitchRow(
                      icon: Icons.alarm,
                      iconColor: Colors.amber,
                      title: 'Reminders',
                      subtitle: 'Scheduled and front-change reminders',
                      value: settings.remindersEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateRemindersEnabled(value),
                    ),
                  ],
                ),
              ),
            ),
            PrismSection(
              title: 'Habits',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSwitchRow(
                  icon: Icons.pin_outlined,
                  iconColor: Colors.green,
                  title: 'Due Habits Badge',
                  subtitle:
                      'Show count of due habits on the tab icon',
                  value: settings.habitsBadgeEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateHabitsBadgeEnabled(value),
                ),
              ),
            ),
            PrismSection(
              title: 'Chat',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSwitchRow(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: Colors.blue,
                  title: 'Log Front on Switch',
                  subtitle:
                      'Changing who\'s speaking in chat also logs a front',
                  value: settings.chatLogsFront,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateChatLogsFront(value),
                ),
              ),
            ),
            PrismSection(
              title: 'Fronting',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSettingsRow(
                  icon: Icons.speed,
                  iconColor: Colors.purple,
                  title: 'Quick Switch',
                  subtitle: _quickSwitchLabel(
                    settings.quickSwitchThresholdSeconds,
                  ),
                  onTap: () => _showQuickSwitchPicker(
                      context, ref, settings.quickSwitchThresholdSeconds),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
