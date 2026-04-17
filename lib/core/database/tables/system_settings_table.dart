import 'package:drift/drift.dart';

/// Singleton settings row (id='singleton').
///
/// Fields fall into two sync tiers:
/// - **Synced** — appearance, terminology, feature toggles, timing mode.
///   Changes propagate to all devices via CRDT.
/// - **Device-local** — font scale, biometric lock, autoLock, display font,
///   nav bar layout. Stays on this device only.
///
/// When adding a new setting, decide which tier it belongs to and add it to
/// the appropriate section below. Synced fields also need a sync_schema.dart
/// entry and a DriftSyncAdapter handler in drift_sync_adapter.dart.
@DataClassName('SystemSettingsData')
class SystemSettingsTable extends Table {
  TextColumn get id => text().withDefault(const Constant('singleton'))();
  TextColumn get systemName => text().nullable()();
  BoolColumn get showQuickFront =>
      boolean().withDefault(const Constant(true))();
  TextColumn get accentColorHex =>
      text().withDefault(const Constant('#AF8EE9'))();
  BoolColumn get perMemberAccentColors =>
      boolean().withDefault(const Constant(false))();
  IntColumn get terminology =>
      integer().withDefault(const Constant(0))(); // enum index
  TextColumn get customTerminology => text().nullable()();
  TextColumn get customPluralTerminology => text().nullable()();
  TextColumn get localeOverride => text().nullable()();
  BoolColumn get terminologyUseEnglish =>
      boolean().withDefault(const Constant(false))();
  TextColumn get sharingId => text().nullable()();
  BoolColumn get frontingRemindersEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get frontingReminderIntervalMinutes =>
      integer().withDefault(const Constant(60))();
  IntColumn get themeMode => integer().withDefault(
    const Constant(0),
  )(); // AppThemeMode enum index (legacy)
  IntColumn get themeBrightness =>
      integer().withDefault(const Constant(0))(); // ThemeBrightness enum index
  IntColumn get themeStyle =>
      integer().withDefault(const Constant(0))(); // ThemeStyle enum index
  // Feature toggles
  BoolColumn get chatEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get pollsEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get habitsEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get sleepTrackingEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get gifSearchEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get voiceNotesEnabled =>
      boolean().withDefault(const Constant(true))();
  // Sleep suggestion settings (synced)
  BoolColumn get sleepSuggestionEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get sleepSuggestionHour =>
      integer().withDefault(const Constant(22))();
  IntColumn get sleepSuggestionMinute =>
      integer().withDefault(const Constant(0))();
  BoolColumn get wakeSuggestionEnabled =>
      boolean().withDefault(const Constant(false))();
  RealColumn get wakeSuggestionAfterHours =>
      real().withDefault(const Constant(8.0))();
  // Quick-switch correction
  IntColumn get quickSwitchThresholdSeconds =>
      integer().withDefault(const Constant(30))();
  // Sharing identity generation — incremented on DEK rotation
  IntColumn get identityGeneration =>
      integer().withDefault(const Constant(0))();
  // Chat behavior
  BoolColumn get chatLogsFront =>
      boolean().withDefault(const Constant(false))();
  // Onboarding
  BoolColumn get hasCompletedOnboarding =>
      boolean().withDefault(const Constant(false))();
  // Device pairing / sync
  BoolColumn get syncThemeEnabled =>
      boolean().withDefault(const Constant(false))();
  // Fronting timing mode (synced — system-level decision)
  IntColumn get timingMode => integer().withDefault(
    const Constant(0),
  )(); // FrontingTimingMode enum index
  // Habits badge (synced)
  BoolColumn get habitsBadgeEnabled =>
      boolean().withDefault(const Constant(true))();
  // Notes feature toggle
  BoolColumn get notesEnabled => boolean().withDefault(const Constant(true))();
  // Phase 3: Synced settings
  TextColumn get systemDescription => text().nullable()();
  BlobColumn get systemAvatarData => blob().nullable()();
  BoolColumn get remindersEnabled =>
      boolean().withDefault(const Constant(true))();
  // Phase 3: Device-local settings
  IntColumn get gifConsentState =>
      integer().withDefault(const Constant(0))(); // GifConsentState enum index
  RealColumn get fontScale => real().withDefault(const Constant(1.0))();
  IntColumn get fontFamily =>
      integer().withDefault(const Constant(0))(); // FontFamily enum index
  BoolColumn get pinLockEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get biometricLockEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get autoLockDelaySeconds =>
      integer().withDefault(const Constant(0))();
  // Display font in home app bar (device-local)
  BoolColumn get displayFontInAppBar =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  // Stores the user's accent color before switching to Material You
  TextColumn get previousAccentColorHex =>
      text().withDefault(const Constant(''))();
  // Device-local nav bar configuration (JSON-encoded list of tab IDs)
  TextColumn get navBarItems => text().withDefault(const Constant(''))();
  TextColumn get navBarOverflowItems =>
      text().withDefault(const Constant(''))();
  BoolColumn get syncNavigationEnabled =>
      boolean().withDefault(const Constant(true))();
  // Chat badge preferences — JSON map of memberId → 'all' | 'mentions_only'
  TextColumn get chatBadgePreferences =>
      text().withDefault(const Constant('{}'))();

  @override
  String get tableName => 'system_settings';

  @override
  Set<Column> get primaryKey => {id};
}
