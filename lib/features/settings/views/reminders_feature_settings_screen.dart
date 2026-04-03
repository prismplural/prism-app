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
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Settings subview for the Reminders feature.
class RemindersFeatureSettingsScreen extends ConsumerWidget {
  const RemindersFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersEnabled = ref.watch(remindersEnabledProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Reminders', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'Get reminded on a schedule or when fronters change. Disabling hides reminders from navigation but keeps existing ones.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: 'General',
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                icon: AppIcons.alarm,
                iconColor: Colors.amber,
                title: 'Enable Reminders',
                subtitle: 'Scheduled and front-change reminders',
                value: remindersEnabled,
                onChanged: (value) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateRemindersEnabled(value),
              ),
            ),
          ),
          if (remindersEnabled)
            PrismSection(
              title: 'Options',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSettingsRow(
                  icon: AppIcons.editNotificationsOutlined,
                  iconColor: Colors.amber,
                  title: 'Manage Reminders',
                  subtitle: 'Create and edit your reminders',
                  onTap: () => context.go('/settings/reminders'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
