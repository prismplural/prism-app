import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Reminder interval options in minutes.
const _reminderIntervals = <int, String>{
  15: '15 minutes',
  30: '30 minutes',
  60: '1 hour',
  120: '2 hours',
  240: '4 hours',
  480: '8 hours',
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
      topBar: const PrismTopBar(title: 'Notifications', showBackButton: true),
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
                    title: 'Fronting reminders',
                    subtitle: 'Get reminded to log fronting changes',
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
                      title: const Text('Reminder interval'),
                      subtitle: const Text('How often to send reminders'),
                      trailing: PrismSelect<int>.compact(
                        value:
                            _reminderIntervals.containsKey(
                              frontingReminderInterval,
                            )
                            ? frontingReminderInterval
                            : 60,
                        menuWidth: 180,
                        items: _reminderIntervals.entries
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
              'Fronting reminders send periodic notifications to help you '
              'stay aware of who is fronting. This can be useful for '
              'logging switches and maintaining awareness throughout '
              'the day.',
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
      title: 'Chat Notifications',
      child: PrismSectionCard(
        child: PrismSwitchRow(
          title: 'Badge for all messages',
          subtitle: isMentionsOnly
              ? 'Only @mentions will badge for $memberName'
              : 'All new messages will badge for $memberName',
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
      loading: () => const PrismListRow(
        title: Text('Permission status'),
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
        title: const Text('Could not check permissions'),
      ),
      data: (granted) {
        if (granted) {
          return PrismListRow(
            leading: Icon(
              AppIcons.checkCircle,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Notifications enabled'),
            subtitle: const Text('Permission granted'),
          );
        }

        return PrismListRow(
          leading: Icon(
            AppIcons.warningAmberRounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Notifications not enabled'),
          subtitle: const Text('Permission required for reminders'),
          trailing: PrismButton(
            label: 'Request',
            onPressed: () async {
              final service = ref.read(frontingNotificationServiceProvider);
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
