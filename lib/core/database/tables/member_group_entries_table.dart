import 'package:drift/drift.dart';

@DataClassName('MemberGroupEntryRow')
class MemberGroupEntries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get memberId => text()();
  TextColumn get pkGroupUuid => text().nullable()();
  TextColumn get pkMemberUuid => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // Local-only push intent for PluralKit bidirectional group membership sync.
  // Stored as a string ('none' | 'push_add' | 'push_remove') because Drift's
  // textEnum() generates an extra import; bare text + repository-side parsing
  // matches existing enum-as-string columns (e.g. pendingFrontingMigrationMode).
  // NOT in prismSyncSchema — push intent is per-device and never crosses Prism's
  // own CRDT sync. See docs/plans/pk-group-membership-push.md.
  TextColumn get pendingPkOp =>
      text().withDefault(const Constant('none')).clientDefault(() => 'none')();

  // Local-only RECENCY STAMP: row creation or latest local membership
  // mutation (H6/M15), refreshed on insert, local re-add, remove intent, and
  // inbound CRDT apply — NOT an immutable creation time despite the name.
  // Not in prismSyncSchema, so it never crosses CRDT sync. Consumers (H6b
  // reconcile grace, M15 retry cap) fail safe on a too-recent stamp.
  // Nullable for the v33 ADD COLUMN; a NULL reads as "not recent / not
  // expired" so it neither leaks a membership nor drops an intent.
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(DateTime.now)();

  /// LOCAL-ONLY incarnation generation for the row's canonical PK-backed entry
  /// sync entity id. 0 = the legacy `sha256('<g> <m>')[:16]` id (the separator
  /// is a NUL byte); N>=1 = the salted `sha256('<g> <m> g<N>')[:16]`
  /// incarnation minted after a tombstone burned generation N-1. NOT in
  /// prismSyncSchema: each device tracks its own live incarnation independently
  /// and the id itself (not this counter) crosses the wire. See
  /// `lib/core/sync/pk_incarnation_ids.dart` + [TombstoneGate].
  IntColumn get syncGeneration =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
