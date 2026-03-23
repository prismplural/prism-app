import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';

class SystemSettingsMapper {
  SystemSettingsMapper._();

  static domain.SystemSettings toDomain(SystemSettingsData row) {
    return domain.SystemSettings(
      systemName: row.systemName,
      showQuickFront: row.showQuickFront,
      accentColorHex: row.accentColorHex,
      perMemberAccentColors: row.perMemberAccentColors,
      terminology: domain.SystemTerminology.values[row.terminology],
      customTerminology: row.customTerminology,
      customPluralTerminology: row.customPluralTerminology,
      frontingRemindersEnabled: row.frontingRemindersEnabled,
      frontingReminderIntervalMinutes: row.frontingReminderIntervalMinutes,
      themeMode: domain.AppThemeMode.values[row.themeMode],
      themeBrightness: domain.ThemeBrightness.values[row.themeBrightness],
      themeStyle: domain.ThemeStyle.values[row.themeStyle],
      chatEnabled: row.chatEnabled,
      pollsEnabled: row.pollsEnabled,
      habitsEnabled: row.habitsEnabled,
      sleepTrackingEnabled: row.sleepTrackingEnabled,
      quickSwitchThresholdSeconds: row.quickSwitchThresholdSeconds,
      chatLogsFront: row.chatLogsFront,
      hasCompletedOnboarding: row.hasCompletedOnboarding,
      syncThemeEnabled: row.syncThemeEnabled,
      habitsBadgeEnabled: row.habitsBadgeEnabled,
      timingMode: FrontingTimingMode.values[row.timingMode],
      notesEnabled: row.notesEnabled,
      previousAccentColorHex: row.previousAccentColorHex,
      systemDescription: row.systemDescription,
      systemAvatarData:
          row.systemAvatarData != null ? Uint8List.fromList(row.systemAvatarData!) : null,
      remindersEnabled: row.remindersEnabled,
      fontScale: row.fontScale,
      fontFamily: domain.FontFamily.values[row.fontFamily],
      pinLockEnabled: row.pinLockEnabled,
      biometricLockEnabled: row.biometricLockEnabled,
      autoLockDelaySeconds: row.autoLockDelaySeconds,
      navBarItems: _decodeNavBarItems(row.navBarItems),
      navBarOverflowItems: _decodeNavBarItems(row.navBarOverflowItems),
      syncNavigationEnabled: row.syncNavigationEnabled,
      chatBadgePreferences: decodeBadgePrefs(row.chatBadgePreferences),
    );
  }

  static SystemSettingsTableCompanion toCompanion(
      domain.SystemSettings model) {
    return SystemSettingsTableCompanion(
      id: const Value('singleton'),
      systemName: Value(model.systemName),
      showQuickFront: Value(model.showQuickFront),
      accentColorHex: Value(model.accentColorHex),
      perMemberAccentColors: Value(model.perMemberAccentColors),
      terminology: Value(model.terminology.index),
      customTerminology: Value(model.customTerminology),
      customPluralTerminology: Value(model.customPluralTerminology),
      frontingRemindersEnabled: Value(model.frontingRemindersEnabled),
      frontingReminderIntervalMinutes:
          Value(model.frontingReminderIntervalMinutes),
      themeMode: Value(model.themeMode.index),
      themeBrightness: Value(model.themeBrightness.index),
      themeStyle: Value(model.themeStyle.index),
      chatEnabled: Value(model.chatEnabled),
      pollsEnabled: Value(model.pollsEnabled),
      habitsEnabled: Value(model.habitsEnabled),
      sleepTrackingEnabled: Value(model.sleepTrackingEnabled),
      quickSwitchThresholdSeconds: Value(model.quickSwitchThresholdSeconds),
      chatLogsFront: Value(model.chatLogsFront),
      hasCompletedOnboarding: Value(model.hasCompletedOnboarding),
      syncThemeEnabled: Value(model.syncThemeEnabled),
      habitsBadgeEnabled: Value(model.habitsBadgeEnabled),
      timingMode: Value(model.timingMode.index),
      notesEnabled: Value(model.notesEnabled),
      previousAccentColorHex: Value(model.previousAccentColorHex),
      systemDescription: Value(model.systemDescription),
      systemAvatarData: Value(model.systemAvatarData),
      remindersEnabled: Value(model.remindersEnabled),
      fontScale: Value(model.fontScale),
      fontFamily: Value(model.fontFamily.index),
      pinLockEnabled: Value(model.pinLockEnabled),
      biometricLockEnabled: Value(model.biometricLockEnabled),
      autoLockDelaySeconds: Value(model.autoLockDelaySeconds),
      navBarItems: Value(encodeNavBarItems(model.navBarItems)),
      navBarOverflowItems: Value(encodeNavBarItems(model.navBarOverflowItems)),
      syncNavigationEnabled: Value(model.syncNavigationEnabled),
      chatBadgePreferences: Value(encodeBadgePrefs(model.chatBadgePreferences)),
    );
  }

  static List<String> _decodeNavBarItems(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return List<String>.from(decoded);
    } catch (_) {}
    return const [];
  }

  static String encodeNavBarItems(List<String> items) {
    if (items.isEmpty) return '';
    return jsonEncode(items);
  }

  static Map<String, String> decodeBadgePrefs(String raw) {
    if (raw.isEmpty || raw == '{}') return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, String>.from(decoded);
    } catch (_) {}
    return const {};
  }

  static String encodeBadgePrefs(Map<String, String> prefs) {
    if (prefs.isEmpty) return '{}';
    return jsonEncode(prefs);
  }
}
