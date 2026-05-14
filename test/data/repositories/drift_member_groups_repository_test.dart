import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';

class _TestMemberGroupsDao extends MemberGroupsDao {
  _TestMemberGroupsDao(super.db);

  final suppressedGroupIds = <String>{};

  /// When non-null, every call to [updateGroupSortState] throws this. Used
  /// to drive the atomicity regression — simulates an exception in the
  /// parent-update step of addMemberToGroup so we can assert the
  /// surrounding transaction rolls back the entry insert.
  Object? failUpdateGroupSortStateWith;

  @override
  Future<bool> isGroupSyncSuppressed(String groupId) async {
    return suppressedGroupIds.contains(groupId);
  }

  @override
  Future<int> updateGroupSortState(String groupId, String sortStateJson) {
    final injected = failUpdateGroupSortStateWith;
    if (injected != null) {
      throw injected;
    }
    return super.updateGroupSortState(groupId, sortStateJson);
  }
}

class _RecordingRepo extends DriftMemberGroupsRepository {
  _RecordingRepo(MemberGroupsDao dao, MemberRepository memberRepository)
      : super(dao, null, memberRepository: memberRepository);

  final creates = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];
  final deletes = <Map<String, String>>[];

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    creates.add({
      'table': table,
      'entityId': entityId,
      'fields': Map<String, dynamic>.from(fields),
    });
  }

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    updates.add({
      'table': table,
      'entityId': entityId,
      'fields': Map<String, dynamic>.from(fields),
    });
  }

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    deletes.add({'table': table, 'entityId': entityId});
  }
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository([List<member_domain.Member>? members])
      : _members = members ?? <member_domain.Member>[];

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

  // The repository code under test only calls getMemberById and
  // getMembersByIds. Throwing on the rest keeps unintended call sites obvious.
  @override
  Future<void> clearPluralKitLink(String id) async => throw UnimplementedError();
  @override
  Future<void> createMember(member_domain.Member member) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) async => throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getAllMembers() async =>
      throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getAllMembersIncludingDeleted() async =>
      throw UnimplementedError();
  @override
  Future<int> getCount() async => throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      throw UnimplementedError();
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async =>
      throw UnimplementedError();
  @override
  Future<void> updateMember(member_domain.Member member) async =>
      throw UnimplementedError();
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
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();
  @override
  Future<({member_domain.Member member, bool wasCreated})>
      ensureUnknownSentinelMember() => throw UnimplementedError();
}

member_domain.Member _member({required String id}) => member_domain.Member(
      id: id,
      name: id,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _seedGroup(
  AppDatabase db, {
  required String id,
  GroupSortState? sortState,
}) {
  final state = sortState ?? GroupSortState.manualEmpty;
  return db.into(db.memberGroups).insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          sortState: Value(MemberGroupMapper.encodeSortStateForColumn(state)),
        ),
      );
}

Future<void> _seedEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  required String memberId,
}) {
  return db.into(db.memberGroupEntries).insert(
        MemberGroupEntriesCompanion.insert(
          id: id,
          groupId: groupId,
          memberId: memberId,
        ),
      );
}

Future<GroupSortState> _readSortState(AppDatabase db, String groupId) async {
  final row = await (db.select(db.memberGroups)
        ..where((g) => g.id.equals(groupId)))
      .getSingle();
  final decoded = tryDecodeSortState(row.sortState);
  expect(decoded, isNotNull, reason: 'sort_state must always decode to a valid state');
  return decoded!;
}

int _groupUpdates(_RecordingRepo repo) =>
    repo.updates.where((u) => u['table'] == 'member_groups').length;

Map<String, Object?>? _lastGroupUpdate(_RecordingRepo repo) {
  for (final update in repo.updates.reversed) {
    if (update['table'] == 'member_groups') return update;
  }
  return null;
}

