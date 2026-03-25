import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Settings subview for the Reminders feature.
class RemindersFeatureSettingsScreen extends ConsumerWidget {
  const RemindersFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Reminders', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Get reminded on a schedule or when fronters change. Disabling hides reminders from navigation but keeps existing ones.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            PrismSection(
              title: 'General',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSwitchRow(
                  icon: Icons.alarm,
                  iconColor: Colors.amber,
                  title: 'Enable Reminders',
                  subtitle: 'Scheduled and front-change reminders',
                  value: settings.remindersEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateRemindersEnabled(value),
                ),
              ),
            ),
            if (settings.remindersEnabled)
              PrismSection(
                title: 'Options',
                child: PrismSectionCard(
                  padding: EdgeInsets.zero,
                  child: PrismSettingsRow(
                    icon: Icons.edit_notifications_outlined,
                    iconColor: Colors.amber,
                    title: 'Manage Reminders',
                    subtitle: 'Create and edit your reminders',
                    onTap: () => context.go('/settings/reminders'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
