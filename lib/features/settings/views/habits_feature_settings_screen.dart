import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Settings subview for the Habits feature.
class HabitsFeatureSettingsScreen extends ConsumerWidget {
  const HabitsFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsEnabled = ref.watch(habitsEnabledProvider);
    final habitsBadgeEnabled = ref.watch(habitsBadgeEnabledProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.featureHabitsTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              context.l10n.featureHabitsDescription,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.featureHabitsGeneral,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                icon: AppIcons.checkCircleOutline,
                iconColor: Colors.green,
                title: context.l10n.featureHabitsEnable,
                subtitle: context.l10n.featureHabitsEnableSubtitle,
                value: habitsEnabled,
                onChanged: (value) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFeatureToggle(habitsEnabled: value),
              ),
            ),
          ),
          if (habitsEnabled)
            PrismSection(
              title: context.l10n.featureHabitsOptions,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSwitchRow(
                  icon: AppIcons.pinOutlined,
                  iconColor: Colors.green,
                  title: context.l10n.featureHabitsDueBadge,
                  subtitle: context.l10n.featureHabitsDueBadgeSubtitle,
                  value: habitsBadgeEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateHabitsBadgeEnabled(value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
