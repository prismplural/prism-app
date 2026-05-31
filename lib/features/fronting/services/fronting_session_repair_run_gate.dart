import 'package:shared_preferences/shared_preferences.dart';

/// One-time gate for the automatic open-session repair sweep.
///
/// Mirrors [PkGroupRepairRunGate]: a persisted version key so the repair runs
/// once per device and re-runs only if a future [currentVersion] needs to sweep
/// again (e.g. a new class of corruption is discovered). The on-demand debug
/// button bypasses this gate entirely.
class FrontingSessionRepairRunGate {
  FrontingSessionRepairRunGate(this._preferences);

  /// Bump when a new repair generation must re-sweep already-checked devices.
  static const currentVersion = 1;
  static const checkedVersionKey =
      'fronting_open_session_repair.auto_checked_version';
  static const checkedAtKey = 'fronting_open_session_repair.auto_checked_at';

  final SharedPreferences _preferences;

  bool get shouldRun =>
      _preferences.getInt(checkedVersionKey) != currentVersion;

  Future<void> markCheckedClean(DateTime checkedAt) async {
    await _preferences.setInt(checkedVersionKey, currentVersion);
    await _preferences.setString(checkedAtKey, checkedAt.toIso8601String());
  }

  static Future<FrontingSessionRepairRunGate> load() async {
    final preferences = await SharedPreferences.getInstance();
    return FrontingSessionRepairRunGate(preferences);
  }
}
