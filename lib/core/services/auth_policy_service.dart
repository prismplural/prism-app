import 'package:shared_preferences/shared_preferences.dart';

/// Tracks periodic PIN verification schedule.
///
/// All timestamps are stored in [SharedPreferences] as milliseconds since
/// epoch so they survive app restarts but are cleared on reinstall (unlike
/// the iOS Keychain).
class AuthPolicyService {
  static const _pinVerifiedKey = 'prism.last_pin_verified';
  static const _pinPeriodDays = 30;

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
    final now = DateTime.now();
    // Future timestamp = clock rollback or tampered prefs → treat as missing.
    if (last.isAfter(now)) return true;
    return now.difference(last).inDays >= _pinPeriodDays;
  }

  /// Records that the user has just successfully verified their PIN.
  Future<void> recordPinVerified() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pinVerifiedKey, DateTime.now().millisecondsSinceEpoch);
  }

}
