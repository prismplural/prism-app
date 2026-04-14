import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Reminder interval options in minutes — built dynamically with l10n.
Map<int, String> _reminderIntervals(BuildContext context) => {
  15: context.l10n.notificationsInterval15m,
  30: context.l10n.notificationsInterval30m,
  60: context.l10n.notificationsInterval1h,
  120: context.l10n.notificationsInterval2h,
  240: context.l10n.notificationsInterval4h,
  480: context.l10n.notificationsInterval8h,
};

/// Screen for configuring fronting reminder notifications.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frontingRemindersEnabled = ref.watch(
      frontingRemindersEnabledProvider,
    );
    final frontingReminderInterval = ref.watch(
      frontingReminderIntervalProvider,
    );
    final permissionAsync = ref.watch(notificationPermissionProvider);
    final theme = Theme.of(context);

    final hasPermission = permissionAsync.value ?? false;

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.notificationsTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          // ── Permission Status (top) ──────────────────
          const _NotificationPermissionTile(),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Fronting Reminders (grayed out without permission) ──
          IgnorePointer(
            ignoring: !hasPermission,
            child: Opacity(
              opacity: hasPermission ? 1.0 : 0.4,
              child: Column(
                children: [
                  PrismSwitchRow(
                    title: context.l10n.notificationsFrontingRemindersTitle,
                    subtitle: context.l10n.notificationsFrontingRemindersSubtitle,
                    value: frontingRemindersEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateFrontingReminders(enabled: value);
                    },
                  ),
                  if (frontingRemindersEnabled) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    PrismListRow(
                      title: Text(context.l10n.notificationsReminderIntervalTitle),
                      subtitle: Text(context.l10n.notificationsReminderIntervalSubtitle),
                      trailing: PrismSelect<int>.compact(
                        value:
                            _reminderIntervals(context).containsKey(
                              frontingReminderInterval,
                            )
                            ? frontingReminderInterval
                            : 60,
                        menuWidth: 180,
                        items: _reminderIntervals(context).entries
                            .map(
                              (e) =>
                                  PrismSelectItem(value: e.key, label: e.value),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            ref
                                .read(settingsNotifierProvider.notifier)
                                .updateFrontingReminders(
                                  enabled: true,
                                  intervalMinutes: value,
                                );
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Chat Notifications (always enabled) ────
          const _ChatBadgeSection(),

          // ── About (reduced visual weight) ──────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              context.l10n.notificationsAboutText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (Theme.of(context).platform == TargetPlatform.android)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                context.l10n.notificationsAndroidFootnote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chat badge preference toggle for the currently speaking member.
class _ChatBadgeSection extends ConsumerWidget {
  const _ChatBadgeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speakingAs = ref.watch(speakingAsProvider);
    if (speakingAs == null) return const SizedBox.shrink();

    final badgePrefs = ref.watch(chatBadgePreferencesProvider);
    final isMentionsOnly = badgePrefs[speakingAs] == 'mentions_only';
    final memberAsync = ref.watch(memberByIdProvider(speakingAs));
    final memberName =
        memberAsync.whenOrNull(data: (m) => m?.name) ?? 'current member';

    return PrismSection(
      title: context.l10n.notificationsChatSection,
      child: PrismSectionCard(
        child: PrismSwitchRow(
          title: context.l10n.notificationsBadgeAllMessages,
          subtitle: isMentionsOnly
              ? context.l10n.notificationsBadgeMentionsOnly(memberName)
              : context.l10n.notificationsBadgeAllFor(memberName),
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
    );
  }
}

/// Displays notification permission status and a request button if needed.
class _NotificationPermissionTile extends ConsumerWidget {
  const _NotificationPermissionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionAsync = ref.watch(notificationPermissionProvider);

    return permissionAsync.when(
      loading: () => PrismListRow(
        title: Text(context.l10n.notificationsPermissionStatus),
        trailing: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => PrismListRow(
        leading: Icon(
          AppIcons.errorOutline,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text(context.l10n.notificationsCouldNotCheck),
      ),
      data: (granted) {
        if (granted) {
          return PrismListRow(
            leading: Icon(
              AppIcons.checkCircle,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(context.l10n.notificationsEnabled),
            subtitle: Text(context.l10n.notificationsPermissionGranted),
          );
        }

        return PrismListRow(
          leading: Icon(
            AppIcons.warningAmberRounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(context.l10n.notificationsNotEnabled),
          subtitle: Text(context.l10n.notificationsPermissionRequired),
          trailing: PrismButton(
            label: context.l10n.notificationsRequest,
            onPressed: () async {
              final service = ref.read(localNotificationServiceProvider);
              await service.requestPermission();
              ref.invalidate(notificationPermissionProvider);
            },
            tone: PrismButtonTone.filled,
            density: PrismControlDensity.compact,
          ),
        );
      },
    );
  }
}
