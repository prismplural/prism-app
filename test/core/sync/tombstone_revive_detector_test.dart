// R6-diag detector tests for the absorbing-tombstone-revive-holes family.
//
// The detector is DIAGNOSTIC-ONLY: it counts Drift-live rows whose current
// incarnation id is tombstoned in the sync engine, and it must NEVER emit a
// sync op while doing so (repair is owned by the reconciliation layer). These
// tests pin both halves: correct counting and zero emissions.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/core/sync/tombstone_revive_detector.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

const _groupUuid = 'group-uuid-1';
const _memberUuid = 'member-uuid-1';

/// A [TombstoneGate] reporting exactly [tombstonedIds] as is_deleted=true (the
/// Rust field_versions source of truth); every other id reads as live.
TombstoneGate _gateTombstoning(Set<String> tombstonedIds) {
  return TombstoneGate((table, entityId, field) async {
    if (field != 'is_deleted') return null;
    return tombstonedIds.contains(entityId) ? 'true' : null;
  });
}

Future<void> _insertGroup(
  AppDatabase db, {
  required String id,
  String? pkUuid,
  int generation = 0,
  bool deleted = false,
}) async {
  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: 'G',
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pkUuid),
          syncGeneration: Value(generation),
          isDeleted: Value(deleted),
        ),
      );
}

Future<void> _insertEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  String? pkGroupUuid,
  String? pkMemberUuid,
  int generation = 0,
  bool deleted = false,
}) async {
  await db
      .into(db.memberGroupEntries)
      .insert(
        MemberGroupEntriesCompanion.insert(
          id: id,
          groupId: groupId,
          memberId: 'mem-1',
          pkGroupUuid: Value(pkGroupUuid),
          pkMemberUuid: Value(pkMemberUuid),
          syncGeneration: Value(generation),
          isDeleted: Value(deleted),
        ),
      );
}

Future<void> _insertMember(
  AppDatabase db, {
  required String id,
  String? pkUuid,
}) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          name: 'M',
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pkUuid),
        ),
      );
}

Future<void> _insertSentinel(AppDatabase db, {bool deleted = false}) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: unknownSentinelMemberId,
          name: 'Unknown',
          createdAt: DateTime.utc(2026, 1, 1),
          isDeleted: Value(deleted),
        ),
      );
}

