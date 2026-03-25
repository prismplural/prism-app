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

/// Settings subview for the Chat feature.
class ChatFeatureSettingsScreen extends ConsumerWidget {
  const ChatFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Chat', showBackButton: true),
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
                'Internal messaging between system members.',
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
                  icon: Icons.chat_outlined,
                  iconColor: Colors.blue,
                  title: 'Enable Chat',
                  subtitle: 'In-system messaging between members',
                  value: settings.chatEnabled,
                  onChanged: (value) => ref
                      .read(settingsNotifierProvider.notifier)
                      .updateFeatureToggle(chatEnabled: value),
                ),
              ),
            ),
            if (settings.chatEnabled)
              PrismSection(
                title: 'Options',
                child: PrismSectionCard(
                  padding: EdgeInsets.zero,
                  child: PrismSwitchRow(
                    icon: Icons.swap_horiz_rounded,
                    iconColor: Colors.blue,
                    title: 'Log Front on Switch',
                    subtitle:
                        'Changing who\'s speaking in chat also logs a front',
                    value: settings.chatLogsFront,
                    onChanged: (value) => ref
                        .read(settingsNotifierProvider.notifier)
                        .updateChatLogsFront(value),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
