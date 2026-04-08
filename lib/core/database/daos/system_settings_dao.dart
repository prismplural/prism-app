import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/system_settings_table.dart';

part 'system_settings_dao.g.dart';

@DriftAccessor(tables: [SystemSettingsTable])
class SystemSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SystemSettingsDaoMixin {
  SystemSettingsDao(super.db);

  static const _singletonId = 'singleton';

  Future<SystemSettingsData> getSettings() async {
    final result = await (select(
      systemSettingsTable,
    )..where((s) => s.id.equals(_singletonId))).getSingleOrNull();
    if (result != null) return result;

    // Create default row on first access (use insertOnConflictUpdate to
    // handle concurrent calls racing to create the singleton).
    await into(systemSettingsTable).insertOnConflictUpdate(
      const SystemSettingsTableCompanion(id: Value(_singletonId)),
    );
    return (select(
      systemSettingsTable,
    )..where((s) => s.id.equals(_singletonId))).getSingle();
  }

  Stream<SystemSettingsData> watchSettings() {
    // Ensure the singleton row exists before watching
    getSettings();
    return (select(
      systemSettingsTable,
    )..where((s) => s.id.equals(_singletonId))).watchSingle();
  }

  Future<void> upsertSettings(SystemSettingsTableCompanion settings) =>
      into(systemSettingsTable).insertOnConflictUpdate(settings);

  /// Update a single field in the singleton settings row.
  Future<void> _updateField(SystemSettingsTableCompanion companion) => (update(
    systemSettingsTable,
  )..where((s) => s.id.equals(_singletonId))).write(companion);

  // --- Text fields ---

  Future<void> updateSystemName(String? value) =>
      _updateField(SystemSettingsTableCompanion(systemName: Value(value)));

  Future<void> updateSharingId(String? value) =>
      _updateField(SystemSettingsTableCompanion(sharingId: Value(value)));

  Future<void> updateAccentColorHex(String value) =>
      _updateField(SystemSettingsTableCompanion(accentColorHex: Value(value)));

  Future<void> updateCustomTerminology(String? value) => _updateField(
    SystemSettingsTableCompanion(customTerminology: Value(value)),
  );

  Future<void> updateCustomPluralTerminology(String? value) => _updateField(
    SystemSettingsTableCompanion(customPluralTerminology: Value(value)),
  );

  Future<void> updatePreviousAccentColorHex(String value) => _updateField(
    SystemSettingsTableCompanion(previousAccentColorHex: Value(value)),
  );

  // --- Bool fields ---

  Future<void> updateShowQuickFront(bool value) =>
      _updateField(SystemSettingsTableCompanion(showQuickFront: Value(value)));

  Future<void> updatePerMemberAccentColors(bool value) => _updateField(
    SystemSettingsTableCompanion(perMemberAccentColors: Value(value)),
  );