void main() {
  late AppDatabase db;
  late _TestMemberGroupsDao dao;
  late _RecordingRepo repo;

  Future<void> setupRepo({List<member_domain.Member> members = const []}) async {
    db = AppDatabase(NativeDatabase.memory());
    dao = _TestMemberGroupsDao(db);
    repo = _RecordingRepo(dao, _FakeMemberRepository([...members]));
  }

  tearDown(() async {
    await db.close();
  });

  group('setGroupManualOrderSnapshot', () {
    test('valid permutation: writes sort_state, returns applied, one sync update',
        () async {
      await setupRepo();
      await _seedGroup(db, id: 'g1');
      await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');
      await _seedEntry(db, id: 'e2', groupId: 'g1', memberId: 'm2');
      await _seedEntry(db, id: 'e3', groupId: 'g1', memberId: 'm3');

      final result =
          await repo.setGroupManualOrderSnapshot('g1', ['e3', 'e1', 'e2']);

      expect(result, isA<SnapshotApplied>());
      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.manual);
      expect(stored.manualOrder, ['e3', 'e1', 'e2']);

      expect(_groupUpdates(repo), 1);
      final update = _lastGroupUpdate(repo)!;
      expect(update['entityId'], 'g1');
      final fields = update['fields']! as Map<String, dynamic>;
      expect(fields.containsKey('sort_state'), isTrue);
      final emittedState =
          tryDecodeSortState(fields['sort_state'] as String?)!;
      expect(emittedState.manualOrder, ['e3', 'e1', 'e2']);
    });

    test('stale permutation missing a concurrently-added id: recovered.appendedIds',
        () async {
      await setupRepo();
      await _seedGroup(db, id: 'g1');
      // UI dragged e1, e2, e3. Meanwhile a peer add for e4 landed.
      await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');
      await _seedEntry(db, id: 'e2', groupId: 'g1', memberId: 'm2');
      await _seedEntry(db, id: 'e3', groupId: 'g1', memberId: 'm3');
      await _seedEntry(db, id: 'e4', groupId: 'g1', memberId: 'm4');

      final result = await repo.setGroupManualOrderSnapshot(
        'g1',
        ['e3', 'e1', 'e2'],
      );

      expect(result, isA<SnapshotRecovered>());
      final recovered = result as SnapshotRecovered;
      expect(recovered.droppedIds, isEmpty);
      expect(recovered.appendedIds, ['e4']);

      final stored = await _readSortState(db, 'g1');
      // Final: (supplied - dropped) ++ appended-sorted-by-id
      expect(stored.manualOrder, ['e3', 'e1', 'e2', 'e4']);
    });

    test(
        'stale permutation containing a concurrently-tombstoned id: recovered.droppedIds',
        () async {
      await setupRepo();
      await _seedGroup(db, id: 'g1');
      await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');
      await _seedEntry(db, id: 'e2', groupId: 'g1', memberId: 'm2');
      // UI dragged with e3 in the list, but a peer tombstoned it.
      await db.into(db.memberGroupEntries).insert(
            MemberGroupEntriesCompanion.insert(
              id: 'e3',
              groupId: 'g1',
              memberId: 'm3',
              isDeleted: const Value(true),
            ),
          );

      final result = await repo.setGroupManualOrderSnapshot(
        'g1',
        ['e3', 'e1', 'e2'],
      );

      expect(result, isA<SnapshotRecovered>());
      final recovered = result as SnapshotRecovered;
      expect(recovered.droppedIds, ['e3']);
      expect(recovered.appendedIds, isEmpty);

      final stored = await _readSortState(db, 'g1');
      expect(stored.manualOrder, ['e1', 'e2']);
    });
  });

  group('setGroupSortMode', () {
    test('writes nameAsc + preserves prior manualOrder', () async {
      await setupRepo();
      await _seedGroup(
        db,
        id: 'g1',
        sortState: const GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['e1', 'e2', 'e3'],
        ),
      );

      await repo.setGroupSortMode('g1', GroupSortMode.nameAsc);

      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.nameAsc);
      expect(
        stored.manualOrder,
        ['e1', 'e2', 'e3'],
        reason: 'manualOrder must be preserved across the mode flip',
      );
      expect(_groupUpdates(repo), 1);
    });

    test(
        'setGroupSortMode(manual) on group in nameAsc with empty manualOrder '
        'keeps manualOrder empty (bare mode flip)', () async {
      await setupRepo();
      await _seedGroup(
        db,
        id: 'g1',
        sortState: GroupSortState.locked(GroupSortMode.nameAsc),
      );

      await repo.setGroupSortMode('g1', GroupSortMode.manual);

      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.manual);
      expect(stored.manualOrder, isEmpty);
    });
  });

  group('addMemberToGroup sort_state maintenance', () {
    test('manual group: appends new entry id, emits one parent sync update',
        () async {
      await setupRepo(members: [_member(id: 'm1'), _member(id: 'm2')]);
      await _seedGroup(
        db,
        id: 'g1',
        sortState: const GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['existing-e0'],
        ),
      );

      await repo.addMemberToGroup('g1', 'm1', 'e1');

      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.manual);
      expect(stored.manualOrder, ['existing-e0', 'e1']);
      // One parent sync update from the manual-order append. (The entry
      // create's sync record goes to member_group_entries, not the group.)
      expect(_groupUpdates(repo), 1);
    });

    test('nameAsc group: entry created, sortState unchanged, no parent update',
        () async {
      await setupRepo(members: [_member(id: 'm1')]);
      await _seedGroup(
        db,
        id: 'g1',
        sortState: GroupSortState.locked(GroupSortMode.nameAsc),
      );

      await repo.addMemberToGroup('g1', 'm1', 'e1');

      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.nameAsc);
      expect(stored.manualOrder, isEmpty);
      expect(_groupUpdates(repo), 0);
    });
  });

  group('removeMemberFromGroup sort_state maintenance', () {
    test('manual group: prunes id from manualOrder, emits parent sync update',
        () async {
      await setupRepo(members: [_member(id: 'm1'), _member(id: 'm2')]);
      await _seedGroup(
        db,
        id: 'g1',
        sortState: const GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['e1', 'e2'],
        ),
      );
      await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');
      await _seedEntry(db, id: 'e2', groupId: 'g1', memberId: 'm2');

      await repo.removeMemberFromGroup('g1', 'm1');

      final stored = await _readSortState(db, 'g1');
      expect(stored.manualOrder, ['e2']);
      expect(_groupUpdates(repo), 1);
    });

    test('nameAsc group: entry tombstoned, sortState unchanged, no parent update',
        () async {
      await setupRepo(members: [_member(id: 'm1')]);
      await _seedGroup(
        db,
        id: 'g1',
        sortState: GroupSortState.locked(GroupSortMode.nameAsc),
      );
      await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');

      await repo.removeMemberFromGroup('g1', 'm1');

      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.nameAsc);
      expect(stored.manualOrder, isEmpty);
      expect(_groupUpdates(repo), 0);
    });

    // P1.3 regression: setGroupSortMode preserves manualOrder when flipping
    // to a sorted mode. A subsequent remove in that sorted mode must NOT
    // prune the preserved order, and must NOT emit a parent sync update —
    // the plan §"Sort-mode invariants" requires sorted modes leave
    // sortState untouched on add/remove.
    test(
      'nameAsc group with preserved manualOrder: remove leaves manualOrder '
      'intact and emits no parent update',
      () async {
        await setupRepo(members: [_member(id: 'm1'), _member(id: 'm2'),
          _member(id: 'm3')]);
        await _seedGroup(
          db,
          id: 'g1',
          sortState: const GroupSortState(
            // Mode = nameAsc, but manualOrder is preserved from a prior
            // manual state (setGroupSortMode preserves it across the flip).
            mode: GroupSortMode.nameAsc,
            manualOrder: ['a', 'b', 'c'],
          ),
        );
        await _seedEntry(db, id: 'b', groupId: 'g1', memberId: 'm2');

        await repo.removeMemberFromGroup('g1', 'm2');

        final stored = await _readSortState(db, 'g1');
        expect(stored.mode, GroupSortMode.nameAsc);
        expect(
          stored.manualOrder,
          ['a', 'b', 'c'],
          reason:
              'sorted-mode remove must leave the preserved manualOrder '
              'untouched',
        );
        expect(_groupUpdates(repo), 0,
            reason:
                'sorted-mode remove must not emit a parent sync update');

        // The entry itself IS tombstoned — the parent state is just left
        // alone.
        final entryRow = await (db.select(db.memberGroupEntries)
              ..where((e) => e.id.equals('b')))
            .getSingle();
        expect(entryRow.isDeleted, isTrue);
      },
    );
  });

  group('cross-device convergence', () {
    // TODO(batch-5.3): Concurrent-reorder convergence P0 regression test.
    // Requires two DriftMemberGroupsRepository instances on separate DBs and
    // the adapter's apply path with an HLC tiebreak — that infra lives in
    // the integration-test layer (see plan §Task 5.3 scenario 4). The
    // single-field design makes this convergence true by construction (one
    // pending_op per write, deterministic LWW), so the assertion lives at
    // the integration test where a full sync engine roundtrip is feasible.
    test(
      'two repositories with opposing manual snapshots converge to one HLC winner',
      () {
        // Stub: see TODO above. Batch 5.3 fills this in with the full
        // adapter + HLC infrastructure.
      },
      skip: 'Stubbed for batch-5.3 integration test infra',
    );

    // TODO(batch-5.3): Cross-device sort-mode-only race regression test.
    // Same infrastructure requirement as above — needs the full sync
    // adapter to demonstrate that a setGroupSortMode call and a
    // setGroupManualOrderSnapshot call converge atomically because they
    // both write to the single sort_state field. The repository-layer
    // assertion is "encodeSortStateForColumn always emits the full
    // (mode, order) pair," already enforced by the mapper-side tests in
    // Batch 2.2.
    test(
      'sort-mode-only race: loser writes are not visible (single-field LWW)',
      () {
        // Stub: see TODO above. Batch 5.3 fills this in with the full
        // adapter + HLC infrastructure.
      },
      skip: 'Stubbed for batch-5.3 integration test infra',
    );
  });

  // Smoke check that the encoded JSON round-trips through tryDecodeSortState,
  // protecting against future encoder/decoder drift.
  test('encoded sort_state is parseable JSON with mode + order keys', () async {
    await setupRepo();
    await _seedGroup(db, id: 'g1');
    await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');

    await repo.setGroupManualOrderSnapshot('g1', ['e1']);

    final row = await (db.select(db.memberGroups)
          ..where((g) => g.id.equals('g1')))
        .getSingle();
    final raw = row.sortState;
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    expect(parsed.containsKey('mode'), isTrue);
    expect(parsed.containsKey('order'), isTrue);
  });

  // ── P1.5: duplicate detection in setGroupManualOrderSnapshot ────────────
  group('setGroupManualOrderSnapshot duplicate detection', () {
    test(
      'duplicate id in supplied permutation: returns recovered, stored '
      'manualOrder is deduped (first occurrence wins), duplicate flagged '
      'via droppedIds',
      () async {
        await setupRepo();
        await _seedGroup(db, id: 'g1');
        await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');
        await _seedEntry(db, id: 'e2', groupId: 'g1', memberId: 'm2');
        await _seedEntry(db, id: 'e3', groupId: 'g1', memberId: 'm3');

        // UI handed us a list with a duplicate. The stored column must
        // not contain the duplicate (it would ship on the wire to peers).
        final result = await repo.setGroupManualOrderSnapshot(
          'g1',
          ['e1', 'e1', 'e2', 'e3'],
        );

        // Not an exact permutation → recovered, not applied.
        expect(result, isA<SnapshotRecovered>());
        final recovered = result as SnapshotRecovered;
        // Duplicate id is reported via droppedIds (the field is a recovery
        // indicator; the toast copy is generic).
        expect(recovered.droppedIds, contains('e1'));
        expect(recovered.appendedIds, isEmpty);

        final stored = await _readSortState(db, 'g1');
        expect(
          stored.manualOrder,
          ['e1', 'e2', 'e3'],
          reason:
              'duplicate occurrence must be dropped (first wins); '
              'no duplicates on the wire',
        );

        // And nothing should leak duplicates into the emitted sync record.
        final update = _lastGroupUpdate(repo)!;
        final fields = update['fields']! as Map<String, dynamic>;
        final emittedState =
            tryDecodeSortState(fields['sort_state'] as String?)!;
        expect(emittedState.manualOrder, ['e1', 'e2', 'e3']);
      },
    );
  });

  // ── P1.4: atomicity of entry write + parent sort_state update ───────────
  group('addMemberToGroup atomicity', () {
    test(
      'an exception in the parent sort_state update rolls back the entry '
      'insert (no entry persisted, no sync records emitted)',
      () async {
        await setupRepo(members: [_member(id: 'm1')]);
        // Manual mode → addMemberToGroup will try to update sort_state.
        await _seedGroup(
          db,
          id: 'g1',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['existing'],
          ),
        );

        // Inject failure in the parent-update step.
        dao.failUpdateGroupSortStateWith = StateError('boom');

        try {
          await repo.addMemberToGroup('g1', 'm1', 'e1');
          fail('addMemberToGroup should have rethrown the injected error');
        } on StateError catch (e) {
          expect(e.message, 'boom');
        }

        // Entry row was rolled back — neither active nor tombstoned.
        final entryRow = await (db.select(db.memberGroupEntries)
              ..where((e) => e.groupId.equals('g1')))
            .get();
        expect(entryRow, isEmpty,
            reason:
                'transaction rollback must drop the entry insert when the '
                'parent update throws');

        // No sync records emitted — emissions happen AFTER commit.
        expect(repo.creates, isEmpty);
        expect(repo.updates, isEmpty);
        expect(repo.deletes, isEmpty);

        // Parent column is also unchanged.
        final stored = await _readSortState(db, 'g1');
        expect(stored.manualOrder, ['existing']);
      },
    );
  });

  // ── Corrupt-local-row regression (P1.2) ──────────────────────────────────
  group('emitGroupSyncState corrupt-local-row sanitization', () {
    int errorCountBaseline() =>
        ErrorReportingService.instance.errors.length;

    int warningsSinceBaseline(int baseline) {
      final entries = ErrorReportingService.instance.errors;
      var count = 0;
      for (var i = baseline; i < entries.length; i++) {
        if (entries[i].severity == ErrorSeverity.warning) count++;
      }
      return count;
    }

    test(
      'corrupt sort_state in the local column is substituted with '
      'manualEmpty on emit + warn',
      () async {
        await setupRepo();
        await _seedGroup(db, id: 'g1');
        // Bypass the mapper/DAO helpers and inject garbage directly into
        // the column. Simulates pre-validation legacy state, a manual DB
        // edit, or file-level corruption.
        await db.customStatement(
          'UPDATE member_groups SET sort_state = ? WHERE id = ?',
          ['utter garbage', 'g1'],
        );

        final baseline = errorCountBaseline();
        await repo.emitGroupSyncState('g1');

        final update = _lastGroupUpdate(repo)!;
        final fields = update['fields']! as Map<String, dynamic>;
        expect(
          fields['sort_state'],
          '{"mode":0,"order":[]}',
          reason: 'corrupt local row must not propagate to peers',
        );
        expect(warningsSinceBaseline(baseline), 1);
      },
    );
  });
}
