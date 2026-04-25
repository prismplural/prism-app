import 'package:drift/drift.dart';

class Members extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get pronouns => text().nullable()();
  TextColumn get emoji => text().withDefault(const Constant('❔'))();
  IntColumn get age => integer().nullable()();
  TextColumn get bio => text().nullable()();
  BlobColumn get avatarImageData => blob().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isAdmin => boolean().withDefault(const Constant(false))();
  BoolColumn get customColorEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get customColorHex => text().nullable()();
  TextColumn get parentSystemId => text().nullable()();
  // PluralKit fields
  TextColumn get pluralkitUuid => text().nullable()();
  TextColumn get pluralkitId => text().nullable()();
  // PK `display_name` — shown as alias in PK, "markdown-capable nickname".
  TextColumn get displayName => text().nullable()();
  // PK `birthday` raw wire string (YYYY-MM-DD). Sentinel `0004-MM-DD` means
  // the year is hidden. Stored as-is, parsed only for display.
  TextColumn get birthday => text().nullable()();
  // PK `proxy_tags` raw JSON array: `[{"prefix": "...", "suffix": "..."}]`.
  // Read-only in Prism — no editor UI.
  TextColumn get proxyTagsJson => text().nullable()();
  // PK `banner` URL. Stored for future banner UI; no bytes download yet.
  TextColumn get pkBannerUrl => text().nullable()();
  // Set when the user picked "Skip" or "Don't push" for this member in the
  // mapping flow. Durable — never re-offered until the user clears it.
  BoolColumn get pluralkitSyncIgnored =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get markdownEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // -- Plan 02 (PK deletion push) --
  //
  // R1: Link epoch stamped at delete time. Local-only (not synced). Compared
  // against `pluralkit_sync_state.link_epoch` at push time; a mismatch aborts
  // the PK DELETE (tombstone was made under a prior link / disconnected).
  IntColumn get deleteIntentEpoch => integer().nullable()();
  // R6: Cross-device coordination timestamp (ms since epoch, synced). First
  // device that takes ownership of pushing the DELETE stamps this; other
  // devices skip while it's fresh (< 10 min) and take over once stale.
  IntColumn get deletePushStartedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
