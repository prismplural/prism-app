import 'package:shared_preferences/shared_preferences.dart';

class PkGroupRepairRunGate {
  PkGroupRepairRunGate(this._preferences);

  static const currentVersion = 1;
  static const checkedVersionKey = 'pk_group_repair.auto_checked_version';
  static const checkedAtKey = 'pk_group_repair.auto_checked_at';
  static const dirtyKey = 'pk_group_repair.dirty';

  final SharedPreferences _preferences;

  bool get shouldRun {
    return _preferences.getInt(checkedVersionKey) != currentVersion ||
        (_preferences.getBool(dirtyKey) ?? false);
  }

  Future<void> markCheckedClean(DateTime checkedAt) async {
    await _preferences.setInt(checkedVersionKey, currentVersion);
    await _preferences.setString(checkedAtKey, checkedAt.toIso8601String());
    await _preferences.setBool(dirtyKey, false);
  }

  Future<void> markDirty() => _preferences.setBool(dirtyKey, true);

  static Future<PkGroupRepairRunGate> load() async {
    final preferences = await SharedPreferences.getInstance();
    return PkGroupRepairRunGate(preferences);
  }

  static Future<void> markDirtyInDefaultStore() async {
    final gate = await load();
    await gate.markDirty();
  }
}
