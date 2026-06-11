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
  // mutation (2026-06 PK audit H6/M15; semantics broadened by the wave-3
  // verifier — issue 1). NOT in prismSyncSchema — the sync layer's
  // toSyncFields allowlist for this table omits it, so it never crosses
  // Prism's CRDT sync. Despite the column name (kept for the v33 migration's
  // sake), this is NOT an immutable creation time. It is refreshed by:
  //   - INSERT `clientDefault` (fresh local rows);
  //   - the repository's addMemberToGroup companion (covers the upsert
  //     REVIVE path, where clientDefault does not fire);
  //   - the DAO's softDeleteEntryWithPendingOp (removeMemberFromGroup) —
  //     so the push retry cap measures INTENT age, not row age;
  //   - every inbound CRDT apply onto this table's row
  //     (drift_sync_adapter._applyMemberGroupEntryFields) — so a revive of a
  //     stale tombstone counts as "recent" on the applying device.
  // Two consumers, both fail-safe under a too-recent stamp:
  //   - H6b removal-reconcile grace: entries younger than
  //     `PkGroupsImporter.removalRecencyGrace` are never reconcile-deleted;
  //   - M15 push retry cap: pending ops older than
  //     `PkGroupsImporter.pushRetryMaxAge` are given up on.
  //
  // Nullable so the v33 `ALTER TABLE ... ADD COLUMN` succeeds without a
  // SQL-level constant default (SQLite forbids ADD COLUMN ... NOT NULL with
  // no default on a populated table; that is why `pending_pk_op` also carries
  // a `withDefault`). The migration backfills existing rows to "now"; a NULL
  // that somehow survives is treated as "no stamp → not recent → eligible for
  // reconcile, not expired for the cap" so a missing stamp neither leaks a PK
  // membership nor drops an intent.
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(DateTime.now)();

  @override
  Set<Column> get primaryKey => {id};
}
