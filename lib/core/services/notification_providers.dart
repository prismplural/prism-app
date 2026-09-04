import 'package:flutter/foundation.dart' show PlatformDispatcher, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/fronting_notification_service.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';

/// Provides the [FrontingNotificationService] singleton instance.
final frontingNotificationServiceProvider =
    Provider<FrontingNotificationService>((ref) {
      final locale =
          ref.watch(localeOverrideProvider) ??
          PlatformDispatcher.instance.locale;
      final l10n = appLocalizationsForLocale(locale);
      final frontingTerms = resolveFrontingTerms(
        l10n,
        ref.watch(frontingTermsSettingProvider),
      );
      return FrontingNotificationService(
        ref.watch(localNotificationServiceProvider),
        reminderTitle: frontingTerms.reminderLabel,
        reminderBody: l10n.notificationsScheduledReminderBody(
          frontingTerms.currentQuestionNow,
        ),
        reminderChannelName: l10n.notificationsReminderChannelName,
        reminderChannelDescription:
            l10n.notificationsReminderChannelDescription,
      );
    });

/// Checks whether notification permissions are currently granted.
final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(localNotificationServiceProvider);
  await service.initialize();
  return service.isPermissionGranted();
});

/// Watches fronting reminder settings and schedules/cancels the periodic
/// fronting reminder notification accordingly.
///
/// Previously this was only wired inside [FrontingNotificationService] CRUD
/// callers; this provider ensures the reminder fires even when settings change
/// without a matching mutation (e.g., on first app open after enabling the
/// setting on another device).
final frontingReminderListenerProvider = Provider<void>((ref) {
  final service = ref.watch(frontingNotificationServiceProvider);

  void update() {
    final enabled = ref.read(frontingRemindersEnabledProvider);
    final intervalMinutes = ref.read(frontingReminderIntervalProvider);

    if (!enabled) {
      service.cancelFrontingReminder().catchError((e) {
        debugPrint('Cancel fronting reminder failed (non-fatal): $e');
      });
      return;
    }

    service
        .scheduleFrontingReminder(interval: Duration(minutes: intervalMinutes))
        .catchError((e) {
          debugPrint('Schedule fronting reminder failed (non-fatal): $e');
        });
  }

  ref.listen(frontingRemindersEnabledProvider, (_, _) => update());
  ref.listen(frontingReminderIntervalProvider, (_, _) => update());

  // Schedule on startup if already enabled.
  update();
});
