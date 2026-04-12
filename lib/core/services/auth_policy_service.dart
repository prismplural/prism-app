import 'package:shared_preferences/shared_preferences.dart';

/// Tracks periodic PIN verification and recovery-phrase reminder schedules.
///
/// All timestamps are stored in [SharedPreferences] as milliseconds since
/// epoch so they survive app restarts but are cleared on reinstall (unlike
/// the iOS Keychain).
class AuthPolicyService {
  static const _pinVerifiedKey = 'prism.last_pin_verified';
  static const _reminderKey = 'prism.last_recovery_reminder';
  static const _pinPeriodDays = 30;
  static const _reminderPeriodDays = 30;

  // ---------------------------------------------------------------------------
  // PIN verification schedule
  // ---------------------------------------------------------------------------

  /// Returns true if the user has not verified their PIN within the last
  /// [_pinPeriodDays] days, or has never verified it.
  Future<bool> isPinVerificationDue() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_pinVerifiedKey);
    if (ts == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(last).inDays >= _pinPeriodDays;
  }

  /// Records that the user has just successfully verified their PIN.
  Future<void> recordPinVerified() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pinVerifiedKey, DateTime.now().millisecondsSinceEpoch);
  }

  // ---------------------------------------------------------------------------
  // Recovery-phrase reminder schedule
  // ---------------------------------------------------------------------------

  /// Returns true if the user has not dismissed a backup reminder within the
  /// last [_reminderPeriodDays] days, or has never seen one.
  Future<bool> isBackupReminderDue() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_reminderKey);
    if (ts == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(last).inDays >= _reminderPeriodDays;
  }

  /// Records that the user has just dismissed the backup reminder.
  Future<void> recordReminderDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderKey, DateTime.now().millisecondsSinceEpoch);
  }
}
