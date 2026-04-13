import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';

/// SharedPreferences key storing whether the user has dismissed the backup
/// reminder.  Written by [recordReminderDismissed].
const _backupReminderDismissedKey = 'prism.backup_reminder_dismissed';

/// Returns `true` when the backup reminder banner should be shown.
///
/// The banner is shown when:
/// - a PIN has been set (encryption is active), AND
/// - the user has not yet dismissed the reminder.
///
/// Call [recordReminderDismissed] (via [AuthPolicyService]) to mark it
/// dismissed; then invalidate this provider to hide the banner.
final backupReminderDueProvider = FutureProvider<bool>((ref) async {
  // Only show when a PIN is set.
  final isPinSet = await ref.watch(isPinSetProvider.future);
  if (!isPinSet) return false;

  final prefs = await SharedPreferences.getInstance();
  final dismissed = prefs.getBool(_backupReminderDismissedKey) ?? false;
  return !dismissed;
});

/// Marks the backup reminder as dismissed (persisted across restarts).
Future<void> recordReminderDismissed() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_backupReminderDismissedKey, true);
}
