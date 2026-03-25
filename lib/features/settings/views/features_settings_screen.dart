import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen for enabling/disabling app features.
/// Each feature navigates to its own subview with toggle and settings.
class FeaturesSettingsScreen extends ConsumerWidget {
  const FeaturesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

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
              title: '',
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
                      icon: Icons.front_hand_outlined,
                      iconColor: Colors.purple,
                      title: 'Fronting',
                      subtitle: 'Quick switch settings',
                      onTap: () => context.go('/settings/features/fronting'),
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
                      icon: Icons.bedtime_outlined,
                      iconColor: Colors.indigo,
                      title: 'Sleep',
                      subtitle: settings.sleepTrackingEnabled
                          ? 'Enabled'
                          : 'Disabled',
                      onTap: () => context.go('/settings/features/sleep'),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSettingsRow(
                      icon: Icons.poll_outlined,
                      iconColor: Colors.purple,
                      title: 'Polls',
                      subtitle: settings.pollsEnabled
                          ? 'Enabled'
                          : 'Disabled',
                      onTap: () => context.go('/settings/features/polls'),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSettingsRow(
                      icon: Icons.sticky_note_2_outlined,
                      iconColor: Colors.teal,
                      title: 'Notes',
                      subtitle: settings.notesEnabled
                          ? 'Enabled'
                          : 'Disabled',
                      onTap: () => context.go('/settings/features/notes'),
                    ),
                    const Divider(height: 1, indent: 60, endIndent: 12),
                    PrismSettingsRow(
                      icon: Icons.alarm,
                      iconColor: Colors.amber,
                      title: 'Reminders',
                      subtitle: settings.remindersEnabled
                          ? 'Enabled'
                          : 'Disabled',
                      onTap: () => context.go('/settings/features/reminders'),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'Disabling a feature hides it from navigation without deleting any data.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
