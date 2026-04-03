import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Screen for enabling/disabling app features.
/// Each feature navigates to its own subview with toggle and settings.
class FeaturesSettingsScreen extends ConsumerWidget {
  const FeaturesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Features', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          PrismSection(
            title: '',
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _featureRow(
                    context,
                    icon: Icons.chat_outlined,
                    iconColor: Colors.blue,
                    title: 'Chat',
                    enabled: flags.chat,
                    onTap: () => context.go('/settings/features/chat'),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  PrismSettingsRow(
                    icon: Icons.front_hand_outlined,
                    iconColor: Colors.purple,
                    title: 'Fronting',
                    onTap: () => context.go('/settings/features/fronting'),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: Icons.check_circle_outline,
                    iconColor: Colors.green,
                    title: 'Habits',
                    enabled: flags.habits,
                    onTap: () => context.go('/settings/features/habits'),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: Icons.bedtime_outlined,
                    iconColor: Colors.indigo,
                    title: 'Sleep',
                    enabled: flags.sleep,
                    onTap: () => context.go('/settings/features/sleep'),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: Icons.poll_outlined,
                    iconColor: Colors.purple,
                    title: 'Polls',
                    enabled: flags.polls,
                    onTap: () => context.go('/settings/features/polls'),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: Icons.sticky_note_2_outlined,
                    iconColor: Colors.teal,
                    title: 'Notes',
                    enabled: flags.notes,
                    onTap: () => context.go('/settings/features/notes'),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  _featureRow(
                    context,
                    icon: Icons.alarm,
                    iconColor: Colors.amber,
                    title: 'Reminders',
                    enabled: flags.reminders,
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
    );
  }

  Widget _featureRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final chevronColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return PrismSettingsRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      showChevron: false,
      trailing: Semantics(
        label: enabled ? 'Enabled' : 'Disabled',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enabled) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Icon(
              Icons.chevron_right_rounded,
              color: chevronColor,
            ),
          ],
        ),
      ),
      onTap: onTap,
    );
  }
}
