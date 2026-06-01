// Phase 6 parity test for `addMemberToGroup` vs. the new batch path.
//
// `docs/plans/sp-import-perf-quick-wins.md` mandates this test before any
// `MemberGroupsDao.batchInsertEntries` replacement lands. Five scenarios,
// each running BOTH the live-edit `addMemberToGroup` flow AND the new batch
// `batchInsertEntries + manual captured-tuple push` flow on the same input,
// then asserting the resulting row in the DB and the captured emission
// tuples are byte-equal between the two paths.
//
// If a scenario diverges, the batch path is wrong — the failure points at
// the helper that needs fixing, not a parity-harness mystery.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';

/// Captured emission, stripped down to the wire-level fields the SP import
/// post-commit replay actually re-emits. `op` is always `create` for the
/// `addMemberToGroup` path; the test asserts emission absence (case 2) and
/// emission deduplication (case 4) explicitly.
class _CapturedEmission {
  const _CapturedEmission(this.table, this.entityId, this.opType, this.fields);
  final String table;
  final String entityId;
  final SyncRecordOpType opType;
  final Map<String, dynamic> fields;

  @override
  String toString() =>
      '_CapturedEmission($table, $entityId, ${opType.name}, $fields)';
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository({List<member_domain.Member> members = const []})
    : _members = List.of(members);

  final List<member_domain.Member> _members;

  @override
  Future<void> clearPluralKitLink(String id) async {}

  @override
  Future<void> createMember(member_domain.Member member) async {
    _members.add(member);
  }

  @override
  Future<void> deleteMember(String id) async {
    _members.removeWhere((member) => member.id == id);
  }

  @override
  Future<List<member_domain.Member>> getAllMembers() async => _members;

  @override
  Future<List<member_domain.Member>> getAllMembersIncludingDeleted() async =>
      _members;

  @override
  Future<int> getCount() async => _members.length;

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      const [];

