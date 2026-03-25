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

/// Settings subview for the Notes feature.
class NotesFeatureSettingsScreen extends ConsumerWidget {
  const NotesFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Notes', showBackButton: true),
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
                'A personal journal for system members. Disabling hides notes from navigation but keeps existing entries.',
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
                  icon: Icons.sticky_note_2_outlined,
                  iconColor: Colors.teal,
                  title: 'Enable Notes',
                  subtitle: 'Write notes and journal entries',
                  value: settings.notesEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateNotesEnabled(value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
