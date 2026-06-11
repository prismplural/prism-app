import 'package:shared_preferences/shared_preferences.dart';

/// Device-local set of sleep sessions the user deleted ON PURPOSE after the
/// data-loss fix, recorded at delete time.
///
/// The cross-type-trim bug deleted sleep sessions silently; once it's fixed,
/// every further sleep deletion is intentional. Recording each one as it
/// happens lets recovery exclude them — so the banner never re-pops for a
/// deletion the user made — while bug-era deletions (which predate the fix and
/// were never recorded) stay recoverable. Device-local: a deletion synced from
/// another device isn't pre-excluded here, but the recovery flow is idempotent
/// and converges if that rare case is acted on.
class SleepRecoveryExclusions {
  SleepRecoveryExclusions(this._preferences);

  static const _key = 'sleep_recovery.intentional_delete_ids_v1';

  final SharedPreferences _preferences;

  Set<String> get ids => _preferences.getStringList(_key)?.toSet() ?? const {};

  Future<void> add(String id) async {
    final current = _preferences.getStringList(_key) ?? const [];
    if (current.contains(id)) return;
    await _preferences.setStringList(_key, [...current, id]);
  }

  static Future<SleepRecoveryExclusions> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SleepRecoveryExclusions(preferences);
  }
}
