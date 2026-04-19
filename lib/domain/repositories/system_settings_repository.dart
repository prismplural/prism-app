import 'dart:typed_data';

import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SleepQuality;
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;

abstract class SystemSettingsRepository {
  Future<domain.SystemSettings> getSettings();
  Stream<domain.SystemSettings> watchSettings();
  Future<void> updateSettings(domain.SystemSettings settings);

  // --- Field-level updates ---

  // Text fields
  Future<void> updateSystemName(String? name);
  Future<void> updateSharingId(String? sharingId);
  Future<void> updateAccentColorHex(String hex);
  Future<void> updateCustomTerminology(String? value);
  Future<void> updateCustomPluralTerminology(String? value);
  Future<void> updatePreviousAccentColorHex(String value);

  // Bool fields
  Future<void> updateShowQuickFront(bool value);
  Future<void> updatePerMemberAccentColors(bool value);
  Future<void> updateFrontingRemindersEnabled(bool value);
  Future<void> updateChatEnabled(bool value);
  Future<void> updatePollsEnabled(bool value);
  Future<void> updateHabitsEnabled(bool value);
  Future<void> updateSleepTrackingEnabled(bool value);
  Future<void> updateGifSearchEnabled(bool value);
  Future<void> updateVoiceNotesEnabled(bool value);
  Future<void> updateSleepSuggestionEnabled(bool value);
  Future<void> updateSleepSuggestionTime(int hour, int minute);
  Future<void> updateWakeSuggestionEnabled(bool value);
  Future<void> updateWakeSuggestionAfterHours(double hours);
  Future<void> updateLocaleOverride(String? value);
  Future<void> updateChatLogsFront(bool value);
  Future<void> updateSyncThemeEnabled(bool value);
  Future<void> updateHasCompletedOnboarding(bool value);

  // Enum fields
  Future<void> updateTerminology(domain.SystemTerminology value);
  Future<void> updateThemeMode(domain.AppThemeMode value);
  Future<void> updateThemeBrightness(domain.ThemeBrightness value);
  Future<void> updateThemeStyle(domain.ThemeStyle value);
  Future<void> updateCornerStyle(domain.CornerStyle value);
  Future<void> updateTimingMode(domain.FrontingTimingMode value);

  // Int fields
  Future<void> updateFrontingReminderIntervalMinutes(int value);
  Future<void> updateQuickSwitchThresholdSeconds(int value);
  Future<void> updateIdentityGeneration(int value);

  // Multi-field updates
  Future<void> updateTerminologyFields({
    required domain.SystemTerminology terminology,
    String? customTerminology,
    String? customPluralTerminology,
    bool useEnglish = false,
  });
  Future<void> updateFrontingReminders({
    required bool enabled,
    required int intervalMinutes,
  });
  Future<void> updateFeatureToggles({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
    bool? gifSearchEnabled,
  });
  Future<void> updateHabitsBadgeEnabled(bool value);
  Future<void> updateNotesEnabled(bool value);
  Future<void> updateRemindersEnabled(bool value);

  // Phase 3: Synced settings
  Future<void> updateSystemDescription(String? value);
  Future<void> updateSystemColor(String? colorHex);
  // Plan 04: PluralKit system tag.
  Future<void> updateSystemTag(String? value);
  Future<void> updateSystemAvatarData(Uint8List? value);

  // Phase 3: Device-local settings
  Future<void> updateGifConsentState(domain.GifConsentState value);
  Future<void> updateFontScale(double value);
  Future<void> updateFontFamily(domain.FontFamily value);
  Future<void> updateDisplayFontInAppBar(bool value);
  Future<void> updatePinLockEnabled(bool value);
  Future<void> updateBiometricLockEnabled(bool value);
  Future<void> updateAutoLockDelaySeconds(int value);

  // Device-local nav bar configuration
  Future<void> updateNavBarItems(List<String> items);
  Future<void> updateNavBarOverflowItems(List<String> items);
  Future<void> updateSyncNavigationEnabled(bool value);
  Future<void> updateChatBadgePreferences(Map<String, String> prefs);

  // Device-local sleep quality default
  Future<void> updateDefaultSleepQuality(SleepQuality? value);
}