void main() {
  late AppDatabase db;

  final gen0EntryId = deriveEntryIncarnationEntityId(
    _groupUuid,
    _memberUuid,
    0,
  )!;
  final gen0GroupId = deriveGroupIncarnationEntityId(_groupUuid, 0);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('null gate reports gateAvailable=false and zero counts', () async {
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    final detector = TombstoneRevivedRowsDetector(db, null);
    final report = await detector.scan();
    expect(report.gateAvailable, isFalse);
    expect(report.totalDiverged, 0);
    expect(report.hasDivergence, isFalse);
  });

  test('a present gate but unconfigured engine reports gateAvailable=false '
      '(no false all-clean)', () async {
    // A constructed-but-unconfigured engine reads is_deleted=null for EVERY id
    // (the FFI returns None when there is no sync_id), which would otherwise
    // look like "no divergence". `engineConfigured: false` must surface
    // gateAvailable=false instead so the diagnostic does not mislead.
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    final detector = TombstoneRevivedRowsDetector(
      db,
      // Even a gate that WOULD flag the row is short-circuited by the flag.
      _gateTombstoning({gen0GroupId}),
      engineConfigured: false,
    );
    final report = await detector.scan();
    expect(report.gateAvailable, isFalse);
    expect(report.totalDiverged, 0);
  });

  test('live group whose canonical id is tombstoned is counted', () async {
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    final detector = TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen0GroupId}),
    );
    final report = await detector.scan();
    expect(report.gateAvailable, isTrue);
    expect(report.groups.count, 1);
    expect(report.groups.entityIds, [gen0GroupId]);
    expect(report.totalDiverged, 1);
  });

  test('live group whose id is live (field version present) is NOT counted',
      () async {
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    // Field version exists but is_deleted=false -> live, not a tombstone.
    final gate = TombstoneGate((table, entityId, field) async {
      if (field != 'is_deleted') return null;
      return entityId == gen0GroupId ? 'false' : null;
    });
    final report = await TombstoneRevivedRowsDetector(db, gate).scan();
    expect(report.groups.count, 0);
    expect(report.totalDiverged, 0);
  });

  test('a tombstoned group row that is itself deleted is NOT counted',
      () async {
    // Only LIVE Drift rows can diverge; a deleted local row is in agreement.
    await _insertGroup(
      db,
      id: 'pk-group-$_groupUuid',
      pkUuid: _groupUuid,
      deleted: true,
    );
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen0GroupId}),
    ).scan();
    expect(report.groups.count, 0);
  });

  test('a group without a pluralkit_uuid is ignored entirely', () async {
    await _insertGroup(db, id: 'local-group', pkUuid: null);
    final report = await TombstoneRevivedRowsDetector(
      db,
      // Tombstone the raw row id to prove it is never even consulted.
      _gateTombstoning({'local-group'}),
    ).scan();
    expect(report.groups.count, 0);
  });

  test('live entry whose incarnation id is tombstoned is counted', () async {
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    await _insertEntry(
      db,
      id: gen0EntryId,
      groupId: 'pk-group-$_groupUuid',
      pkGroupUuid: _groupUuid,
      pkMemberUuid: _memberUuid,
    );
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen0EntryId}),
    ).scan();
    expect(report.entries.count, 1);
    expect(report.entries.entityIds, [gen0EntryId]);
  });

  test('entry detection is generation-aware (gen-1 row uses the salted id)',
      () async {
    final gen1EntryId = deriveEntryIncarnationEntityId(
      _groupUuid,
      _memberUuid,
      1,
    )!;
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    await _insertEntry(
      db,
      id: gen1EntryId,
      groupId: 'pk-group-$_groupUuid',
      pkGroupUuid: _groupUuid,
      pkMemberUuid: _memberUuid,
      generation: 1,
    );
    // The burned gen-0 id is tombstoned, but the live row is at gen-1 — its
    // current id is live, so it must NOT be flagged.
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen0EntryId}),
    ).scan();
    expect(report.entries.count, 0);
    // Conversely, tombstoning the row's own gen-1 id flags it.
    final report2 = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen1EntryId}),
    ).scan();
    expect(report2.entries.count, 1);
    expect(report2.entries.entityIds, [gen1EntryId]);
  });

  test('an entry with no PK ref on the row AND no PK-linked group/member is '
      'ignored', () async {
    // Non-PK edge: the row emits under its own opaque id, never reused after a
    // delete, so it can never be in this divergence class.
    await _insertGroup(db, id: 'local-group', pkUuid: null);
    await _insertEntry(
      db,
      id: 'raw-entry',
      groupId: 'local-group',
      pkGroupUuid: null,
      pkMemberUuid: null,
    );
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({'raw-entry'}),
    ).scan();
    expect(report.entries.count, 0);
  });

  test('a legacy entry lacking entry-level PK refs is still detected via the '
      'group/member pluralkit_uuid fallback (matches the emit path)', () async {
    // The repository emit path derives the entry id from the entry's own PK
    // refs ELSE the joined group/member pluralkit_uuid. A legacy row with NULL
    // entry-level refs but a PK-linked group + member emits (and can diverge)
    // under the deterministic sha id, so the detector must see it too.
    await _insertMember(db, id: 'pk-mem', pkUuid: _memberUuid);
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    await db
        .into(db.memberGroupEntries)
        .insert(
          MemberGroupEntriesCompanion.insert(
            id: 'legacy-entry',
            groupId: 'pk-group-$_groupUuid',
            memberId: 'pk-mem',
            // No entry-level PK refs — the fallback must resolve them.
          ),
        );
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen0EntryId}),
    ).scan();
    expect(report.entries.count, 1);
    expect(report.entries.entityIds, [gen0EntryId]);
  });

  test('live tombstoned Unknown sentinel is counted', () async {
    await _insertSentinel(db);
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({unknownSentinelMemberId}),
    ).scan();
    expect(report.sentinelMember.count, 1);
    expect(report.sentinelMember.entityIds, [unknownSentinelMemberId]);
  });

  test('a live but non-tombstoned sentinel is NOT counted', () async {
    await _insertSentinel(db);
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({}),
    ).scan();
    expect(report.sentinelMember.count, 0);
  });

  test('a deleted sentinel row is NOT counted even if tombstoned', () async {
    await _insertSentinel(db, deleted: true);
    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({unknownSentinelMemberId}),
    ).scan();
    expect(report.sentinelMember.count, 0);
  });

  test('a full scan over diverged rows emits ZERO sync ops', () async {
    // Seed one diverged row on every surface, then prove the detector never
    // captures an emission while counting them.
    await _insertGroup(db, id: 'pk-group-$_groupUuid', pkUuid: _groupUuid);
    await _insertEntry(
      db,
      id: gen0EntryId,
      groupId: 'pk-group-$_groupUuid',
      pkGroupUuid: _groupUuid,
      pkMemberUuid: _memberUuid,
    );
    await _insertSentinel(db);

    final captured = <String>[];
    SyncRecordMixin.installCaptureSinkForTesting(
      (op) => captured.add('${op.table}/${op.entityId}/${op.opType.name}'),
    );
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    final report = await TombstoneRevivedRowsDetector(
      db,
      _gateTombstoning({gen0GroupId, gen0EntryId, unknownSentinelMemberId}),
    ).scan();

    expect(report.totalDiverged, 3);
    expect(report.hasDivergence, isTrue);
    expect(captured, isEmpty, reason: 'detector must never emit a sync op');
  });
}
