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
  IntColumn get themeCornerStyle =>
      integer().withDefault(const Constant(0))(); // CornerStyle enum index
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
  BoolColumn get pkGroupSyncV2Enabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get systemDescription => text().nullable()();
  TextColumn get systemColor => text().nullable()();
  // PluralKit system profile tag — synced (plan 04).
  TextColumn get systemTag => text().nullable()();
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
  // Default sleep quality for new sleep sessions (device-local)
  TextColumn get defaultSleepQuality => text().nullable()();

  // -- Phase 1: per-member fronting refactor (docs/plans/fronting-per-member-sessions.md §4.1) --
  //
  // Drives the upgrade modal shown on first app launch after v7 schema upgrade.
  //
  // Allowed values:
  //   'notStarted'      — v7 schema installed but user hasn't seen the modal yet
  //   'deferred'        — user tapped "Not now"; modal re-shown on next launch
  //   'upgradeAndKeep'  — user chose selective migration (in progress or complete)
  //   'startFresh'      — user chose wipe-everything path (in progress or complete)
  //   'notNow'          — alias for deferred, written by the "Not now" path
  //   'complete'        — migration finished (or fresh install — no data to migrate)
  //   'blocked'         — v7 migration detected unresolvable duplicate rows;
  //                       Phase 5 startup will surface this to the user
  //
  // Default is 'complete' so that fresh installs (onCreate path) skip the
  // upgrade modal entirely — there is no legacy data to migrate.  The v6→v7
  // onUpgrade block immediately overwrites the default with 'notStarted' for
  // any database that existed before v7, so existing users still see the modal.
  //
  // Device-local: migration mode is per-device (solo vs primary vs secondary
  // roles differ per §4.2); not synced across peers.
  TextColumn get pendingFrontingMigrationMode =>
      text().withDefault(const Constant('complete'))();

  // Codex pass 2 #B-NEW3 — substate within the `'inProgress'` window.
  //
  // Allowed values:
  //   ''           — initial / inert (no destructive post-tx step has run yet)
  //   'resetDone'  — Rust `reset_sync_state()` returned success; remaining
  //                  post-tx steps (keychain wipe + sync_quarantine clear +
  //                  mark complete) still need to run
  //
  // Without this we cannot distinguish two failure modes from inside
  // resumeCleanup():
  //   (a) Rust reset never ran — we MUST run it now.
  //   (b) Rust reset already succeeded; only the keychain/quarantine
  //       follow-ups failed — re-running reset on an unconfigured handle
  //       would return "sync_id not set" and we'd treat that as
  //       "already reset" even when it wasn't.
  //
  // The previous implementation collapsed both cases via the "sync_id
  // not set"-means-success heuristic, which silently marked migration
  // complete when (a) had failed for unrelated reasons (e.g. the FFI
  // call threw before clearing the persistent tables) and the next
  // launch would re-attach to the OLD sync group.
  //
  // Device-local: same scope as `pending_fronting_migration_mode`.
  TextColumn get pendingFrontingMigrationCleanupSubstate =>
      text().withDefault(const Constant(''))();

  @override
  String get tableName => 'system_settings';

  @override
  Set<Column> get primaryKey => {id};
}
