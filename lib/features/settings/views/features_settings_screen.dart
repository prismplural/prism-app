import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen for enabling/disabling app features.
class FeaturesSettingsScreen extends ConsumerWidget {
  const FeaturesSettingsScreen({super.key});

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
              title: 'Features with settings',
              description:
                  'Tap to configure feature-specific options.',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    PrismSettingsRow(
                      icon: Icons.chat_outlined,
                      iconColor: Colors.blue,
                      title: 'Chat',
                      subtitle: settings.chatEnabled
                          ? 'Enabled'
                          : 'Disabled',
                      onTap: () => context.go('/settings/features/chat'),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSettingsRow(
                      icon: Icons.check_circle_outline,
                      iconColor: Colors.green,
                      title: 'Habits',
                      subtitle: settings.habitsEnabled
                          ? 'Enabled'
                          : 'Disabled',
                      onTap: () => context.go('/settings/features/habits'),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSettingsRow(
                      icon: Icons.front_hand_outlined,
                      iconColor: Colors.purple,
                      title: 'Fronting',
                      subtitle: 'Quick switch and other options',
                      onTap: () => context.go('/settings/features/fronting'),
                    ),
                  ],
                ),
              ),
            ),
            PrismSection(
              title: 'Other features',
              description:
                  'Hides a feature from navigation without deleting any data.',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
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
          ],
        ),
      ),
    );
  }
}
