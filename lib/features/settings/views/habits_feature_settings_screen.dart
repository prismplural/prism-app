import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Settings subview for the Habits feature.
class HabitsFeatureSettingsScreen extends ConsumerWidget {
  const HabitsFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Habits', showBackButton: true),
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
                'Track recurring tasks and build streaks with your system members.',
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
                  icon: Icons.check_circle_outline,
                  iconColor: Colors.green,
                  title: 'Enable Habits',
                  subtitle: 'Track daily routines and goals',
                  value: settings.habitsEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateFeatureToggle(habitsEnabled: value),
                ),
              ),
            ),
            if (settings.habitsEnabled)
              PrismSection(
                title: 'Options',
                child: PrismSectionCard(
                  padding: EdgeInsets.zero,
                  child: PrismSwitchRow(
                    icon: Icons.pin_outlined,
                    iconColor: Colors.green,
                    title: 'Due Habits Badge',
                    subtitle: 'Show count of due habits on the tab icon',
                    value: settings.habitsBadgeEnabled,
                    onChanged: (value) => ref
                        .read(settingsNotifierProvider.notifier)
                        .updateHabitsBadgeEnabled(value),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
