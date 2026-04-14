import 'dart:convert';
import 'dart:typed_data';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/data/mappers/system_settings_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/system_settings.dart' as domain;
import 'package:prism_plurality/domain/repositories/system_settings_repository.dart';

class DriftSystemSettingsRepository
    with SyncRecordMixin
    implements SystemSettingsRepository {
  final SystemSettingsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'system_settings';
  static const _settingsEntityId = 'singleton';

  DriftSystemSettingsRepository(this._dao, this._syncHandle);

  @override
  Future<domain.SystemSettings> getSettings() async {
    final row = await _dao.getSettings();
    return SystemSettingsMapper.toDomain(row);
  }

  @override
  Stream<domain.SystemSettings> watchSettings() {
    return _dao.watchSettings().map(SystemSettingsMapper.toDomain);
  }

  @override
  Future<void> updateSettings(domain.SystemSettings settings) async {
    final companion = SystemSettingsMapper.toCompanion(settings);
    await _dao.upsertSettings(companion);
    await syncRecordUpdate(
      _table,
      _settingsEntityId,
      _settingsFields(settings),
    );
  }

  // --- Field-level updates ---

  // Text fields

  @override
  Future<void> updateSystemName(String? name) async {
    await _dao.updateSystemName(name);
    await _syncField('system_name', name);
  }

  @override
  Future<void> updateSharingId(String? sharingId) async {
    await _dao.updateSharingId(sharingId);
    await _syncField('sharing_id', sharingId);
  }

  @override
  Future<void> updateAccentColorHex(String hex) async {
    await _dao.updateAccentColorHex(hex);
    await _syncFieldIfThemeEnabled('accent_color_hex', hex);
  }

  @override
  Future<void> updateCustomTerminology(String? value) async {
    await _dao.updateCustomTerminology(value);
    await _syncField('custom_terminology', value);
  }

  @override
  Future<void> updateCustomPluralTerminology(String? value) async {
    await _dao.updateCustomPluralTerminology(value);
    await _syncField('custom_plural_terminology', value);
  }

  @override
  Future<void> updatePreviousAccentColorHex(String value) async {
    await _dao.updatePreviousAccentColorHex(value);
    // previousAccentColorHex is local-only, no sync needed
  }

  // Bool fields

  @override
  Future<void> updateShowQuickFront(bool value) async {
    await _dao.updateShowQuickFront(value);
    await _syncField('show_quick_front', value);
  }

  @override
  Future<void> updatePerMemberAccentColors(bool value) async {
    await _dao.updatePerMemberAccentColors(value);
    await _syncField('per_member_accent_colors', value);
  }

  @override
  Future<void> updateFrontingRemindersEnabled(bool value) async {
    await _dao.updateFrontingRemindersEnabled(value);
    await _syncField('fronting_reminders_enabled', value);
  }

  @override
  Future<void> updateChatEnabled(bool value) async {
    await _dao.updateChatEnabled(value);
    await _syncField('chat_enabled', value);
  }

  @override
  Future<void> updatePollsEnabled(bool value) async {
    await _dao.updatePollsEnabled(value);
    await _syncField('polls_enabled', value);
  }

  @override
  Future<void> updateHabitsEnabled(bool value) async {
    await _dao.updateHabitsEnabled(value);
    await _syncField('habits_enabled', value);
  }

  @override
  Future<void> updateSleepTrackingEnabled(bool value) async {
    await _dao.updateSleepTrackingEnabled(value);
    await _syncField('sleep_tracking_enabled', value);
  }

  @override
  Future<void> updateGifSearchEnabled(bool value) async {
    await _dao.updateGifSearchEnabled(value);
    await _syncField('gif_search_enabled', value);
  }

  @override
  Future<void> updateVoiceNotesEnabled(bool value) async {
    await _dao.updateVoiceNotesEnabled(value);
    await _syncField('voice_notes_enabled', value);
  }

  @override
  Future<void> updateLocaleOverride(String? value) async {
    await _dao.updateLocaleOverride(value);
    await _syncField('locale_override', value);
  }

  @override
  Future<void> updateChatLogsFront(bool value) async {
    await _dao.updateChatLogsFront(value);
    await _syncField('chat_logs_front', value);
  }

  @override
  Future<void> updateHabitsBadgeEnabled(bool value) async {
    // Local-only preference — no sync needed.
    await _dao.updateHabitsBadgeEnabled(value);
  }

  @override
  Future<void> updateNotesEnabled(bool value) async {
    await _dao.updateNotesEnabled(value);
    await _syncField('notes_enabled', value);
  }

  @override
  Future<void> updateSyncThemeEnabled(bool value) async {
    await _dao.updateSyncThemeEnabled(value);
    await _syncField('sync_theme_enabled', value);
  }

  @override
  Future<void> updateHasCompletedOnboarding(bool value) async {
    await _dao.updateHasCompletedOnboarding(value);
    await _syncField('has_completed_onboarding', value);
  }

  // Enum fields

  @override
  Future<void> updateTerminology(domain.SystemTerminology value) async {
    await _dao.updateTerminology(value.index);
    await _syncField('terminology', value.index);
  }

  @override
  Future<void> updateThemeMode(domain.AppThemeMode value) async {
    await _dao.updateThemeMode(value.index);
    await _syncField('theme_mode', value.index);
  }

  @override
  Future<void> updateThemeBrightness(domain.ThemeBrightness value) async {
    await _dao.updateThemeBrightness(value.index);
    await _syncFieldIfThemeEnabled('theme_brightness', value.index);
  }

  @override
  Future<void> updateThemeStyle(domain.ThemeStyle value) async {
    await _dao.updateThemeStyle(value.index);
    await _syncFieldIfThemeEnabled('theme_style', value.index);
  }

  @override
  Future<void> updateTimingMode(domain.FrontingTimingMode value) async {
    await _dao.updateTimingMode(value.index);
    await _syncField('timing_mode', value.index);
  }

  // Int fields

  @override
  Future<void> updateFrontingReminderIntervalMinutes(int value) async {
    await _dao.updateFrontingReminderIntervalMinutes(value);
    await _syncField('fronting_reminder_interval_minutes', value);
  }

  @override
  Future<void> updateQuickSwitchThresholdSeconds(int value) async {
    await _dao.updateQuickSwitchThresholdSeconds(value);
    await _syncField('quick_switch_threshold_seconds', value);
  }

  @override
  Future<void> updateIdentityGeneration(int value) async {
    await _dao.updateIdentityGeneration(value);
    await _syncField('identity_generation', value);
  }

  // Multi-field updates

  @override
  Future<void> updateTerminologyFields({
    required domain.SystemTerminology terminology,
    String? customTerminology,
    String? customPluralTerminology,
    bool useEnglish = false,
  }) async {
    await _dao.updateTerminologyFields(
      terminology: terminology.index,
      customTerminology: customTerminology,
      customPluralTerminology: customPluralTerminology,
      useEnglish: useEnglish,
    );
    await syncRecordUpdate(_table, _settingsEntityId, {
      'terminology': terminology.index,
      'custom_terminology': customTerminology,
      'custom_plural_terminology': customPluralTerminology,
      'terminology_use_english': useEnglish ? 1 : 0,
    });
  }

  @override
  Future<void> updateFrontingReminders({
    required bool enabled,
    required int intervalMinutes,
  }) async {
    await _dao.updateFrontingReminders(
      enabled: enabled,
      intervalMinutes: intervalMinutes,
    );
    await syncRecordUpdate(_table, _settingsEntityId, {
      'fronting_reminders_enabled': enabled,
      'fronting_reminder_interval_minutes': intervalMinutes,
    });
  }

  @override
  Future<void> updateFeatureToggles({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
    bool? gifSearchEnabled,
  }) async {
    await _dao.updateFeatureToggles(
      chatEnabled: chatEnabled,
      pollsEnabled: pollsEnabled,
      habitsEnabled: habitsEnabled,
      sleepTrackingEnabled: sleepTrackingEnabled,
      gifSearchEnabled: gifSearchEnabled,
    );
    final syncFields = <String, dynamic>{};
    if (chatEnabled != null) syncFields['chat_enabled'] = chatEnabled;
    if (pollsEnabled != null) syncFields['polls_enabled'] = pollsEnabled;
    if (habitsEnabled != null) syncFields['habits_enabled'] = habitsEnabled;
    if (sleepTrackingEnabled != null) {
      syncFields['sleep_tracking_enabled'] = sleepTrackingEnabled;
    }
    if (gifSearchEnabled != null) {
      syncFields['gif_search_enabled'] = gifSearchEnabled;
    }
    if (syncFields.isNotEmpty) {
      await syncRecordUpdate(_table, _settingsEntityId, syncFields);
    }
  }

  // Phase 3: Synced settings

  @override
  Future<void> updateRemindersEnabled(bool value) async {
    await _dao.updateRemindersEnabled(value);
    await _syncField('reminders_enabled', value);
  }

  @override
  Future<void> updateSystemDescription(String? value) async {
    await _dao.updateSystemDescription(value);
    await _syncField('system_description', value);
  }

  @override
  Future<void> updateSystemAvatarData(Uint8List? value) async {
    await _dao.updateSystemAvatarData(value);
    await _syncField(
      'system_avatar_data',
      value != null ? base64Encode(value) : null,
    );
  }

  // Phase 3: Device-local settings (no sync)

  @override
  Future<void> updateFontScale(double value) async {
    await _dao.updateFontScale(value);
  }

  @override
  Future<void> updateFontFamily(domain.FontFamily value) async {
    await _dao.updateFontFamily(value.index);
  }

  @override
  Future<void> updateDisplayFontInAppBar(bool value) async {
    await _dao.updateDisplayFontInAppBar(value);
  }

  @override
  Future<void> updatePinLockEnabled(bool value) async {
    await _dao.updatePinLockEnabled(value);
  }

  @override
  Future<void> updateBiometricLockEnabled(bool value) async {
    await _dao.updateBiometricLockEnabled(value);
  }

  @override
  Future<void> updateAutoLockDelaySeconds(int value) async {
    await _dao.updateAutoLockDelaySeconds(value);
  }

  // Nav bar configuration (conditionally synced)

  @override
  Future<void> updateNavBarItems(List<String> items) async {
    final encoded = SystemSettingsMapper.encodeNavBarItems(items);
    await _dao.updateNavBarItems(encoded);
    await _syncFieldIfNavEnabled('nav_bar_items', encoded);
  }

  @override
  Future<void> updateNavBarOverflowItems(List<String> items) async {
    final encoded = SystemSettingsMapper.encodeNavBarItems(items);
    await _dao.updateNavBarOverflowItems(encoded);
    await _syncFieldIfNavEnabled('nav_bar_overflow_items', encoded);
  }

  @override
  Future<void> updateSyncNavigationEnabled(bool value) async {
    await _dao.updateSyncNavigationEnabled(value);
    // syncNavigationEnabled itself is always synced so both devices
    // agree on whether nav layout should be shared.
    await _syncField('sync_navigation_enabled', value);
  }

  @override
  Future<void> updateChatBadgePreferences(Map<String, String> prefs) async {
    final encoded = SystemSettingsMapper.encodeBadgePrefs(prefs);
    await _dao.updateChatBadgePreferences(encoded);
    await _syncField('chat_badge_preferences', encoded);
  }

  // --- Helpers ---

  /// Sync a single field to the CRDT engine.
  Future<void> _syncField(String fieldName, dynamic value) =>
      syncRecordUpdate(_table, _settingsEntityId, {fieldName: value});

  /// Sync a field only if theme sync is enabled.
  Future<void> _syncFieldIfThemeEnabled(String fieldName, dynamic value) async {
    final settings = await getSettings();
    if (settings.syncThemeEnabled) {
      await _syncField(fieldName, value);
    }
  }

  /// Sync a field only if navigation sync is enabled.
  Future<void> _syncFieldIfNavEnabled(String fieldName, dynamic value) async {
    final settings = await getSettings();
    if (settings.syncNavigationEnabled) {
      await _syncField(fieldName, value);
    }
  }

  Map<String, dynamic> _settingsFields(domain.SystemSettings s) {
    return {
      'system_name': s.systemName,
      'sharing_id': s.sharingId,
      'show_quick_front': s.showQuickFront,
      'accent_color_hex': s.accentColorHex,
      'per_member_accent_colors': s.perMemberAccentColors,
      'terminology': s.terminology.index,
      'custom_terminology': s.customTerminology,
      'custom_plural_terminology': s.customPluralTerminology,
      'fronting_reminders_enabled': s.frontingRemindersEnabled,
      'fronting_reminder_interval_minutes': s.frontingReminderIntervalMinutes,
      'theme_mode': s.themeMode.index,
      'theme_brightness': s.themeBrightness.index,
      'theme_style': s.themeStyle.index,
      'chat_enabled': s.chatEnabled,
      'polls_enabled': s.pollsEnabled,
      'habits_enabled': s.habitsEnabled,
      'sleep_tracking_enabled': s.sleepTrackingEnabled,
      'gif_search_enabled': s.gifSearchEnabled,
      'quick_switch_threshold_seconds': s.quickSwitchThresholdSeconds,
      'identity_generation': s.identityGeneration,
      'has_completed_onboarding': s.hasCompletedOnboarding,
      'chat_logs_front': s.chatLogsFront,
      'sync_theme_enabled': s.syncThemeEnabled,
      'timing_mode': s.timingMode.index,
      'notes_enabled': s.notesEnabled,
      'system_description': s.systemDescription,
      'system_avatar_data': s.systemAvatarData != null
          ? base64Encode(s.systemAvatarData!)
          : null,
      'reminders_enabled': s.remindersEnabled,
      'sync_navigation_enabled': s.syncNavigationEnabled,
      'nav_bar_items': SystemSettingsMapper.encodeNavBarItems(s.navBarItems),
      'nav_bar_overflow_items': SystemSettingsMapper.encodeNavBarItems(
        s.navBarOverflowItems,
      ),
      'chat_badge_preferences': SystemSettingsMapper.encodeBadgePrefs(
        s.chatBadgePreferences,
      ),
      'is_deleted': false,
    };
  }
}
