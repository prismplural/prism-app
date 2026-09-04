import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
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
    final frontingTerms = watchFrontingTerms(context, ref);
    final theme = Theme.of(context);

    final hasPermission = permissionAsync.value ?? false;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.notificationsTitle,
        showBackButton: true,
      ),
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
                    title: frontingTerms.reminderLabel,
                    subtitle: context.l10n
                        .notificationsFrontingRemindersSubtitle(
                          frontingTerms.logChangeReminderAction,
                        ),
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
                      title: Text(
                        context.l10n.notificationsReminderIntervalTitle,
                      ),
                      subtitle: Text(
                        context.l10n.notificationsReminderIntervalSubtitle,
                      ),
                      trailing: PrismSelect<int>.compact(
                        value:
                            _reminderIntervals(
                              context,
                            ).containsKey(frontingReminderInterval)
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
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    const _FrontingReminderSuppressRow(),
                  ],
                ],
              ),
            ),
          ),

          // ── About (reduced visual weight) ──────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              context.l10n.notificationsAboutText(
                frontingTerms.reminderLabel,
                frontingTerms.currentQuestion,
                frontingTerms.logChangeReminderAction,
              ),
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

/// Picked when the user chooses "Custom…"; intercepted to open the dialog.
const int _kSuppressCustomSentinel = -1;
const List<int> _kSuppressPresets = [0, 5, 10, 15];
const int _kSuppressMin = 1;
const int _kSuppressMax = 60;

class _FrontingReminderSuppressRow extends ConsumerWidget {
  const _FrontingReminderSuppressRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(frontingReminderSuppressMinutesProvider);
    final frontingTerms = watchFrontingTerms(context, ref);
    final value = asyncValue.value ?? 5;
    final l10n = context.l10n;

    String labelFor(int v) => v == 0
        ? l10n.notificationsSuppressOff
        : l10n.notificationsSuppressMinutes(v);

    final items = <PrismSelectItem<int>>[
      for (final preset in _kSuppressPresets)
        PrismSelectItem(value: preset, label: labelFor(preset)),
      // Surface a non-preset value so the field shows the user's choice.
      if (!_kSuppressPresets.contains(value))
        PrismSelectItem(
          value: value,
          label: l10n.notificationsSuppressCustomLabel(value),
        ),
      PrismSelectItem(
        value: _kSuppressCustomSentinel,
        label: l10n.notificationsSuppressCustomOption,
      ),
    ];

    return PrismListRow(
      title: Text(l10n.notificationsSuppressIfRecentTitle),
      subtitle: Text(
        l10n.notificationsSuppressIfRecentSubtitle(
          frontingTerms.changeSingular,
        ),
      ),
      trailing: PrismSelect<int>.compact(
        value: value,
        menuWidth: 200,
        items: items,
        onChanged: (selected) async {
          if (selected == null) return;
          if (selected == _kSuppressCustomSentinel) {
            final custom = await _promptForCustomMinutes(context, value);
            if (custom != null) {
              await ref
                  .read(frontingReminderSuppressMinutesProvider.notifier)
                  .set(custom);
            }
            return;
          }
          await ref
              .read(frontingReminderSuppressMinutesProvider.notifier)
              .set(selected);
        },
      ),
    );
  }

  Future<int?> _promptForCustomMinutes(
    BuildContext context,
    int initial,
  ) async {
    final l10n = context.l10n;
    var input = initial >= _kSuppressMin && initial <= _kSuppressMax
        ? initial.toString()
        : '';
    int? parsedInput() {
      final parsed = int.tryParse(input);
      if (parsed == null || parsed < _kSuppressMin || parsed > _kSuppressMax) {
        return null;
      }
      return parsed;
    }

    return PrismDialog.show<int>(
      context: context,
      title: l10n.notificationsSuppressCustomDialogTitle,
      actions: [
        PrismButton(
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          tone: PrismButtonTone.outlined,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        PrismButton(
          label: MaterialLocalizations.of(context).okButtonLabel,
          tone: PrismButtonTone.filled,
          onPressed: () {
            final parsed = parsedInput();
            if (parsed != null) {
              Navigator.of(context, rootNavigator: true).pop(parsed);
            }
          },
        ),
      ],
      builder: (dialogContext) {
        return TextFormField(
          initialValue: input,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            suffixText: l10n.notificationsSuppressCustomSuffix,
            helperText: l10n.notificationsSuppressCustomDialogHelper,
          ),
          onChanged: (value) => input = value,
          onFieldSubmitted: (_) {
            final parsed = parsedInput();
            if (parsed != null) {
              Navigator.of(dialogContext).pop(parsed);
            }
          },
        );
      },
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
        trailing: PrismSpinner(
          color: Theme.of(context).colorScheme.primary,
          size: 16,
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
