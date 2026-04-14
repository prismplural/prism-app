import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/fronting_notification_service.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Provides the [FrontingNotificationService] singleton instance.
final frontingNotificationServiceProvider =
    Provider<FrontingNotificationService>((ref) {
  return FrontingNotificationService(
    ref.watch(localNotificationServiceProvider),
  );
});

/// Checks whether notification permissions are currently granted.
final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(localNotificationServiceProvider);
  await service.initialize();
  return service.isPermissionGranted();
});

/// Watches fronting reminder settings + active sessions and schedules/cancels
/// the periodic fronting reminder notification accordingly.
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
    final sessions = ref.read(activeSessionsProvider).value;

    if (!enabled) {
      service.cancelFrontingReminder().catchError((e) {
        debugPrint('Cancel fronting reminder failed (non-fatal): $e');
      });
      return;
    }

    // Resolve current fronter name from first active session (best-effort).
    final firstSession =
        sessions != null && sessions.isNotEmpty ? sessions.first : null;
    final memberId = firstSession?.memberId;
    final fronterName = memberId != null
        ? ref.read(memberByIdProvider(memberId)).value?.name
        : null;

    service
        .scheduleFrontingReminder(
          interval: Duration(minutes: intervalMinutes),
          currentFronterName: fronterName ?? 'your system',
        )
        .catchError((e) {
          debugPrint('Schedule fronting reminder failed (non-fatal): $e');
        });
  }

  ref.listen(frontingRemindersEnabledProvider, (_, _) => update());
  ref.listen(frontingReminderIntervalProvider, (_, _) => update());
  ref.listen(activeSessionsProvider, (_, _) => update());

  // Schedule on startup if already enabled.
  update();
});
