import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Settings subview for the Chat feature.
class ChatFeatureSettingsScreen extends ConsumerWidget {
  const ChatFeatureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatEnabled = ref.watch(chatEnabledProvider);
    final chatLogsFront = ref.watch(chatLogsFrontProvider);
    final gifSearchEnabled = ref.watch(gifSearchEnabledProvider);
    final voiceNotesEnabled = ref.watch(voiceNotesEnabledProvider);
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.featureChatTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              context.l10n.featureChatDescription(terms.pluralLower),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.featureChatGeneral,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSwitchRow(
                icon: AppIcons.chatOutlined,
                iconColor: Colors.blue,
                title: context.l10n.featureChatEnable,
                subtitle: context.l10n.featureChatEnableSubtitle(terms.pluralLower),
                value: chatEnabled,
                onChanged: (value) => ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFeatureToggle(chatEnabled: value),
              ),
            ),
          ),
          if (chatEnabled)
            PrismSection(
              title: context.l10n.featureChatOptions,
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    PrismSwitchRow(
                      icon: AppIcons.swapHorizRounded,
                      iconColor: Colors.blue,
                      title: context.l10n.featureChatLogFront,
                      subtitle: context.l10n.featureChatLogFrontSubtitle,
                      value: chatLogsFront,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateChatLogsFront(value),
                    ),
                    PrismSwitchRow(
                      icon: AppIcons.gif,
                      iconColor: Colors.deepPurple,
                      title: context.l10n.featureChatGifSearch,
                      subtitle: context.l10n.featureChatGifSearchSubtitle,
                      value: gifSearchEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateGifSearchEnabled(value),
                    ),
                    PrismSwitchRow(
                      icon: AppIcons.microphone,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: context.l10n.featureChatVoiceNotes,
                      subtitle: context.l10n.featureChatVoiceNotesSubtitle,
                      value: voiceNotesEnabled,
                      onChanged: (value) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateVoiceNotesEnabled(value),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
