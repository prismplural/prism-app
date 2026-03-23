import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

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
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Notifications', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            // ── Explanation ──────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'About Notifications',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fronting reminders help you stay aware of who is '
                        'fronting by sending periodic notifications. This can '
                        'be useful for logging switches and maintaining '
                        'awareness throughout the day.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Fronting Reminders Toggle ────────────────
            PrismSwitchRow(
              title: 'Fronting reminders',
              subtitle:
                'Get reminded to log fronting changes',
              value: settings.frontingRemindersEnabled,
              onChanged: (value) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateFrontingReminders(enabled: value);
              },
            ),

            // ── Reminder Interval ────────────────────────
            if (settings.frontingRemindersEnabled) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              PrismListRow(
                title: const Text('Reminder interval'),
                subtitle: const Text('How often to send reminders'),
                trailing: DropdownButton<int>(
                  value: _reminderIntervals
                          .containsKey(settings.frontingReminderIntervalMinutes)
                      ? settings.frontingReminderIntervalMinutes
                      : 60,
                  underline: const SizedBox.shrink(),
                  items: _reminderIntervals.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
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

            // ── Chat Notifications ──────────────────────
            const _ChatBadgeSection(),

            // ── Permission Status ────────────────────────
            const Divider(height: 1, indent: 16, endIndent: 16),
            const _NotificationPermissionTile(),
          ],
        ),
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
        leading: Icon(Icons.error_outline,
            color: Theme.of(context).colorScheme.error),
        title: const Text('Could not check permissions'),
      ),
      data: (granted) {
        if (granted) {
          return PrismListRow(
            leading: Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('Notifications enabled'),
            subtitle: const Text('Permission granted'),
          );
        }

        return PrismListRow(
          leading: Icon(Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Notifications not enabled'),
          subtitle: const Text('Permission required for reminders'),
          trailing: PrismButton(
            label: 'Request',
            onPressed: () async {
              final service =
                  ref.read(frontingNotificationServiceProvider);
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
