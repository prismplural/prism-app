// R1/F14 incarnation tests for DriftMemberGroupsRepository.
//
// A PK-linked re-add of a member whose deterministic gen-0 entry id is burned
// (a peer tombstone the engine holds) must mint the next incarnation and emit
// the create under the gen-1 id, persisting sync_generation; a subsequent
// remove must delete the gen-1 id, not the burned gen-0 one. Without a wired
// engine (gate==null) the legacy gen-0 behavior is preserved byte-for-byte.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';

const _groupUuid = 'group-uuid-1';
const _memberUuid = 'member-uuid-1';

class _Emission {
  const _Emission(this.table, this.entityId, this.opType);
  final String table;
  final String entityId;
  final SyncRecordOpType opType;
  @override
  String toString() => '$table/$entityId/${opType.name}';
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this._members);
  final List<member_domain.Member> _members;

  @override
  Future<member_domain.Member?> getMemberById(String id) async {
    for (final m in _members) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      _members.where((m) => ids.contains(m.id)).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [TombstoneGate] whose readFieldValue says exactly [tombstonedIds] are
/// is_deleted=true; everything else has no field version (live).
TombstoneGate _gateTombstoning(Set<String> tombstonedIds) {
  return TombstoneGate((table, entityId, field) async {
    if (field != 'is_deleted') return null;
    return tombstonedIds.contains(entityId) ? 'true' : null;
  });
}

member_domain.Member _member() => member_domain.Member(
  id: 'mem-1',
  name: 'Mem',
  emoji: '?',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
  pluralkitUuid: _memberUuid,
);

Future<void> _insertPkGroup(AppDatabase db) async {
  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(
          id: 'pk-group-$_groupUuid',
          name: 'G',
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: const Value(_groupUuid),
        ),
      );
  await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
}

Future<List<_Emission>> _capture(Future<void> Function() body) async {
  final out = <_Emission>[];
  await SyncRecordMixin.suppressAndCapture(body, (op) {
    out.add(_Emission(op.table, op.entityId, op.opType));
  });
  return out;
}

