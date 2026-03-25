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

/// Settings subview for the Polls feature.
class PollsFeatureSettingsScreen extends ConsumerWidget {
  const PollsFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Polls', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                'Let your system vote on decisions together. Disabling hides polls from navigation but keeps existing poll data.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            PrismSection(
              title: '',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSwitchRow(
                  icon: Icons.poll_outlined,
                  iconColor: Colors.purple,
                  title: 'Enable Polls',
                  subtitle: 'Create polls for system decisions',
                  value: settings.pollsEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateFeatureToggle(pollsEnabled: value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
