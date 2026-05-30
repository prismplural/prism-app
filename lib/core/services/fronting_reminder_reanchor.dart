import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/notification_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Re-anchors the periodic fronting reminder so its next fire is at
/// least `now + suppressWindow`. Call after any path that creates a
/// live fronting session; no-op when reminders are off or the suppress
/// preference is 0.
///
/// Reads the suppress value through the repository rather than
/// [frontingReminderSuppressMinutesProvider] so an early front log
/// (before the AsyncNotifier's first build resolves) still re-anchors.
Future<void> maybeReanchorFrontingReminder(Ref ref) async {
  final remindersEnabled = ref.read(frontingRemindersEnabledProvider);
  if (!remindersEnabled) return;
  final repo = ref.read(appPreferenceRepositoryProvider);
  final suppress = await repo.get(frontingReminderSuppressMinutesPreference);
  if (suppress <= 0) return;
  final intervalMinutes = ref.read(frontingReminderIntervalProvider);
  final nextReminderMinutes = intervalMinutes < suppress
      ? suppress
      : intervalMinutes;
  final service = ref.read(frontingNotificationServiceProvider);
  await service.scheduleFrontingReminder(
    interval: Duration(minutes: nextReminderMinutes),
  );
}

/// Fire-and-forget wrapper around [maybeReanchorFrontingReminder] so a
/// notification failure doesn't bubble up through the user-facing
/// mutation that just succeeded.
void scheduleFrontingReminderReanchorBestEffort(Ref ref) {
  unawaited(
    maybeReanchorFrontingReminder(ref).catchError((Object error) {
      debugPrint('Fronting reminder re-anchor failed (non-fatal): $error');
    }),
  );
}
