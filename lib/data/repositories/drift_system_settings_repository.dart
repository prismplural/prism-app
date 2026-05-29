import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/data/mappers/system_settings_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SleepQuality;
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
    final existingRow = await _dao.getSettingsRow();
    // Singletons have no "tombstoned" state to guard against — bail only
    // when the row is genuinely absent. The settings table has an
    // `is_deleted` column for parity with other tables, but no code path
    // marks the singleton row deleted, so the additional `isDeleted` guard
    // would be dead weight here.
    if (existingRow == null) return;

    final changedDbFields = diffSyncFields(
      _settingsDbFieldsFromRow(existingRow),
      _settingsDbFields(settings),
    );
    final changedFields = diffSyncFields(
      _settingsFieldsFromRow(existingRow),
      _settingsFields(settings),
    );

    if (changedDbFields.isNotEmpty) {
      await _dao.applyPartialSettings(
        _partialSettingsCompanion(changedDbFields),
      );
    }
    if (changedFields.isNotEmpty) {
      await syncRecordUpdate(_table, _settingsEntityId, changedFields);
    }
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

  @override
  Future<void> updatePaletteSeedColorHex(String hex) async {
    await _dao.updatePaletteSeedColorHex(hex);
    await _syncFieldIfThemeEnabled('palette_seed_color_hex', hex);
  }

  // Bool fields

  @override
  Future<void> updateShowQuickFront(bool value) async {
    await _dao.updateShowQuickFront(value);
    await _syncField('show_quick_front', value);
  }

  @override
  Future<void> updateAutoPromoteLongFrontingSessions(bool value) async {
    await _dao.updateAutoPromoteLongFrontingSessions(value);
    await _syncField('auto_promote_long_fronting_sessions', value);
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
  Future<void> updateSleepSuggestionEnabled(bool value) async {
    await _dao.updateSleepSuggestionEnabled(value);
    await _syncField('sleep_suggestion_enabled', value);
  }

  @override
  Future<void> updateSleepSuggestionTime(int hour, int minute) async {
    await _dao.updateSleepSuggestionTime(hour, minute);
    await syncRecordUpdate(_table, _settingsEntityId, {
      'sleep_suggestion_hour': hour,
      'sleep_suggestion_minute': minute,
    });
  }

  @override
  Future<void> updateWakeSuggestionEnabled(bool value) async {
    await _dao.updateWakeSuggestionEnabled(value);
    await _syncField('wake_suggestion_enabled', value);
  }

  @override
  Future<void> updateWakeSuggestionAfterHours(double hours) async {
    await _dao.updateWakeSuggestionAfterHours(hours);
    await _syncField('wake_suggestion_after_hours', hours);
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
    await _dao.updateHabitsBadgeEnabled(value);
    await _syncField('habits_badge_enabled', value);
  }

  @override
  Future<void> updateNotesEnabled(bool value) async {
    await _dao.updateNotesEnabled(value);
    await _syncField('notes_enabled', value);
  }

  @override
  Future<void> updateBoardsEnabled(bool value) async {
    await _dao.updateBoardsEnabled(value);
    await _syncField('boards_enabled', value);
  }

  @override
  Future<void> updateBioMarkdownEnabled(bool value) async {
    await _dao.updateBioMarkdownEnabled(value);
    await _syncField('bio_markdown_enabled', value);
  }

  @override
  Future<void> updateSpBoardsBackfilledAt(DateTime? value) async {
    await _dao.updateSpBoardsBackfilledAt(value);
    // sp_boards_backfilled_at is a CRDT LWW field — sync it so a peer that
    // completes the backfill before us can abort our run via sentinel check.
    await _syncField(
      'sp_boards_backfilled_at',
      value?.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> updateSyncThemeEnabled(bool value) async {
    await _dao.updateSyncThemeEnabled(value);
    await _syncField('sync_theme_enabled', value);
  }

  @override
  Future<void> updateHasCompletedOnboarding(bool value) async {
    await _dao.updateHasCompletedOnboarding(value);
    // Onboarding completion is device-local; not synced to peers.
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
  Future<void> updateCornerStyle(domain.CornerStyle value) async {
    await _dao.updateThemeCornerStyle(value.index);
    await _syncFieldIfThemeEnabled('theme_corner_style', value.index);
  }

  @override
  Future<void> updatePaletteSource(domain.PaletteSource value) async {
    await _dao.updatePaletteSource(value.index);
    await _syncFieldIfThemeEnabled('palette_source', value.index);
  }

  @override
  Future<void> updatePaletteMood(domain.PaletteMood value) async {
    await _dao.updatePaletteMood(value.index);
    await _syncFieldIfThemeEnabled('palette_mood', value.index);
  }

  @override
  Future<void> updatePaletteContrast(domain.PaletteContrast value) async {
    await _dao.updatePaletteContrast(value.index);
    await _syncFieldIfThemeEnabled('palette_contrast', value.index);
  }

  @override
  Future<void> updateTimingMode(domain.FrontingTimingMode value) async {
    await _dao.updateTimingMode(value.index);
    await _syncField('timing_mode', value.index);
  }

  @override
  Future<void> updateFrontingListViewMode(
    domain.FrontingListViewMode value,
  ) async {
    await _dao.updateFrontingListViewMode(value.index);
    await _syncField('fronting_list_view_mode', value.index);
  }

  @override
  Future<void> updateAddFrontDefaultBehavior(
    domain.FrontStartBehavior value,
  ) async {
    await _dao.updateAddFrontDefaultBehavior(value.index);
    await _syncField('add_front_default_behavior', value.index);
  }

  @override
  Future<void> updateQuickFrontDefaultBehavior(
    domain.FrontStartBehavior value,
  ) async {
    await _dao.updateQuickFrontDefaultBehavior(value.index);
    await _syncField('quick_front_default_behavior', value.index);
  }

  @override
  Future<void> updateMembersListViewMode(
    domain.MembersListViewMode value,
  ) async {
    await _dao.updateMembersListViewMode(value.index);
  }

  @override
  Future<void> updateMembersGroupedDefaultState(
    domain.MembersGroupedDefaultState value,
  ) async {
    await _dao.updateMembersGroupedDefaultState(value.index);
  }

  @override
  Future<void> updateMembersFolderMemberVisibility(
    domain.MembersFolderMemberVisibility value,
  ) async {
    await _dao.updateMembersFolderMemberVisibility(value.index);
  }

  @override
  Future<void> updateMembersShowPronouns(bool value) async {
    await _dao.updateMembersShowPronouns(value);
  }

  @override
  Future<void> updateMembersShowFrontButtons(bool value) async {
    await _dao.updateMembersShowFrontButtons(value);
  }

  @override
  Future<void> updateMembersShowGroups(bool value) async {
    await _dao.updateMembersShowGroups(value);
  }

  @override
  Future<void> updateMembersFrontButtonBehavior(
    domain.FrontStartBehavior value,
  ) async {
    await _dao.updateMembersFrontButtonBehavior(value.index);
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
      'terminology_use_english': useEnglish,
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
  Future<void> updateSystemColor(String? colorHex) async {
    await _dao.updateSystemColor(colorHex);
    await _syncField('system_color', colorHex);
  }

  @override
  Future<void> updatePkGroupSyncV2Enabled(bool value) async {
    final settings = await getSettings();
    if (settings.pkGroupSyncV2Enabled == value) return;
    await _dao.updatePkGroupSyncV2Enabled(value);
    await _syncField('pk_group_sync_v2_enabled', value);
  }

  @override
  Future<void> updateSystemTag(String? value) async {
    await _dao.updateSystemTag(value);
    await _syncField('system_tag', value);
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
  Future<void> updateGifConsentState(domain.GifConsentState value) async {
    await _dao.updateGifConsentState(value.index);
  }

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

  // Device-local sleep quality default (no sync)

  @override
  Future<void> updateDefaultSleepQuality(SleepQuality? value) async {
    await _dao.updateDefaultSleepQuality(value?.name);
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

  /// Database patch map; includes local fields omitted from sync emission.
  Map<String, dynamic> _settingsDbFieldsFromRow(SystemSettingsData row) {
    return {
      ..._settingsFieldsFromRow(row),
      'has_completed_onboarding': row.hasCompletedOnboarding,
      'previous_accent_color_hex': row.previousAccentColorHex,
      'gif_consent_state': row.gifConsentState,
      'font_scale': row.fontScale,
      'font_family': row.fontFamily,
      'pin_lock_enabled': row.pinLockEnabled,
      'biometric_lock_enabled': row.biometricLockEnabled,
      'auto_lock_delay_seconds': row.autoLockDelaySeconds,
      'display_font_in_app_bar': row.displayFontInAppBar,
      'default_sleep_quality': row.defaultSleepQuality,
      'boards_enabled': row.boardsEnabled,
      'sp_boards_backfilled_at': row.spBoardsBackfilledAt,
      'members_list_view_mode': row.membersListViewMode,
      'members_grouped_default_state': row.membersGroupedDefaultState,
      'members_folder_member_visibility': row.membersFolderMemberVisibility,
      'members_show_pronouns': row.membersShowPronouns,
      'members_show_front_buttons': row.membersShowFrontButtons,
      'members_show_groups': row.membersShowGroups,
      'members_front_button_behavior': row.membersFrontButtonBehavior,
    };
  }

  Map<String, dynamic> _settingsDbFields(domain.SystemSettings s) {
    return {
      ..._settingsFields(s),
      'has_completed_onboarding': s.hasCompletedOnboarding,
      'previous_accent_color_hex': s.previousAccentColorHex,
      'gif_consent_state': s.gifConsentState.index,
      'font_scale': s.fontScale,
      'font_family': s.fontFamily.index,
      'pin_lock_enabled': s.pinLockEnabled,
      'biometric_lock_enabled': s.biometricLockEnabled,
      'auto_lock_delay_seconds': s.autoLockDelaySeconds,
      'display_font_in_app_bar': s.displayFontInAppBar,
      'default_sleep_quality': s.defaultSleepQuality?.name,
      'boards_enabled': s.boardsEnabled,
      'sp_boards_backfilled_at': s.spBoardsBackfilledAt,
      'members_list_view_mode': s.membersListViewMode.index,
      'members_grouped_default_state': s.membersGroupedDefaultState.index,
      'members_folder_member_visibility': s.membersFolderMemberVisibility.index,
      'members_show_pronouns': s.membersShowPronouns,
      'members_show_front_buttons': s.membersShowFrontButtons,
      'members_show_groups': s.membersShowGroups,
      'members_front_button_behavior': s.membersFrontButtonBehavior.index,
    };
  }

  /// Mirror of [_settingsFields] keyed off the raw Drift row.
  ///
  /// Used by the patch-style [updateSettings] path: the previous state for
  /// `diffSyncFields` must use the same key set and encoding as the next
  /// state, so any column that flows through `_settingsFields` must also
  /// flow through here. Single-field setters (`updateBoardsEnabled`,
  /// `updateSpBoardsBackfilledAt`, etc.) own their own emission paths and
  /// stay out of this map by design.
  ///
  /// JSON-encoded columns (`nav_bar_items`, `nav_bar_overflow_items`,
  /// `chat_badge_preferences`) carry ordered data — pass the stored string
  /// straight through without canonicalizing.
  Map<String, dynamic> _settingsFieldsFromRow(SystemSettingsData row) {
    return {
      'system_name': row.systemName,
      'sharing_id': row.sharingId,
      'show_quick_front': row.showQuickFront,
      'accent_color_hex': row.accentColorHex,
      'per_member_accent_colors': row.perMemberAccentColors,
      'terminology': row.terminology,
      'custom_terminology': row.customTerminology,
      'custom_plural_terminology': row.customPluralTerminology,
      'terminology_use_english': row.terminologyUseEnglish,
      'fronting_reminders_enabled': row.frontingRemindersEnabled,
      'fronting_reminder_interval_minutes': row.frontingReminderIntervalMinutes,
      'theme_mode': row.themeMode,
      'theme_brightness': row.themeBrightness,
      'theme_style': row.themeStyle,
      'theme_corner_style': row.themeCornerStyle,
      'palette_source': row.paletteSource,
      'palette_seed_color_hex': row.paletteSeedColorHex,
      'palette_mood': row.paletteMood,
      'palette_contrast': row.paletteContrast,
      'chat_enabled': row.chatEnabled,
      'polls_enabled': row.pollsEnabled,
      'habits_enabled': row.habitsEnabled,
      'sleep_tracking_enabled': row.sleepTrackingEnabled,
      'gif_search_enabled': row.gifSearchEnabled,
      'voice_notes_enabled': row.voiceNotesEnabled,
      'sleep_suggestion_enabled': row.sleepSuggestionEnabled,
      'sleep_suggestion_hour': row.sleepSuggestionHour,
      'sleep_suggestion_minute': row.sleepSuggestionMinute,
      'wake_suggestion_enabled': row.wakeSuggestionEnabled,
      'wake_suggestion_after_hours': row.wakeSuggestionAfterHours,
      'locale_override': row.localeOverride,
      'quick_switch_threshold_seconds': row.quickSwitchThresholdSeconds,
      'identity_generation': row.identityGeneration,
      'chat_logs_front': row.chatLogsFront,
      'sync_theme_enabled': row.syncThemeEnabled,
      'timing_mode': row.timingMode,
      'notes_enabled': row.notesEnabled,
      'pk_group_sync_v2_enabled': row.pkGroupSyncV2Enabled,
      'system_description': row.systemDescription,
      'system_color': row.systemColor,
      'system_tag': row.systemTag,
      'system_avatar_data': row.systemAvatarData != null
          ? base64Encode(row.systemAvatarData!)
          : null,
      'reminders_enabled': row.remindersEnabled,
      'habits_badge_enabled': row.habitsBadgeEnabled,
      'sync_navigation_enabled': row.syncNavigationEnabled,
      'nav_bar_items': row.navBarItems,
      'nav_bar_overflow_items': row.navBarOverflowItems,
      'chat_badge_preferences': row.chatBadgePreferences,
      'fronting_list_view_mode': row.frontingListViewMode,
      'add_front_default_behavior': row.addFrontDefaultBehavior,
      'quick_front_default_behavior': row.quickFrontDefaultBehavior,
      'auto_promote_long_fronting_sessions':
          row.autoPromoteLongFrontingSessions,
      'bio_markdown_enabled': row.bioMarkdownEnabled,
      'is_deleted': row.isDeleted,
    };
  }

  /// Build a sparse [SystemSettingsTableCompanion] from a patch produced
  /// by `diffSyncFields`. Columns not in the patch stay `Value.absent()`
  /// so the underlying UPDATE only touches what changed.
  ///
  /// JSON columns (`nav_bar_items`, `nav_bar_overflow_items`,
  /// `chat_badge_preferences`) are stored as JSON strings — pass them
  /// through as-is. `system_avatar_data` is stored as bytes; the patch
  /// carries the base64-encoded string used on the sync wire and is
  /// decoded here to round-trip into the database.
  SystemSettingsTableCompanion _partialSettingsCompanion(
    Map<String, dynamic> fields,
  ) {
    return SystemSettingsTableCompanion(
      systemName: fields.containsKey('system_name')
          ? Value(fields['system_name'] as String?)
          : const Value.absent(),
      sharingId: fields.containsKey('sharing_id')
          ? Value(fields['sharing_id'] as String?)
          : const Value.absent(),
      showQuickFront: fields.containsKey('show_quick_front')
          ? Value(fields['show_quick_front'] as bool)
          : const Value.absent(),
      accentColorHex: fields.containsKey('accent_color_hex')
          ? Value(fields['accent_color_hex'] as String)
          : const Value.absent(),
      perMemberAccentColors: fields.containsKey('per_member_accent_colors')
          ? Value(fields['per_member_accent_colors'] as bool)
          : const Value.absent(),
      terminology: fields.containsKey('terminology')
          ? Value(fields['terminology'] as int)
          : const Value.absent(),
      customTerminology: fields.containsKey('custom_terminology')
          ? Value(fields['custom_terminology'] as String?)
          : const Value.absent(),
      customPluralTerminology: fields.containsKey('custom_plural_terminology')
          ? Value(fields['custom_plural_terminology'] as String?)
          : const Value.absent(),
      terminologyUseEnglish: fields.containsKey('terminology_use_english')
          ? Value(fields['terminology_use_english'] as bool)
          : const Value.absent(),
      frontingRemindersEnabled: fields.containsKey('fronting_reminders_enabled')
          ? Value(fields['fronting_reminders_enabled'] as bool)
          : const Value.absent(),
      frontingReminderIntervalMinutes:
          fields.containsKey('fronting_reminder_interval_minutes')
          ? Value(fields['fronting_reminder_interval_minutes'] as int)
          : const Value.absent(),
      themeMode: fields.containsKey('theme_mode')
          ? Value(fields['theme_mode'] as int)
          : const Value.absent(),
      themeBrightness: fields.containsKey('theme_brightness')
          ? Value(fields['theme_brightness'] as int)
          : const Value.absent(),
      themeStyle: fields.containsKey('theme_style')
          ? Value(fields['theme_style'] as int)
          : const Value.absent(),
      themeCornerStyle: fields.containsKey('theme_corner_style')
          ? Value(fields['theme_corner_style'] as int)
          : const Value.absent(),
      paletteSource: fields.containsKey('palette_source')
          ? Value(fields['palette_source'] as int)
          : const Value.absent(),
      paletteSeedColorHex: fields.containsKey('palette_seed_color_hex')
          ? Value(fields['palette_seed_color_hex'] as String)
          : const Value.absent(),
      paletteMood: fields.containsKey('palette_mood')
          ? Value(fields['palette_mood'] as int)
          : const Value.absent(),
      paletteContrast: fields.containsKey('palette_contrast')
          ? Value(fields['palette_contrast'] as int)
          : const Value.absent(),
      chatEnabled: fields.containsKey('chat_enabled')
          ? Value(fields['chat_enabled'] as bool)
          : const Value.absent(),
      pollsEnabled: fields.containsKey('polls_enabled')
          ? Value(fields['polls_enabled'] as bool)
          : const Value.absent(),
      habitsEnabled: fields.containsKey('habits_enabled')
          ? Value(fields['habits_enabled'] as bool)
          : const Value.absent(),
      sleepTrackingEnabled: fields.containsKey('sleep_tracking_enabled')
          ? Value(fields['sleep_tracking_enabled'] as bool)
          : const Value.absent(),
      gifSearchEnabled: fields.containsKey('gif_search_enabled')
          ? Value(fields['gif_search_enabled'] as bool)
          : const Value.absent(),
      voiceNotesEnabled: fields.containsKey('voice_notes_enabled')
          ? Value(fields['voice_notes_enabled'] as bool)
          : const Value.absent(),
      sleepSuggestionEnabled: fields.containsKey('sleep_suggestion_enabled')
          ? Value(fields['sleep_suggestion_enabled'] as bool)
          : const Value.absent(),
      sleepSuggestionHour: fields.containsKey('sleep_suggestion_hour')
          ? Value(fields['sleep_suggestion_hour'] as int)
          : const Value.absent(),
      sleepSuggestionMinute: fields.containsKey('sleep_suggestion_minute')
          ? Value(fields['sleep_suggestion_minute'] as int)
          : const Value.absent(),
      wakeSuggestionEnabled: fields.containsKey('wake_suggestion_enabled')
          ? Value(fields['wake_suggestion_enabled'] as bool)
          : const Value.absent(),
      wakeSuggestionAfterHours:
          fields.containsKey('wake_suggestion_after_hours')
          ? Value(fields['wake_suggestion_after_hours'] as double)
          : const Value.absent(),
      localeOverride: fields.containsKey('locale_override')
          ? Value(fields['locale_override'] as String?)
          : const Value.absent(),
      quickSwitchThresholdSeconds:
          fields.containsKey('quick_switch_threshold_seconds')
          ? Value(fields['quick_switch_threshold_seconds'] as int)
          : const Value.absent(),
      identityGeneration: fields.containsKey('identity_generation')
          ? Value(fields['identity_generation'] as int)
          : const Value.absent(),
      chatLogsFront: fields.containsKey('chat_logs_front')
          ? Value(fields['chat_logs_front'] as bool)
          : const Value.absent(),
      hasCompletedOnboarding: fields.containsKey('has_completed_onboarding')
          ? Value(fields['has_completed_onboarding'] as bool)
          : const Value.absent(),
      syncThemeEnabled: fields.containsKey('sync_theme_enabled')
          ? Value(fields['sync_theme_enabled'] as bool)
          : const Value.absent(),
      timingMode: fields.containsKey('timing_mode')
          ? Value(fields['timing_mode'] as int)
          : const Value.absent(),
      notesEnabled: fields.containsKey('notes_enabled')
          ? Value(fields['notes_enabled'] as bool)
          : const Value.absent(),
      previousAccentColorHex: fields.containsKey('previous_accent_color_hex')
          ? Value(fields['previous_accent_color_hex'] as String)
          : const Value.absent(),
      pkGroupSyncV2Enabled: fields.containsKey('pk_group_sync_v2_enabled')
          ? Value(fields['pk_group_sync_v2_enabled'] as bool)
          : const Value.absent(),
      systemDescription: fields.containsKey('system_description')
          ? Value(fields['system_description'] as String?)
          : const Value.absent(),
      systemColor: fields.containsKey('system_color')
          ? Value(fields['system_color'] as String?)
          : const Value.absent(),
      systemTag: fields.containsKey('system_tag')
          ? Value(fields['system_tag'] as String?)
          : const Value.absent(),
      systemAvatarData: fields.containsKey('system_avatar_data')
          ? Value(
              fields['system_avatar_data'] != null
                  ? base64Decode(fields['system_avatar_data'] as String)
                  : null,
            )
          : const Value.absent(),
      remindersEnabled: fields.containsKey('reminders_enabled')
          ? Value(fields['reminders_enabled'] as bool)
          : const Value.absent(),
      habitsBadgeEnabled: fields.containsKey('habits_badge_enabled')
          ? Value(fields['habits_badge_enabled'] as bool)
          : const Value.absent(),
      gifConsentState: fields.containsKey('gif_consent_state')
          ? Value(fields['gif_consent_state'] as int)
          : const Value.absent(),
      fontScale: fields.containsKey('font_scale')
          ? Value(fields['font_scale'] as double)
          : const Value.absent(),
      fontFamily: fields.containsKey('font_family')
          ? Value(fields['font_family'] as int)
          : const Value.absent(),
      pinLockEnabled: fields.containsKey('pin_lock_enabled')
          ? Value(fields['pin_lock_enabled'] as bool)
          : const Value.absent(),
      biometricLockEnabled: fields.containsKey('biometric_lock_enabled')
          ? Value(fields['biometric_lock_enabled'] as bool)
          : const Value.absent(),
      autoLockDelaySeconds: fields.containsKey('auto_lock_delay_seconds')
          ? Value(fields['auto_lock_delay_seconds'] as int)
          : const Value.absent(),
      displayFontInAppBar: fields.containsKey('display_font_in_app_bar')
          ? Value(fields['display_font_in_app_bar'] as bool)
          : const Value.absent(),
      syncNavigationEnabled: fields.containsKey('sync_navigation_enabled')
          ? Value(fields['sync_navigation_enabled'] as bool)
          : const Value.absent(),
      navBarItems: fields.containsKey('nav_bar_items')
          ? Value(fields['nav_bar_items'] as String)
          : const Value.absent(),
      navBarOverflowItems: fields.containsKey('nav_bar_overflow_items')
          ? Value(fields['nav_bar_overflow_items'] as String)
          : const Value.absent(),
      chatBadgePreferences: fields.containsKey('chat_badge_preferences')
          ? Value(fields['chat_badge_preferences'] as String)
          : const Value.absent(),
      defaultSleepQuality: fields.containsKey('default_sleep_quality')
          ? Value(fields['default_sleep_quality'] as String?)
          : const Value.absent(),
      frontingListViewMode: fields.containsKey('fronting_list_view_mode')
          ? Value(fields['fronting_list_view_mode'] as int)
          : const Value.absent(),
      addFrontDefaultBehavior: fields.containsKey('add_front_default_behavior')
          ? Value(fields['add_front_default_behavior'] as int)
          : const Value.absent(),
      quickFrontDefaultBehavior:
          fields.containsKey('quick_front_default_behavior')
          ? Value(fields['quick_front_default_behavior'] as int)
          : const Value.absent(),
      autoPromoteLongFrontingSessions:
          fields.containsKey('auto_promote_long_fronting_sessions')
          ? Value(fields['auto_promote_long_fronting_sessions'] as bool)
          : const Value.absent(),
      boardsEnabled: fields.containsKey('boards_enabled')
          ? Value(fields['boards_enabled'] as bool)
          : const Value.absent(),
      spBoardsBackfilledAt: fields.containsKey('sp_boards_backfilled_at')
          ? Value(fields['sp_boards_backfilled_at'] as DateTime?)
          : const Value.absent(),
      membersListViewMode: fields.containsKey('members_list_view_mode')
          ? Value(fields['members_list_view_mode'] as int)
          : const Value.absent(),
      membersGroupedDefaultState:
          fields.containsKey('members_grouped_default_state')
          ? Value(fields['members_grouped_default_state'] as int)
          : const Value.absent(),
      membersFolderMemberVisibility:
          fields.containsKey('members_folder_member_visibility')
          ? Value(fields['members_folder_member_visibility'] as int)
          : const Value.absent(),
      membersShowPronouns: fields.containsKey('members_show_pronouns')
          ? Value(fields['members_show_pronouns'] as bool)
          : const Value.absent(),
      membersShowFrontButtons: fields.containsKey('members_show_front_buttons')
          ? Value(fields['members_show_front_buttons'] as bool)
          : const Value.absent(),
      membersShowGroups: fields.containsKey('members_show_groups')
          ? Value(fields['members_show_groups'] as bool)
          : const Value.absent(),
      membersFrontButtonBehavior:
          fields.containsKey('members_front_button_behavior')
          ? Value(fields['members_front_button_behavior'] as int)
          : const Value.absent(),
      bioMarkdownEnabled: fields.containsKey('bio_markdown_enabled')
          ? Value(fields['bio_markdown_enabled'] as bool)
          : const Value.absent(),
    );
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
      'terminology_use_english': s.terminologyUseEnglish,
      'fronting_reminders_enabled': s.frontingRemindersEnabled,
      'fronting_reminder_interval_minutes': s.frontingReminderIntervalMinutes,
      'theme_mode': s.themeMode.index,
      'theme_brightness': s.themeBrightness.index,
      'theme_style': s.themeStyle.index,
      'theme_corner_style': s.cornerStyle.index,
      'palette_source': s.paletteSource.index,
      'palette_seed_color_hex': s.paletteSeedColorHex,
      'palette_mood': s.paletteMood.index,
      'palette_contrast': s.paletteContrast.index,
      'chat_enabled': s.chatEnabled,
      'polls_enabled': s.pollsEnabled,
      'habits_enabled': s.habitsEnabled,
      'sleep_tracking_enabled': s.sleepTrackingEnabled,
      'gif_search_enabled': s.gifSearchEnabled,
      'voice_notes_enabled': s.voiceNotesEnabled,
      'sleep_suggestion_enabled': s.sleepSuggestionEnabled,
      'sleep_suggestion_hour': s.sleepSuggestionHour,
      'sleep_suggestion_minute': s.sleepSuggestionMinute,
      'wake_suggestion_enabled': s.wakeSuggestionEnabled,
      'wake_suggestion_after_hours': s.wakeSuggestionAfterHours,
      'locale_override': s.localeOverride,
      'quick_switch_threshold_seconds': s.quickSwitchThresholdSeconds,
      'identity_generation': s.identityGeneration,
      'chat_logs_front': s.chatLogsFront,
      'sync_theme_enabled': s.syncThemeEnabled,
      'timing_mode': s.timingMode.index,
      'notes_enabled': s.notesEnabled,
      'pk_group_sync_v2_enabled': s.pkGroupSyncV2Enabled,
      'system_description': s.systemDescription,
      'system_color': s.systemColor,
      'system_tag': s.systemTag,
      'system_avatar_data': s.systemAvatarData != null
          ? base64Encode(s.systemAvatarData!)
          : null,
      'reminders_enabled': s.remindersEnabled,
      'habits_badge_enabled': s.habitsBadgeEnabled,
      'sync_navigation_enabled': s.syncNavigationEnabled,
      'nav_bar_items': SystemSettingsMapper.encodeNavBarItems(s.navBarItems),
      'nav_bar_overflow_items': SystemSettingsMapper.encodeNavBarItems(
        s.navBarOverflowItems,
      ),
      'chat_badge_preferences': SystemSettingsMapper.encodeBadgePrefs(
        s.chatBadgePreferences,
      ),
      'fronting_list_view_mode': s.frontingListViewMode.index,
      'add_front_default_behavior': s.addFrontDefaultBehavior.index,
      'quick_front_default_behavior': s.quickFrontDefaultBehavior.index,
      'auto_promote_long_fronting_sessions': s.autoPromoteLongFrontingSessions,
      'bio_markdown_enabled': s.bioMarkdownEnabled,
      'is_deleted': false,
    };
  }

  /// Test-only access to the sync field map. Mirrors `debugNoteFields` /
  /// `debugCommentFields` patterns elsewhere — lets the parity / sync-emit
  /// contract tests assert that every prefs field appears in the emit map
  /// without having to drive the full `updateSettings` path.
  @visibleForTesting
  Map<String, dynamic> debugSettingsFields(domain.SystemSettings s) =>
      _settingsFields(s);

  /// Phase 5 capture-replay alias for [debugSettingsFields].
  ///
  /// Plan §"Field-map reuse" mandates a single field-map implementation per
  /// entity, callable from the SP importer's batch-insert path so captured
  /// emission tuples are byte-identical to the repository's. Both names
  /// resolve to `_settingsFields` so the contract holds. See
  /// `docs/plans/sp-import-perf-quick-wins.md`.
  Map<String, dynamic> settingsFields(domain.SystemSettings s) =>
      _settingsFields(s);
}