  Future<void> updateFrontingRemindersEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(frontingRemindersEnabled: Value(value)),
  );

  Future<void> updateChatEnabled(bool value) =>
      _updateField(SystemSettingsTableCompanion(chatEnabled: Value(value)));

  Future<void> updatePollsEnabled(bool value) =>
      _updateField(SystemSettingsTableCompanion(pollsEnabled: Value(value)));

  Future<void> updateHabitsEnabled(bool value) =>
      _updateField(SystemSettingsTableCompanion(habitsEnabled: Value(value)));

  Future<void> updateSleepTrackingEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(sleepTrackingEnabled: Value(value)),
  );

  Future<void> updateChatLogsFront(bool value) =>
      _updateField(SystemSettingsTableCompanion(chatLogsFront: Value(value)));

  Future<void> updateHabitsBadgeEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(habitsBadgeEnabled: Value(value)),
  );

  Future<void> updateSyncThemeEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(syncThemeEnabled: Value(value)),
  );

  Future<void> updateHasCompletedOnboarding(bool value) => _updateField(
    SystemSettingsTableCompanion(hasCompletedOnboarding: Value(value)),
  );

  Future<void> updateNotesEnabled(bool value) =>
      _updateField(SystemSettingsTableCompanion(notesEnabled: Value(value)));

  Future<void> updateRemindersEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(remindersEnabled: Value(value)),
  );

  // --- Text fields (Phase 3) ---

  Future<void> updateSystemDescription(String? value) => _updateField(
    SystemSettingsTableCompanion(systemDescription: Value(value)),
  );

  // --- Blob fields (Phase 3) ---

  Future<void> updateSystemAvatarData(Uint8List? value) => _updateField(
    SystemSettingsTableCompanion(systemAvatarData: Value(value)),
  );

  // --- Device-local fields (Phase 3) ---

  Future<void> updateFontScale(double value) =>
      _updateField(SystemSettingsTableCompanion(fontScale: Value(value)));

  Future<void> updateFontFamily(int value) =>
      _updateField(SystemSettingsTableCompanion(fontFamily: Value(value)));

  Future<void> updateDisplayFontInAppBar(bool value) => _updateField(
    SystemSettingsTableCompanion(displayFontInAppBar: Value(value)),
  );

  Future<void> updatePinLockEnabled(bool value) =>
      _updateField(SystemSettingsTableCompanion(pinLockEnabled: Value(value)));

  Future<void> updateBiometricLockEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(biometricLockEnabled: Value(value)),
  );

  Future<void> updateAutoLockDelaySeconds(int value) => _updateField(
    SystemSettingsTableCompanion(autoLockDelaySeconds: Value(value)),
  );

  Future<void> updateNavBarItems(String value) =>
      _updateField(SystemSettingsTableCompanion(navBarItems: Value(value)));

  Future<void> updateNavBarOverflowItems(String value) => _updateField(
    SystemSettingsTableCompanion(navBarOverflowItems: Value(value)),
  );

  Future<void> updateSyncNavigationEnabled(bool value) => _updateField(
    SystemSettingsTableCompanion(syncNavigationEnabled: Value(value)),
  );

  Future<void> updateChatBadgePreferences(String value) => _updateField(
    SystemSettingsTableCompanion(chatBadgePreferences: Value(value)),
  );

  // --- Int (enum index) fields ---

  Future<void> updateTerminology(int value) =>
      _updateField(SystemSettingsTableCompanion(terminology: Value(value)));

  Future<void> updateThemeMode(int value) =>
      _updateField(SystemSettingsTableCompanion(themeMode: Value(value)));

  Future<void> updateThemeBrightness(int value) =>
      _updateField(SystemSettingsTableCompanion(themeBrightness: Value(value)));

  Future<void> updateThemeStyle(int value) =>
      _updateField(SystemSettingsTableCompanion(themeStyle: Value(value)));

  Future<void> updateTimingMode(int value) =>
      _updateField(SystemSettingsTableCompanion(timingMode: Value(value)));

  // --- Int fields ---

  Future<void> updateFrontingReminderIntervalMinutes(int value) => _updateField(
    SystemSettingsTableCompanion(frontingReminderIntervalMinutes: Value(value)),
  );

  Future<void> updateQuickSwitchThresholdSeconds(int value) => _updateField(
    SystemSettingsTableCompanion(quickSwitchThresholdSeconds: Value(value)),
  );

  Future<void> updateIdentityGeneration(int value) => _updateField(
    SystemSettingsTableCompanion(identityGeneration: Value(value)),
  );

  // --- Multi-field updates ---

  Future<void> updateTerminologyFields({
    required int terminology,
    String? customTerminology,
    String? customPluralTerminology,
  }) => _updateField(
    SystemSettingsTableCompanion(
      terminology: Value(terminology),
      customTerminology: Value(customTerminology),
      customPluralTerminology: Value(customPluralTerminology),
    ),
  );

  Future<void> updateFrontingReminders({
    required bool enabled,
    required int intervalMinutes,
  }) => _updateField(
    SystemSettingsTableCompanion(
      frontingRemindersEnabled: Value(enabled),
      frontingReminderIntervalMinutes: Value(intervalMinutes),
    ),
  );

  Future<void> updateFeatureToggles({
    bool? chatEnabled,
    bool? pollsEnabled,
    bool? habitsEnabled,
    bool? sleepTrackingEnabled,
  }) {
    final companion = SystemSettingsTableCompanion(
      chatEnabled: chatEnabled != null
          ? Value(chatEnabled)
          : const Value.absent(),
      pollsEnabled: pollsEnabled != null
          ? Value(pollsEnabled)
          : const Value.absent(),
      habitsEnabled: habitsEnabled != null
          ? Value(habitsEnabled)
          : const Value.absent(),
      sleepTrackingEnabled: sleepTrackingEnabled != null
          ? Value(sleepTrackingEnabled)
          : const Value.absent(),
    );
    return _updateField(companion);
  }
}
