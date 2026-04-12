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
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Settings subview for the Reminders feature.
class RemindersFeatureSettingsScreen extends ConsumerWidget {
  const RemindersFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersEnabled = ref.watch(remindersEnabledProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.featureRemindersTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              context.l10n.featureRemindersDescription,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.featureRemindersGeneral,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                icon: AppIcons.alarm,
                iconColor: Colors.amber,
                title: context.l10n.featureRemindersEnable,
                subtitle: context.l10n.featureRemindersEnableSubtitle,
                value: remindersEnabled,
                onChanged: (value) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateRemindersEnabled(value),
              ),
            ),
          ),
          if (remindersEnabled)
            PrismSection(
              title: context.l10n.featureRemindersOptions,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSettingsRow(
                  icon: AppIcons.editNotificationsOutlined,
                  iconColor: Colors.amber,
                  title: context.l10n.featureRemindersManage,
                  subtitle: context.l10n.featureRemindersManageSubtitle,
                  onTap: () => context.go('/settings/reminders'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
