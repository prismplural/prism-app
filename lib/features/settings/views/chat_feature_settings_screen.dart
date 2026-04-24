import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/widgets/gif_consent_dialog.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
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
    final useProxyTagsForAuthoring =
        ref
            .watch(useProxyTagsForAuthoringProvider)
            .whenOrNull(data: (v) => v) ??
        false;
    final gifConfig = ref.watch(gifServiceConfigProvider).asData?.value;
    final gifConsentState = ref.watch(gifConsentStateProvider);
    final voiceNotesEnabled = ref.watch(voiceNotesEnabledProvider);
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final speakingAs = ref.watch(speakingAsProvider);
    final badgePrefs = ref.watch(chatBadgePreferencesProvider);
    final isMentionsOnly =
        speakingAs != null && badgePrefs[speakingAs] == 'mentions_only';
    final memberName = speakingAs == null
        ? null
        : ref
              .watch(memberByIdProvider(speakingAs))
              .whenOrNull(data: (m) => m?.name);
    final gifAvailable = gifConfig?.enabled == true;
    final gifConsentSubtitle = !gifAvailable
        ? context.l10n.featureChatGifSearchSyncRequiredSubtitle
        : switch (gifConsentState) {
            GifConsentState.unknown =>
              context.l10n.featureChatGifSearchUndecidedSubtitle,
            GifConsentState.enabled =>
              context.l10n.featureChatGifSearchEnabledSubtitle,
            GifConsentState.declined =>
              context.l10n.featureChatGifSearchDeclinedSubtitle,
          };

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.featureChatTitle,
        showBackButton: true,
      ),
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
            child: PrismGroupedSectionCard(
              child: PrismSwitchRow(
                icon: AppIcons.chatOutlined,
                iconColor: Colors.blue,
                title: context.l10n.featureChatEnable,
                subtitle: context.l10n.featureChatEnableSubtitle(
                  terms.pluralLower,
                ),
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
              child: PrismGroupedSectionCard(
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
                      icon: AppIcons.editOutlined,
                      iconColor: Colors.blue,
                      title: context.l10n.featureChatProxyTagAuthoring,
                      subtitle:
                          context.l10n.featureChatProxyTagAuthoringSubtitle,
                      value: useProxyTagsForAuthoring,
                      onChanged: (value) => ref
                          .read(useProxyTagsForAuthoringProvider.notifier)
                          .set(value),
                    ),
                    PrismListRow(
                      leading: Icon(AppIcons.gif, color: Colors.deepPurple),
                      title: Text(context.l10n.featureChatGifSearch),
                      subtitle: Text(gifConsentSubtitle),
                      showChevron: true,
                      onTap: () async {
                        if (!gifAvailable) {
                          await _showSyncRequiredDialog(context);
                          return;
                        }
                        final accepted = await GifConsentDialog.show(context);
                        if (!context.mounted) return;
                        await ref
                            .read(settingsNotifierProvider.notifier)
                            .updateGifConsentState(
                              accepted
                                  ? GifConsentState.enabled
                                  : GifConsentState.declined,
                            );
                      },
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
          if (chatEnabled && speakingAs != null)
            PrismSection(
              title: context.l10n.notificationsChatSection,
              child: PrismGroupedSectionCard(
                child: PrismSwitchRow(
                  icon: AppIcons.markChatUnreadOutlined,
                  iconColor: Colors.blue,
                  title: context.l10n.notificationsBadgeAllMessages,
                  subtitle: isMentionsOnly
                      ? context.l10n.notificationsBadgeMentionsOnly(
                          memberName ?? terms.singularLower,
                        )
                      : context.l10n.notificationsBadgeAllFor(
                          memberName ?? terms.singularLower,
                        ),
                  value: !isMentionsOnly,
                  onChanged: (value) {
                    final newPrefs = Map<String, String>.from(badgePrefs);
                    if (value) {
                      newPrefs.remove(speakingAs);
                    } else {
                      newPrefs[speakingAs] = 'mentions_only';
                    }
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateChatBadgePreferences(newPrefs);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _showSyncRequiredDialog(BuildContext context) async {
  final l10n = context.l10n;
  final goToSetup = await PrismDialog.confirm(
    context: context,
    title: l10n.featureChatGifSearchSyncRequiredDialogTitle,
    message: l10n.featureChatGifSearchSyncRequiredDialogBody,
    cancelLabel: l10n.cancel,
    confirmLabel: l10n.featureChatGifSearchSyncRequiredDialogAction,
  );
  if (goToSetup == true && context.mounted) {
    await context.push(AppRoutePaths.syncSetup);
  }
}
