import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/utils/enum_decoder.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SleepQuality;
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;

class SystemSettingsMapper {
  SystemSettingsMapper._();

  static domain.SystemSettings toDomain(SystemSettingsData row) {
    return domain.SystemSettings(
      systemName: row.systemName,
      sharingId: row.sharingId,
      showQuickFront: row.showQuickFront,
      accentColorHex: row.accentColorHex,
      perMemberAccentColors: row.perMemberAccentColors,
      terminology: domain.SystemTerminology.values[row.terminology],
      customTerminology: row.customTerminology,
      customPluralTerminology: row.customPluralTerminology,
      terminologyUseEnglish: row.terminologyUseEnglish,
      frontingRemindersEnabled: row.frontingRemindersEnabled,
      frontingReminderIntervalMinutes: row.frontingReminderIntervalMinutes,
      themeMode: domain.AppThemeMode.values[row.themeMode],
      themeBrightness: domain.ThemeBrightness.values[row.themeBrightness],
      themeStyle: domain.ThemeStyle.values[row.themeStyle],
      cornerStyle: domain.CornerStyle.values[row.themeCornerStyle],
      chatEnabled: row.chatEnabled,
      pollsEnabled: row.pollsEnabled,
      habitsEnabled: row.habitsEnabled,
      sleepTrackingEnabled: row.sleepTrackingEnabled,
      gifSearchEnabled: row.gifSearchEnabled,
      voiceNotesEnabled: row.voiceNotesEnabled,
      sleepSuggestionEnabled: row.sleepSuggestionEnabled,
      sleepSuggestionHour: row.sleepSuggestionHour,
      sleepSuggestionMinute: row.sleepSuggestionMinute,
      wakeSuggestionEnabled: row.wakeSuggestionEnabled,
      wakeSuggestionAfterHours: row.wakeSuggestionAfterHours,
      quickSwitchThresholdSeconds: row.quickSwitchThresholdSeconds,
      identityGeneration: row.identityGeneration,
      chatLogsFront: row.chatLogsFront,
      hasCompletedOnboarding: row.hasCompletedOnboarding,
      syncThemeEnabled: row.syncThemeEnabled,
      habitsBadgeEnabled: row.habitsBadgeEnabled,
      timingMode: domain.FrontingTimingMode.values[row.timingMode],
      notesEnabled: row.notesEnabled,
      previousAccentColorHex: row.previousAccentColorHex,
      systemDescription: row.systemDescription,
      systemColor: row.systemColor,
      pkGroupSyncV2Enabled: row.pkGroupSyncV2Enabled,
      systemTag: row.systemTag,
      systemAvatarData: row.systemAvatarData != null
          ? Uint8List.fromList(row.systemAvatarData!)
          : null,
      remindersEnabled: row.remindersEnabled,
      localeOverride: row.localeOverride,
      gifConsentState: domain.GifConsentState.values[row.gifConsentState],
      fontScale: row.fontScale,
      fontFamily: domain.FontFamily.values[row.fontFamily],
      pinLockEnabled: row.pinLockEnabled,
      biometricLockEnabled: row.biometricLockEnabled,
      autoLockDelaySeconds: row.autoLockDelaySeconds,
      displayFontInAppBar: row.displayFontInAppBar,
      navBarItems: _decodeNavBarItems(row.navBarItems),
      navBarOverflowItems: _decodeNavBarItems(row.navBarOverflowItems),
      syncNavigationEnabled: row.syncNavigationEnabled,
      chatBadgePreferences: decodeBadgePrefs(row.chatBadgePreferences),
      defaultSleepQuality: row.defaultSleepQuality != null
          ? SleepQuality.values.byName(row.defaultSleepQuality!)
          : null,
      frontingListViewMode: enumByIndex(
        row.frontingListViewMode,
        domain.FrontingListViewMode.values,
        domain.FrontingListViewMode.combinedPeriods,
      ),
      addFrontDefaultBehavior: enumByIndex(
        row.addFrontDefaultBehavior,
        domain.FrontStartBehavior.values,
        domain.FrontStartBehavior.additive,
      ),
      quickFrontDefaultBehavior: enumByIndex(
        row.quickFrontDefaultBehavior,
        domain.FrontStartBehavior.values,
        domain.FrontStartBehavior.additive,
      ),
      boardsEnabled: row.boardsEnabled,
      spBoardsBackfilledAt: row.spBoardsBackfilledAt,
    );
  }