void main() {
  late AppDatabase db;
  late DriftMemberGroupsRepository repo;

  final gen0EntryId = deriveEntryIncarnationEntityId(_groupUuid, _memberUuid, 0)!;
  final gen1EntryId = deriveEntryIncarnationEntityId(_groupUuid, _memberUuid, 1)!;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _insertPkGroup(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('gen-0 entry id is byte-identical to the legacy NUL-separated sha', () {
    // Pin the binding format: gen0 must equal the pre-R1 derivation
    // (sha256('<g>\u0000<m>')[:16]) so already synced entries keep identity.
    final legacy = crypto.sha256
        .convert(utf8.encode('$_groupUuid\u0000$_memberUuid'))
        .toString()
        .substring(0, 16);
    expect(gen0EntryId, legacy);
    expect(gen0EntryId, isNot(equals(gen1EntryId)));
    // gen1 uses the space-separated ' g1' salt.
    final salted = crypto.sha256
        .convert(utf8.encode('$_groupUuid $_memberUuid g1'))
        .toString()
        .substring(0, 16);
    expect(gen1EntryId, salted);
  });

  test(
    're-add over a burned gen-0 tombstone emits the create under gen-1 and '
    'persists sync_generation; a later remove deletes gen-1, not gen-0',
    () async {
      repo = DriftMemberGroupsRepository(
        db.memberGroupsDao,
        null,
        memberRepository: _FakeMemberRepository([_member()]),
        // The engine holds a tombstone on the gen-0 id (peer removal).
        tombstoneGate: _gateTombstoning({gen0EntryId}),
      );

      // Seed the gen-0 row as a soft-deleted tombstone (mirrors a prior remove
      // whose op was applied locally).
      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0EntryId,
              groupId: 'pk-group-$_groupUuid',
              memberId: 'mem-1',
              pkGroupUuid: const Value(_groupUuid),
              pkMemberUuid: const Value(_memberUuid),
              isDeleted: const Value(true),
            ),
          );

      // ── Re-add ────────────────────────────────────────────────────────────
      final addEmissions = await _capture(() async {
        await repo.addMemberToGroup('pk-group-$_groupUuid', 'mem-1', 'entry-x');
      });

      final entryCreates = addEmissions
          .where(
            (e) =>
                e.table == 'member_group_entries' &&
                e.opType == SyncRecordOpType.create,
          )
          .toList();
      expect(entryCreates.length, 1, reason: 'exactly one entry create');
      expect(
        entryCreates.single.entityId,
        gen1EntryId,
        reason: 'create must target the gen-1 incarnation, not the burned gen-0',
      );

      final liveRow = await db.memberGroupsDao.findEntry(
        'pk-group-$_groupUuid',
        'mem-1',
      );
      expect(liveRow, isNotNull);
      expect(liveRow!.id, gen1EntryId);
      expect(liveRow.syncGeneration, 1);
      expect(liveRow.isDeleted, isFalse);

      // ── Remove again ──────────────────────────────────────────────────────
      final removeEmissions = await _capture(() async {
        await repo.removeMemberFromGroup('pk-group-$_groupUuid', 'mem-1');
      });
      final entryDeletes = removeEmissions
          .where(
            (e) =>
                e.table == 'member_group_entries' &&
                e.opType == SyncRecordOpType.delete,
          )
          .toList();
      expect(entryDeletes.length, 1, reason: 'exactly one entry delete');
      expect(
        entryDeletes.single.entityId,
        gen1EntryId,
        reason: 'delete must target the live gen-1 id, not the burned gen-0',
      );
    },
  );

  test(
    'minting gen-1 neutralizes the same-edge soft-deleted push_remove row '
    '(H6c regression — no orphaned remove for the orchestrator to push)',
    () async {
      // Blocker 1: removeMemberFromGroup left a soft-deleted gen-0 row carrying
      // pending_pk_op='push_remove'. A re-add mints a NEW gen-1 id (gen-0 is
      // burned), so the upsert never reaches that stale row. The push
      // orchestrator iterates ALL pending rows and pushes adds before removes
      // with no same-edge dedup, so the orphaned remove would fire after the
      // fresh add and pull the member back out of the user's real PluralKit
      // group. The re-add must hard-delete the superseded same-edge row so the
      // minted gen-1 push_add is the ONLY pending intent for the edge.
      repo = DriftMemberGroupsRepository(
        db.memberGroupsDao,
        null,
        memberRepository: _FakeMemberRepository([_member()]),
        tombstoneGate: _gateTombstoning({gen0EntryId}),
      );

      await db
          .into(db.memberGroupEntries)
          .insert(
            MemberGroupEntriesCompanion.insert(
              id: gen0EntryId,
              groupId: 'pk-group-$_groupUuid',
              memberId: 'mem-1',
              pkGroupUuid: const Value(_groupUuid),
              pkMemberUuid: const Value(_memberUuid),
              isDeleted: const Value(true),
              pendingPkOp: const Value('push_remove'),
            ),
          );

      await _capture(() async {
        await repo.addMemberToGroup('pk-group-$_groupUuid', 'mem-1', 'entry-x');
      });

      // The orphaned gen-0 push_remove row is gone.
      final gen0Row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(gen0EntryId))).getSingleOrNull();
      expect(gen0Row, isNull, reason: 'superseded gen-0 row hard-deleted');

      // The only pending intent for the edge is the gen-1 push_add.
      final pending = await db.memberGroupsDao.entriesWithPendingPkOp();
      expect(pending.map((e) => e.id), [gen1EntryId]);
      expect(pending.single.pendingPkOp, 'push_add');
      expect(pending.single.isDeleted, isFalse);
    },
  );

  test('fresh add with no tombstone keeps gen-0 (legacy behavior)', () async {
    repo = DriftMemberGroupsRepository(
      db.memberGroupsDao,
      null,
      memberRepository: _FakeMemberRepository([_member()]),
      tombstoneGate: _gateTombstoning(const {}),
    );

    final emissions = await _capture(() async {
      await repo.addMemberToGroup('pk-group-$_groupUuid', 'mem-1', 'entry-x');
    });
    final create = emissions.singleWhere(
      (e) =>
          e.table == 'member_group_entries' &&
          e.opType == SyncRecordOpType.create,
    );
    expect(create.entityId, gen0EntryId);

    final row = await db.memberGroupsDao.findEntry(
      'pk-group-$_groupUuid',
      'mem-1',
    );
    expect(row!.syncGeneration, 0);
  });

  test('no gate wired (gate==null) keeps gen-0 byte-for-byte', () async {
    repo = DriftMemberGroupsRepository(
      db.memberGroupsDao,
      null,
      memberRepository: _FakeMemberRepository([_member()]),
    );

    final emissions = await _capture(() async {
      await repo.addMemberToGroup('pk-group-$_groupUuid', 'mem-1', 'entry-x');
    });
    final create = emissions.singleWhere(
      (e) =>
          e.table == 'member_group_entries' &&
          e.opType == SyncRecordOpType.create,
    );
    expect(create.entityId, gen0EntryId);
  });
}