  @override
  Future<member_domain.Member?> getMemberById(String id) async {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      _members.where((member) => ids.contains(member.id)).toList();

  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> updateMember(member_domain.Member member) async {
    final index = _members.indexWhere((existing) => existing.id == member.id);
    if (index >= 0) {
      _members[index] = member;
    }
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> excludePluralKitSync(String id) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> resumePluralKitSync(String id) async => throw UnimplementedError();

  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();

  @override
  Stream<List<member_domain.Member>> watchAllMembers() =>
      throw UnimplementedError();

  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();

  @override
  Future<({member_domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

member_domain.Member _member({required String id, String? pluralkitUuid}) =>
    member_domain.Member(
      id: id,
      name: id,
      emoji: '?',
      isActive: true,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitUuid: pluralkitUuid,
    );

Future<void> _insertGroup(
  AppDatabase db, {
  required String id,
  String? pluralkitUuid,
  bool syncSuppressed = false,
}) async {
  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pluralkitUuid),
          syncSuppressed: Value(syncSuppressed),
        ),
      );
}

AppDatabase _freshDb() => AppDatabase(NativeDatabase.memory());

/// Run [body] under `suppressAndCapture`, returning the captured emissions.
Future<List<_CapturedEmission>> _captureUnderSuppress(
  Future<void> Function() body,
) async {
  final captured = <_CapturedEmission>[];
  await SyncRecordMixin.suppressAndCapture(body, (op) {
    captured.add(
      _CapturedEmission(
        op.table,
        op.entityId,
        op.opType,
        Map<String, dynamic>.of(op.fields),
      ),
    );
  });
  return captured;
}

/// Dump every member_group_entries row (including soft-deleted), sorted by id.
Future<List<MemberGroupEntryRow>> _allEntries(AppDatabase db) async {
  final rows = await db.select(db.memberGroupEntries).get();
  rows.sort((a, b) => a.id.compareTo(b.id));
  return rows;
}

void main() {
  group('addMemberToGroup vs batchInsertEntries parity', () {
    tearDown(() {
      // Defensive: suppress + capture clears its sink in `finally`. Pin the
      // invariant so an errored test doesn't leak into the next one.
      expect(
        SyncRecordMixin.isSuppressed,
        isFalse,
        reason: 'suppression flag leaked between tests',
      );
      expect(
        SyncRecordMixin.hasCaptureSink,
        isFalse,
        reason: 'capture sink leaked between tests',
      );
    });

    test(
      'scenario 1: normal group, plain insert + one captured create',
      () async {
        // ── live-edit path ────────────────────────────────────────────────
        final liveDb = _freshDb();
        addTearDown(liveDb.close);
        await _insertGroup(liveDb, id: 'grp-1');
        final liveMembers = _FakeMemberRepository(
          members: [_member(id: 'mem-1')],
        );
        final liveRepo = DriftMemberGroupsRepository(
          liveDb.memberGroupsDao,
          null,
          memberRepository: liveMembers,
        );
        final liveCaptured = await _captureUnderSuppress(() async {
          await liveRepo.addMemberToGroup('grp-1', 'mem-1', 'entry-1');
        });
        final liveEntries = await _allEntries(liveDb);

        // ── batch path ────────────────────────────────────────────────────
        final batchDb = _freshDb();
        addTearDown(batchDb.close);
        await _insertGroup(batchDb, id: 'grp-1');
        final batchCaptured = await _captureUnderSuppress(() async {
          final group = await batchDb.memberGroupsDao.getGroupById('grp-1');
          expect(group, isNotNull);
          const entryId = 'entry-1';
          const companion = MemberGroupEntriesCompanion(
            id: Value(entryId),
            groupId: Value('grp-1'),
            memberId: Value('mem-1'),
            pkGroupUuid: Value(null),
            pkMemberUuid: Value(null),
            isDeleted: Value(false),
            pendingPkOp: Value('none'),
          );
          await batchDb.memberGroupsDao.batchInsertEntries([companion]);
          const stored = MemberGroupEntryRow(
            id: entryId,
            groupId: 'grp-1',
            memberId: 'mem-1',
            pkGroupUuid: null,
            pkMemberUuid: null,
            isDeleted: false,
            pendingPkOp: 'none',
          );
          await _emitCaptured(
            batchDb,
            'member_group_entries',
            entryId,
            stored,
            group!,
            member: null,
          );
          await _appendBatchManualOrderAndEmitCaptured(batchDb, group, [
            entryId,
          ]);
        });
        final batchEntries = await _allEntries(batchDb);

        _expectEntriesByteEqual(batchEntries, liveEntries);
        await _expectGroupSortStatesByteEqual(batchDb, liveDb, 'grp-1');
        _expectEmissionsByteEqual(batchCaptured, liveCaptured);
        expect(
          liveCaptured.length,
          2,
          reason:
              'normal group: one entry create and one group sort_state update',
        );
      },
    );

    test(
      'scenario 2: sync-suppressed group, NO emission on either path',
      () async {
        // ── live-edit path ────────────────────────────────────────────────
        final liveDb = _freshDb();
        addTearDown(liveDb.close);
        await _insertGroup(liveDb, id: 'grp-supp', syncSuppressed: true);
        final liveMembers = _FakeMemberRepository(
          members: [_member(id: 'mem-1')],
        );
        final liveRepo = DriftMemberGroupsRepository(
          liveDb.memberGroupsDao,
          null,
          memberRepository: liveMembers,
        );
        final liveCaptured = await _captureUnderSuppress(() async {
          await liveRepo.addMemberToGroup('grp-supp', 'mem-1', 'entry-1');
        });
        final liveEntries = await _allEntries(liveDb);

        // ── batch path ────────────────────────────────────────────────────
        final batchDb = _freshDb();
        addTearDown(batchDb.close);
        await _insertGroup(batchDb, id: 'grp-supp', syncSuppressed: true);
        final batchCaptured = await _captureUnderSuppress(() async {
          final group = await batchDb.memberGroupsDao.getGroupById('grp-supp');
          expect(group, isNotNull);
          const entryId = 'entry-1';
          const companion = MemberGroupEntriesCompanion(
            id: Value(entryId),
            groupId: Value('grp-supp'),
            memberId: Value('mem-1'),
            pkGroupUuid: Value(null),
            pkMemberUuid: Value(null),
            isDeleted: Value(false),
            pendingPkOp: Value('none'),
          );
          await batchDb.memberGroupsDao.batchInsertEntries([companion]);
          // Caller must gate emission on isGroupSyncSuppressed; the suppress
          // bit is on this group, so no captured tuple is pushed.
          final isSuppressed = await batchDb.memberGroupsDao
              .isGroupSyncSuppressed('grp-supp');
          expect(
            isSuppressed,
            isTrue,
            reason:
                'Test setup invariant: group must be sync-suppressed for scenario 2',
          );
          await _appendBatchManualOrderAndEmitCaptured(batchDb, group!, [
            entryId,
          ]);
        });
        final batchEntries = await _allEntries(batchDb);

        _expectEntriesByteEqual(batchEntries, liveEntries);
        await _expectGroupSortStatesByteEqual(batchDb, liveDb, 'grp-supp');
        _expectEmissionsByteEqual(batchCaptured, liveCaptured);
        expect(
          liveCaptured,
          isEmpty,
          reason: 'sync-suppressed group: emission must be skipped',
        );
        expect(
          batchCaptured,
          isEmpty,
          reason:
              'batch path must gate on isGroupSyncSuppressed and skip emission',
        );
      },
    );

    test(
      'scenario 3: PK-linked group + PK-linked member sets pendingPkOp=push_add',
      () async {
        const groupId = 'grp-pk';
        const memberId = 'mem-pk';
        const pkGroupUuid = 'pk-grp-uuid';
        const pkMemberUuid = 'pk-mem-uuid';

        // ── live-edit path ────────────────────────────────────────────────
        final liveDb = _freshDb();
        addTearDown(liveDb.close);
        // PK-backed group emissions are gated on `pkGroupSyncV2Enabled` —
        // default `false`. Flip it on so both paths exercise the emission
        // branch the plan calls out (`scenario 3` asserts pk_* keys present
        // in the captured tuple).
        await liveDb.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
        await _insertGroup(liveDb, id: groupId, pluralkitUuid: pkGroupUuid);
        final liveMembers = _FakeMemberRepository(
          members: [_member(id: memberId, pluralkitUuid: pkMemberUuid)],
        );
        final liveRepo = DriftMemberGroupsRepository(
          liveDb.memberGroupsDao,
          null,
          memberRepository: liveMembers,
        );
        final liveCaptured = await _captureUnderSuppress(() async {
          await liveRepo.addMemberToGroup(groupId, memberId, 'fallback-id');
        });
        final liveEntries = await _allEntries(liveDb);

        expect(liveEntries.length, 1);
        final liveRow = liveEntries.single;
        expect(liveRow.pendingPkOp, 'push_add');
        expect(liveRow.pkGroupUuid, pkGroupUuid);
        expect(liveRow.pkMemberUuid, pkMemberUuid);
        expect(
          liveRow.id,
          isNot('fallback-id'),
          reason: 'live path uses deterministic SHA id, not fallback',
        );

        // ── batch path ────────────────────────────────────────────────────
        final batchDb = _freshDb();
        addTearDown(batchDb.close);
        await batchDb.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
        await _insertGroup(batchDb, id: groupId, pluralkitUuid: pkGroupUuid);
        final batchMembers = _FakeMemberRepository(
          members: [_member(id: memberId, pluralkitUuid: pkMemberUuid)],
        );
        final batchCaptured = await _captureUnderSuppress(() async {
          final group = await batchDb.memberGroupsDao.getGroupById(groupId);
          final member = await batchMembers.getMemberById(memberId);
          expect(group, isNotNull);
          expect(member, isNotNull);
          final entryId = _computeDeterministicEntryId(
            pkGroupUuid: group!.pluralkitUuid!,
            pkMemberUuid: member!.pluralkitUuid!,
          );
          expect(
            entryId,
            liveRow.id,
            reason: 'batch path id must match live deterministic id',
          );
          final companion = MemberGroupEntriesCompanion(
            id: Value(entryId),
            groupId: Value(group.id),
            memberId: Value(member.id),
            pkGroupUuid: Value(group.pluralkitUuid),
            pkMemberUuid: Value(member.pluralkitUuid),
            isDeleted: const Value(false),
            pendingPkOp: const Value('push_add'),
          );
          await batchDb.memberGroupsDao.batchInsertEntries([companion]);
          final stored = MemberGroupEntryRow(
            id: entryId,
            groupId: group.id,
            memberId: member.id,
            pkGroupUuid: group.pluralkitUuid,
            pkMemberUuid: member.pluralkitUuid,
            isDeleted: false,
            pendingPkOp: 'push_add',
          );
          await _emitCaptured(
            batchDb,
            'member_group_entries',
            entryId,
            stored,
            group,
            member: member,
          );
          await _appendBatchManualOrderAndEmitCaptured(batchDb, group, [
            entryId,
          ]);
        });
        final batchEntries = await _allEntries(batchDb);

        _expectEntriesByteEqual(batchEntries, liveEntries);
        await _expectGroupSortStatesByteEqual(batchDb, liveDb, groupId);
        _expectEmissionsByteEqual(batchCaptured, liveCaptured);
        expect(liveCaptured.length, 2);
        final entryEmission = liveCaptured.firstWhere(
          (emission) => emission.table == 'member_group_entries',
        );
        expect(entryEmission.fields['pk_group_uuid'], pkGroupUuid);
        expect(entryEmission.fields['pk_member_uuid'], pkMemberUuid);
      },
    );

    test(
      'scenario 4: entry already exists — both paths early-return',
      () async {
        const groupId = 'grp-dup';
        const memberId = 'mem-1';
        const existingId = 'pre-existing';

        // ── live-edit path ────────────────────────────────────────────────
        final liveDb = _freshDb();
        addTearDown(liveDb.close);
        await _insertGroup(liveDb, id: groupId);
        await liveDb
            .into(liveDb.memberGroupEntries)
            .insert(
              MemberGroupEntriesCompanion.insert(
                id: existingId,
                groupId: groupId,
                memberId: memberId,
              ),
            );
        final liveMembers = _FakeMemberRepository(
          members: [_member(id: memberId)],
        );
        final liveRepo = DriftMemberGroupsRepository(
          liveDb.memberGroupsDao,
          null,
          memberRepository: liveMembers,
        );
        final liveCaptured = await _captureUnderSuppress(() async {
          // Live path's `addMemberToGroup` early-returns when findEntry hits.
          await liveRepo.addMemberToGroup(groupId, memberId, 'new-entry-id');
        });
        final liveEntries = await _allEntries(liveDb);

        // ── batch path ────────────────────────────────────────────────────
        final batchDb = _freshDb();
        addTearDown(batchDb.close);
        await _insertGroup(batchDb, id: groupId);
        await batchDb
            .into(batchDb.memberGroupEntries)
            .insert(
              MemberGroupEntriesCompanion.insert(
                id: existingId,
                groupId: groupId,
                memberId: memberId,
              ),
            );
        final batchCaptured = await _captureUnderSuppress(() async {
          // The batch path's caller pre-filters duplicates. Pre-fetch active
          // entries by (group, member) — if a row exists, skip insert + emit.
          final existing = await batchDb.memberGroupsDao.findEntry(
            groupId,
            memberId,
          );
          if (existing != null) {
            // Skip — entry already present, no insert, no emission.
            return;
          }
          // Unreachable in this scenario; included for symmetry.
          await batchDb.memberGroupsDao.batchInsertEntries(const []);
        });
        final batchEntries = await _allEntries(batchDb);

        _expectEntriesByteEqual(batchEntries, liveEntries);
        await _expectGroupSortStatesByteEqual(batchDb, liveDb, groupId);
        _expectEmissionsByteEqual(batchCaptured, liveCaptured);
        expect(
          liveCaptured,
          isEmpty,
          reason: 'duplicate skip: no emission on either path',
        );
        expect(batchCaptured, isEmpty);
        expect(liveEntries.length, 1);
        expect(liveEntries.single.id, existingId);
        expect(batchEntries.length, 1);
        expect(batchEntries.single.id, existingId);
      },
    );

    test(
      'scenario 5: prior soft-deleted PK entry — both paths revive at the same SHA id',
      () async {
        const groupId = 'grp-pk-revival';
        const memberId = 'mem-pk';
        const pkGroupUuid = 'pk-grp-uuid';
        const pkMemberUuid = 'pk-mem-uuid';
        final deterministicId = _computeDeterministicEntryId(
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
        );

        // ── live-edit path ────────────────────────────────────────────────
        final liveDb = _freshDb();
        addTearDown(liveDb.close);
        // PK-backed group emissions gate on `pkGroupSyncV2Enabled`; enable it
        // so the live revival path actually emits the captured create.
        await liveDb.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
        await _insertGroup(liveDb, id: groupId, pluralkitUuid: pkGroupUuid);
        await liveDb
            .into(liveDb.memberGroupEntries)
            .insert(
              MemberGroupEntriesCompanion.insert(
                id: deterministicId,
                groupId: groupId,
                memberId: memberId,
                pkGroupUuid: const Value(pkGroupUuid),
                pkMemberUuid: const Value(pkMemberUuid),
                isDeleted: const Value(true),
                pendingPkOp: const Value('push_remove'),
              ),
            );
        final liveMembers = _FakeMemberRepository(
          members: [_member(id: memberId, pluralkitUuid: pkMemberUuid)],
        );
        final liveRepo = DriftMemberGroupsRepository(
          liveDb.memberGroupsDao,
          null,
          memberRepository: liveMembers,
        );
        final liveCaptured = await _captureUnderSuppress(() async {
          await liveRepo.addMemberToGroup(groupId, memberId, 'fallback');
        });
        final liveEntries = await _allEntries(liveDb);
        expect(liveEntries.length, 1);
        expect(liveEntries.single.id, deterministicId);
        expect(
          liveEntries.single.isDeleted,
          isFalse,
          reason: 'live revival clears is_deleted',
        );
        expect(
          liveEntries.single.pendingPkOp,
          'push_add',
          reason: 'live revival overwrites pending_pk_op with push_add',
        );

        // ── batch path ────────────────────────────────────────────────────
        final batchDb = _freshDb();
        addTearDown(batchDb.close);
        await batchDb.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
        await _insertGroup(batchDb, id: groupId, pluralkitUuid: pkGroupUuid);
        await batchDb
            .into(batchDb.memberGroupEntries)
            .insert(
              MemberGroupEntriesCompanion.insert(
                id: deterministicId,
                groupId: groupId,
                memberId: memberId,
                pkGroupUuid: const Value(pkGroupUuid),
                pkMemberUuid: const Value(pkMemberUuid),
                isDeleted: const Value(true),
                pendingPkOp: const Value('push_remove'),
              ),
            );
        final batchMembers = _FakeMemberRepository(
          members: [_member(id: memberId, pluralkitUuid: pkMemberUuid)],
        );
        final batchCaptured = await _captureUnderSuppress(() async {
          final group = await batchDb.memberGroupsDao.getGroupById(groupId);
          final member = await batchMembers.getMemberById(memberId);
          expect(group, isNotNull);
          expect(member, isNotNull);
          final companion = MemberGroupEntriesCompanion(
            id: Value(deterministicId),
            groupId: Value(group!.id),
            memberId: Value(member!.id),
            pkGroupUuid: Value(group.pluralkitUuid),
            pkMemberUuid: Value(member.pluralkitUuid),
            isDeleted: const Value(false),
            pendingPkOp: const Value('push_add'),
          );
          // `batchInsertEntries` uses `insertAllOnConflictUpdate` so the prior
          // tombstone row at this deterministic id is revived in place.
          await batchDb.memberGroupsDao.batchInsertEntries([companion]);
          final stored = MemberGroupEntryRow(
            id: deterministicId,
            groupId: group.id,
            memberId: member.id,
            pkGroupUuid: group.pluralkitUuid,
            pkMemberUuid: member.pluralkitUuid,
            isDeleted: false,
            pendingPkOp: 'push_add',
          );
          await _emitCaptured(
            batchDb,
            'member_group_entries',
            deterministicId,
            stored,
            group,
            member: member,
          );
          await _appendBatchManualOrderAndEmitCaptured(batchDb, group, [
            deterministicId,
          ]);
        });
        final batchEntries = await _allEntries(batchDb);

        _expectEntriesByteEqual(batchEntries, liveEntries);
        await _expectGroupSortStatesByteEqual(batchDb, liveDb, groupId);
        _expectEmissionsByteEqual(batchCaptured, liveCaptured);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Compute the same deterministic 16-char hex id the repo's PK path emits.
/// Mirrors `_entryEntityIdFromPkRefs` in
/// `drift_member_groups_repository.dart`:
///   `sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]`.
String _computeDeterministicEntryId({
  required String pkGroupUuid,
  required String pkMemberUuid,
}) {
  final digest = crypto.sha256.convert(
    utf8.encode('$pkGroupUuid\u0000$pkMemberUuid'),
  );
  return digest.toString().substring(0, 16);
}

void _expectEmissionsByteEqual(
  List<_CapturedEmission> actual,
  List<_CapturedEmission> expected,
) {
  expect(
    actual.length,
    expected.length,
    reason:
        'emission count diverged: live=${expected.length}, batch=${actual.length}',
  );
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i].table, expected[i].table, reason: 'emission $i: table');
    expect(
      actual[i].entityId,
      expected[i].entityId,
      reason: 'emission $i: entityId',
    );
    expect(actual[i].opType, expected[i].opType, reason: 'emission $i: opType');
    expect(
      actual[i].fields,
      expected[i].fields,
      reason: 'emission $i: fields drift',
    );
  }
}

void _expectEntriesByteEqual(
  List<MemberGroupEntryRow> actual,
  List<MemberGroupEntryRow> expected,
) {
  expect(actual.length, expected.length, reason: 'row count diverged');
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i].id, expected[i].id, reason: 'row $i: id');
    expect(actual[i].groupId, expected[i].groupId, reason: 'row $i: groupId');
    expect(
      actual[i].memberId,
      expected[i].memberId,
      reason: 'row $i: memberId',
    );
    expect(
      actual[i].pkGroupUuid,
      expected[i].pkGroupUuid,
      reason: 'row $i: pkGroupUuid',
    );
    expect(
      actual[i].pkMemberUuid,
      expected[i].pkMemberUuid,
      reason: 'row $i: pkMemberUuid',
    );
    expect(
      actual[i].isDeleted,
      expected[i].isDeleted,
      reason: 'row $i: isDeleted',
    );
    expect(
      actual[i].pendingPkOp,
      expected[i].pendingPkOp,
      reason: 'row $i: pendingPkOp',
    );
  }
}

/// Mimic the captured-tuple push the SP importer does after a batch insert.
///
/// Uses the public-static `memberGroupEntryFields` helper as the single
/// source of truth for the wire-level field map. The actual emission goes
/// through `syncRecordCreate` under suppression, which forwards to the
/// capture sink installed by `_captureUnderSuppress`.
Future<void> _emitCaptured(
  AppDatabase db,
  String table,
  String entityId,
  MemberGroupEntryRow stored,
  MemberGroupRow group, {
  member_domain.Member? member,
}) async {
  final repo = DriftMemberGroupsRepository(db.memberGroupsDao, null);
  await repo.syncRecordCreate(
    table,
    entityId,
    DriftMemberGroupsRepository.memberGroupEntryFields(
      stored,
      group: group,
      member: member,
    ),
  );
}

Future<MemberGroupRow> _appendBatchManualOrder(
  AppDatabase db,
  MemberGroupRow group,
  List<String> entryIds,
) async {
  final current = tryDecodeSortState(group.sortState);
  if (current == null || !current.isManual) return group;

  final seen = current.manualOrder.toSet();
  final appended = <String>[];
  for (final entryId in entryIds) {
    if (seen.add(entryId)) appended.add(entryId);
  }
  if (appended.isEmpty) return group;

  final nextState = current.copyWith(
    manualOrder: [...current.manualOrder, ...appended],
  );
  await db.memberGroupsDao.updateGroupSortState(
    group.id,
    MemberGroupMapper.encodeSortStateForColumn(nextState),
  );
  return await db.memberGroupsDao.getGroupById(group.id) ?? group;
}

Future<void> _emitGroupUpdateCapturedIfAllowed(
  AppDatabase db,
  MemberGroupRow group,
) async {
  if (await db.memberGroupsDao.isGroupSyncSuppressed(group.id)) return;
  final pkGroupUuid = group.pluralkitUuid;
  if (pkGroupUuid != null && pkGroupUuid.isNotEmpty) {
    final settings = await db.systemSettingsDao.getSettings();
    if (!settings.pkGroupSyncV2Enabled) return;
  }

  final repo = DriftMemberGroupsRepository(db.memberGroupsDao, null);
  await repo.syncRecordUpdate(
    'member_groups',
    _groupEntityId(group),
    <String, dynamic>{
      'sort_state': sanitizeSortStateForEmission(
        group.sortState,
        contextId: group.id,
      ),
    },
  );
}

String _groupEntityId(MemberGroupRow group) {
  final pkGroupUuid = group.pluralkitUuid;
  if (pkGroupUuid != null && pkGroupUuid.isNotEmpty) {
    return 'pk-group:$pkGroupUuid';
  }
  return group.id;
}

Future<void> _appendBatchManualOrderAndEmitCaptured(
  AppDatabase db,
  MemberGroupRow group,
  List<String> entryIds,
) async {
  final updated = await _appendBatchManualOrder(db, group, entryIds);
  if (updated.sortState == group.sortState) return;
  await _emitGroupUpdateCapturedIfAllowed(db, updated);
}

Future<void> _expectGroupSortStatesByteEqual(
  AppDatabase actual,
  AppDatabase expected,
  String groupId,
) async {
  final actualGroup = await actual.memberGroupsDao.getGroupById(groupId);
  final expectedGroup = await expected.memberGroupsDao.getGroupById(groupId);
  expect(actualGroup?.sortState, expectedGroup?.sortState);
}
