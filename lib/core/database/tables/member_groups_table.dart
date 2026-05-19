import 'package:drift/drift.dart';

@DataClassName('MemberGroupRow')
class MemberGroups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get colorHex => text().nullable()();
  TextColumn get emoji => text().nullable()();
  BlobColumn get avatarImageData => blob().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get parentGroupId => text().nullable()();
  IntColumn get groupType => integer().withDefault(const Constant(0))();
  TextColumn get filterRules => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// PluralKit 5-char short ID (display only, never used for identity matching).
  TextColumn get pluralkitId => text().nullable()();

  /// PluralKit canonical UUID — the sole identity key for PK-linked groups.
  TextColumn get pluralkitUuid => text().nullable()();

  /// Last time we observed this group in a PK pull. Synced so all devices
  /// agree on the "stale" UI hint for groups that have disappeared from PK.
  DateTimeColumn get lastSeenFromPkAt => dateTime().nullable()();

  /// Local-only migration guard for ambiguous legacy PK duplicates. Suppressed
  /// rows remain usable locally, but must not emit ordinary Prism sync ops
  /// until the user resolves them.
  BoolColumn get syncSuppressed =>
      boolean().withDefault(const Constant(false))();

  /// Local-only review hint for ambiguous rows that likely map to a canonical
  /// PK group UUID but cannot be merged safely without user confirmation.
  TextColumn get suspectedPkGroupUuid => text().nullable()();

  /// Per-group sort state, stored as JSON: `{"mode": <int>, "order": [...]}`.
  /// `mode` is the int index of `GroupSortMode` (manual/nameAsc/nameDesc/
  /// recentDesc). `order` is the manual-mode list of entry ids.
  ///
  /// Persisted as a single column so the (mode, manualOrder) pair always
  /// converges to one device's complete state under per-field LWW sync —
  /// see `docs/plans/2026-05-14-group-member-ordering.md` §"Design decision".
  TextColumn get sortState =>
      text().withDefault(const Constant('{"mode":0,"order":[]}'))();

  @override
  Set<Column> get primaryKey => {id};
}
