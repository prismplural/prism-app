// R1 adapter parse + generation-guard tests for both PK-backed id shapes:
// group incarnation ids (`pk-group-g<N>:<uuid>`) and entry incarnation ids
// (salted gen-N shas). The adapter must (a) apply a strictly-newer incarnation
// as a sanctioned revive (revive the row + bump sync_generation), and
// (b) refuse a hardDelete whose tombstone targets an OLDER incarnation than the
// live row (the tombstone-then-revive flap guard).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';

const _gUuid = 'pk-g-uuid-1';
const _mUuid = 'pk-m-uuid-1';

DriftSyncEntity _entityFor(AppDatabase db, String tableName) {
  final adapter = buildSyncAdapterWithCompletion(db).adapter;
  return adapter.entities.singleWhere((e) => e.tableName == tableName);
}

Future<void> _seedMemberAndGroup(AppDatabase db) async {
  final now = DateTime.utc(2026, 1, 1);
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: 'm-local',
          name: 'Alice',
          createdAt: now,
          pluralkitUuid: const Value(_mUuid),
        ),
      );
}

void main() {
  group('group incarnation parse + guard', () {
    test('a strictly-newer group incarnation create revives + bumps gen',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groups = _entityFor(db, 'member_groups');

      // Local gen-0 row, tombstoned (a peer removal applied locally).
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$_gUuid',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
              isDeleted: const Value(true),
            ),
          );

      // Incoming gen-1 incarnation create with an explicit is_deleted=false.
      final gen1Id = deriveGroupIncarnationEntityId(_gUuid, 1);
      await groups.applyFields(gen1Id, {
        'name': 'G',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'pluralkit_uuid': _gUuid,
        'is_deleted': false,
      });

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.pluralkitUuid.equals(_gUuid))).getSingle();
      expect(row.isDeleted, isFalse, reason: 'sanctioned revive');
      expect(row.syncGeneration, 1, reason: 'advanced to the incoming gen');

      // An alias is recorded for the incarnation id so a later sparse patch
      // under that id resolves back to this row.
      final alias = await (db.select(
        db.pkGroupSyncAliases,
      )..where((t) => t.legacyEntityId.equals(gen1Id))).getSingleOrNull();
      expect(alias, isNotNull);
      expect(alias!.pkGroupUuid, _gUuid);
    });

    test('a lower/equal incarnation never demotes sync_generation', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groups = _entityFor(db, 'member_groups');

      // Local row already at gen 2.
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$_gUuid',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
              syncGeneration: const Value(2),
            ),
          );

      // A stale gen-0 (canonical) update arrives.
      await groups.applyFields('pk-group:$_gUuid', {
        'name': 'G-renamed',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'pluralkit_uuid': _gUuid,
        'is_deleted': false,
      });

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.pluralkitUuid.equals(_gUuid))).getSingle();
      expect(row.syncGeneration, 2, reason: 'gen never decreases');
    });

    test('hardDelete is skipped when the live row is a newer incarnation',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groups = _entityFor(db, 'member_groups');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$_gUuid',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
              syncGeneration: const Value(1),
            ),
          );

      // The burned gen-0 tombstone is re-delivered.
      await groups.hardDelete('pk-group:$_gUuid');

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.pluralkitUuid.equals(_gUuid))).getSingleOrNull();
      expect(row, isNotNull, reason: 'gen-1 row survives the gen-0 tombstone');
      expect(row!.syncGeneration, 1);
    });

    test(
        'a fields-borne gen-0 is_deleted=true never tombstones a newer-gen '
        'group row', () async {
      // Blocker 2(b): the group applyFields wrote is_deleted unguarded. A stale
      // gen-0 tombstone (re-pushed by sync_bootstrap as a record_create with
      // is_deleted=true, or replayed from quarantine) resolves by pk uuid to the
      // live gen-1 row and must NOT flip it to deleted.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groups = _entityFor(db, 'member_groups');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$_gUuid',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
              syncGeneration: const Value(1),
            ),
          );

      // Stale gen-0 canonical op carrying is_deleted=true.
      await groups.applyFields('pk-group:$_gUuid', {
        'name': 'G',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'pluralkit_uuid': _gUuid,
        'is_deleted': true,
      });

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.pluralkitUuid.equals(_gUuid))).getSingle();
      expect(
        row.isDeleted,
        isFalse,
        reason: 'the older-incarnation tombstone leaves the gen-1 group live',
      );
      expect(row.syncGeneration, 1);
    });

    test(
        'a gen-1 group tombstone deletes the live gen-1 row keyed by its local '
        'id (blocker 3 group variant)', () async {
      // The live gen-1 group row is keyed by its own local id (`pk-group-<uuid>`)
      // but carries sync_generation=1. A legitimate gen-1 tombstone arrives
      // keyed by the `pk-group-g1:<uuid>` incarnation id. The resolve-for-delete
      // path must recover the uuid from the incarnation prefix and resolve the
      // live row by pk uuid, then the generation guard (1 == 1) lets the delete
      // proceed.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groups = _entityFor(db, 'member_groups');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$_gUuid',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
              syncGeneration: const Value(1),
            ),
          );

      await groups.hardDelete(deriveGroupIncarnationEntityId(_gUuid, 1));

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.pluralkitUuid.equals(_gUuid))).getSingleOrNull();
      expect(row, isNull, reason: 'the gen-1 tombstone deletes the gen-1 group');
    });

    test('hardDelete proceeds when the tombstone matches the row generation',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groups = _entityFor(db, 'member_groups');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$_gUuid',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
            ),
          );

      await groups.hardDelete('pk-group:$_gUuid');

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.pluralkitUuid.equals(_gUuid))).getSingleOrNull();
      expect(row, isNull, reason: 'gen-0 tombstone deletes the gen-0 row');
    });
  });

  group('entry incarnation parse + guard', () {
    test('a strictly-newer entry incarnation create bumps the row gen',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMemberAndGroup(db);
      final entries = _entityFor(db, 'member_group_entries');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'g-local',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
            ),
          );

      // Tombstoned gen-0 entry row.
      final gen0 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 0)!;
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0,
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              isDeleted: const Value(true),
            ),
          );

      // Incoming gen-1 incarnation create.
      final gen1 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 1)!;
      await entries.applyFields(gen1, {
        'pk_group_uuid': _gUuid,
        'pk_member_uuid': _mUuid,
        'is_deleted': false,
      });

      final live = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(gen1))).getSingleOrNull();
      expect(live, isNotNull);
      expect(live!.isDeleted, isFalse);
      expect(live.syncGeneration, 1);
    });

    test(
        'a stale gen-0 entry op never soft-deletes / re-roots the live gen-1 '
        'edge (canonical-collapse redirect guard)', () async {
      // Blocker 2(a), redirect arm: a stale gen-0 (canonical) live op arrives
      // while the live edge is a separate gen-1 row. The redirect must NOT
      // soft-delete the live gen-1 row and re-root the edge at a fresh gen-0
      // row (that is the F14 burned-id split-brain). is_deleted=false so the op
      // reaches the redirect body rather than the no-existing-row tombstone
      // short-circuit.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMemberAndGroup(db);
      final entries = _entityFor(db, 'member_group_entries');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'g-local',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
            ),
          );

      final gen1 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 1)!;
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen1,
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              syncGeneration: const Value(1),
            ),
          );

      final gen0 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 0)!;
      await entries.applyFields(gen0, {
        'pk_group_uuid': _gUuid,
        'pk_member_uuid': _mUuid,
        'is_deleted': false,
      });

      final gen1Row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(gen1))).getSingleOrNull();
      expect(gen1Row, isNotNull);
      expect(
        gen1Row!.isDeleted,
        isFalse,
        reason: 'the live gen-1 row is not soft-deleted by the stale gen-0 op',
      );
      expect(gen1Row.syncGeneration, 1, reason: 'generation never regresses');
      // No fresh gen-0 row was rooted: only the gen-1 row exists for this edge.
      final all = await (db.select(
        db.memberGroupEntries,
      )..where(
            (t) =>
                t.pkGroupUuid.equals(_gUuid) & t.pkMemberUuid.equals(_mUuid),
          ))
          .get();
      expect(all.map((r) => r.id).toSet(), {gen1});
    });

    test(
        'a fields-borne gen-0 is_deleted=true never tombstones a collapsed '
        'gen-1 row', () async {
      // Blocker 2(a), is_deleted arm: the live edge collapsed onto the gen-0 id
      // carrying sync_generation=1. A stale gen-0 op with is_deleted=true must
      // NOT flip that newer row to deleted (the guarded isDeletedValue leaves it
      // untouched when the incoming generation is older than the stored one).
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMemberAndGroup(db);
      final entries = _entityFor(db, 'member_group_entries');

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'g-local',
              name: 'G',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value(_gUuid),
            ),
          );

      final gen0 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 0)!;
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0,
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              syncGeneration: const Value(1), // collapsed onto gen-0 id @ gen 1
            ),
          );

      await entries.applyFields(gen0, {
        'pk_group_uuid': _gUuid,
        'pk_member_uuid': _mUuid,
        'is_deleted': true,
      });

      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(gen0))).getSingleOrNull();
      expect(row, isNotNull);
      expect(
        row!.isDeleted,
        isFalse,
        reason: 'the older-incarnation tombstone leaves the gen-1 row live',
      );
      expect(row.syncGeneration, 1);
    });

    test(
        'entry hardDelete skips the gen-0 tombstone when the live edge '
        'COLLAPSED onto the gen-0 id at sync_generation=1', () async {
      // The case the guard actually protects (blocker 4): after a canonical-
      // collapse redirect the live edge lives at the gen-0 SHA but carries
      // sync_generation=1. A re-delivered gen-0 tombstone keyed by that same id
      // must NOT delete it. Seeding the row at the gen-0 id with gen=1 (not at
      // the gen-1 sha) is what makes the guard load-bearing — a delete-by-id
      // would otherwise hit this exact row.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entries = _entityFor(db, 'member_group_entries');

      final gen0 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 0)!;
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0,
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              syncGeneration: const Value(1),
            ),
          );

      await entries.hardDelete(gen0);

      final live = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(gen0))).getSingleOrNull();
      expect(
        live,
        isNotNull,
        reason: 'the collapsed gen-1 edge survives the gen-0 tombstone',
      );
      expect(live!.syncGeneration, 1);
    });

    test(
        'entry hardDelete skips the gen-0 tombstone with a stale soft-deleted '
        'gen-0 row + a separate live gen-1 row', () async {
      // Two-row variant: a stale soft-deleted gen-0 row (left behind by a
      // re-add) PLUS the live gen-1 row at the gen-1 sha. The gen-0 tombstone
      // resolves the edge by exact-id (the soft-deleted row), but the live row
      // for the edge is gen-1, so the guard must skip the delete and the live
      // gen-1 row must survive untouched.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entries = _entityFor(db, 'member_group_entries');

      final gen0 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 0)!;
      final gen1 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 1)!;
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0,
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              isDeleted: const Value(true),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen1,
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              syncGeneration: const Value(1),
            ),
          );

      await entries.hardDelete(gen0);

      final live = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(gen1))).getSingleOrNull();
      expect(
        live,
        isNotNull,
        reason: 'the live gen-1 row survives the gen-0 tombstone',
      );
      expect(live!.isDeleted, isFalse);
    });

    test(
        'entry hardDelete removes the collapsed live edge when the tombstone '
        'matches its generation', () async {
      // Blocker 3 positive case: a legitimate gen-1 tombstone arrives keyed by
      // the gen-1 sha, but the live edge collapsed onto the gen-0 sha carrying
      // sync_generation=1. A delete-by-wire-id would no-op (no row at the gen-1
      // sha) and the edge would live forever; the generation-aware logical
      // delete must find and remove the collapsed row.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entries = _entityFor(db, 'member_group_entries');

      final gen0 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 0)!;
      final gen1 = deriveEntryIncarnationEntityId(_gUuid, _mUuid, 1)!;
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0, // collapsed onto the gen-0 id…
              groupId: 'g-local',
              memberId: 'm-local',
              pkGroupUuid: const Value(_gUuid),
              pkMemberUuid: const Value(_mUuid),
              syncGeneration: const Value(1), // …but carrying gen 1.
            ),
          );

      await entries.hardDelete(gen1);

      final remaining = await (db.select(
        db.memberGroupEntries,
      )..where(
            (t) =>
                t.pkGroupUuid.equals(_gUuid) & t.pkMemberUuid.equals(_mUuid),
          ))
          .get();
      expect(
        remaining,
        isEmpty,
        reason: 'the gen-1 tombstone deletes the collapsed gen-1 edge',
      );
    });
  });
}