  static SystemSettingsTableCompanion toCompanion(domain.SystemSettings model) {
    return SystemSettingsTableCompanion(
      id: const Value('singleton'),
      systemName: Value(model.systemName),
      sharingId: Value(model.sharingId),
      showQuickFront: Value(model.showQuickFront),
      accentColorHex: Value(model.accentColorHex),
      perMemberAccentColors: Value(model.perMemberAccentColors),
      terminology: Value(model.terminology.index),
      customTerminology: Value(model.customTerminology),
      customPluralTerminology: Value(model.customPluralTerminology),
      terminologyUseEnglish: Value(model.terminologyUseEnglish),
      frontingRemindersEnabled: Value(model.frontingRemindersEnabled),
      frontingReminderIntervalMinutes: Value(
        model.frontingReminderIntervalMinutes,
      ),
      themeMode: Value(model.themeMode.index),
      themeBrightness: Value(model.themeBrightness.index),
      themeStyle: Value(model.themeStyle.index),
      themeCornerStyle: Value(model.cornerStyle.index),
      chatEnabled: Value(model.chatEnabled),
      pollsEnabled: Value(model.pollsEnabled),
      habitsEnabled: Value(model.habitsEnabled),
      sleepTrackingEnabled: Value(model.sleepTrackingEnabled),
      gifSearchEnabled: Value(model.gifSearchEnabled),
      voiceNotesEnabled: Value(model.voiceNotesEnabled),
      sleepSuggestionEnabled: Value(model.sleepSuggestionEnabled),
      sleepSuggestionHour: Value(model.sleepSuggestionHour),
      sleepSuggestionMinute: Value(model.sleepSuggestionMinute),
      wakeSuggestionEnabled: Value(model.wakeSuggestionEnabled),
      wakeSuggestionAfterHours: Value(model.wakeSuggestionAfterHours),
      quickSwitchThresholdSeconds: Value(model.quickSwitchThresholdSeconds),
      identityGeneration: Value(model.identityGeneration),
      chatLogsFront: Value(model.chatLogsFront),
      hasCompletedOnboarding: Value(model.hasCompletedOnboarding),
      syncThemeEnabled: Value(model.syncThemeEnabled),
      habitsBadgeEnabled: Value(model.habitsBadgeEnabled),
      timingMode: Value(model.timingMode.index),
      notesEnabled: Value(model.notesEnabled),
      previousAccentColorHex: Value(model.previousAccentColorHex),
      systemDescription: Value(model.systemDescription),
      systemColor: Value(model.systemColor),
      pkGroupSyncV2Enabled: Value(model.pkGroupSyncV2Enabled),
      systemTag: Value(model.systemTag),
      systemAvatarData: Value(model.systemAvatarData),
      remindersEnabled: Value(model.remindersEnabled),
      localeOverride: Value(model.localeOverride),
      gifConsentState: Value(model.gifConsentState.index),
      fontScale: Value(model.fontScale),
      fontFamily: Value(model.fontFamily.index),
      pinLockEnabled: Value(model.pinLockEnabled),
      biometricLockEnabled: Value(model.biometricLockEnabled),
      autoLockDelaySeconds: Value(model.autoLockDelaySeconds),
      displayFontInAppBar: Value(model.displayFontInAppBar),
      navBarItems: Value(encodeNavBarItems(model.navBarItems)),
      navBarOverflowItems: Value(encodeNavBarItems(model.navBarOverflowItems)),
      syncNavigationEnabled: Value(model.syncNavigationEnabled),
      chatBadgePreferences: Value(encodeBadgePrefs(model.chatBadgePreferences)),
      defaultSleepQuality: Value(model.defaultSleepQuality?.name),
      frontingListViewMode: Value(model.frontingListViewMode.index),
      addFrontDefaultBehavior: Value(model.addFrontDefaultBehavior.index),
      quickFrontDefaultBehavior: Value(model.quickFrontDefaultBehavior.index),
      boardsEnabled: Value(model.boardsEnabled),
      spBoardsBackfilledAt: Value(model.spBoardsBackfilledAt),
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
