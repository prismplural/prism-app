import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart'
    as group_domain;
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
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();
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

    test('empty supplied list: recovers all live entries sorted by id',
        () async {
      await setupRepo();
      await _seedGroup(db, id: 'g1');
      await _seedEntry(db, id: 'e2', groupId: 'g1', memberId: 'm2');
      await _seedEntry(db, id: 'e1', groupId: 'g1', memberId: 'm1');
      await _seedEntry(db, id: 'e3', groupId: 'g1', memberId: 'm3');

      final result = await repo.setGroupManualOrderSnapshot('g1', const []);

      expect(result, isA<SnapshotRecovered>());
      final recovered = result as SnapshotRecovered;
      expect(recovered.droppedIds, isEmpty);
      expect(recovered.appendedIds, ['e1', 'e2', 'e3']);

      final stored = await _readSortState(db, 'g1');
      expect(stored.mode, GroupSortMode.manual);
      expect(stored.manualOrder, ['e1', 'e2', 'e3']);

      expect(_groupUpdates(repo), 1);
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

    // Regression: setGroupSortMode preserves manualOrder when flipping to
    // a sorted mode. A subsequent remove in that sorted mode must NOT
    // prune the preserved order, and must NOT emit a parent sync update —
    // sorted modes leave sortState untouched on add/remove.
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
    // Concurrent-reorder convergence regression test.
    // The single-field design makes this convergence true by construction
    // (one pending_op per write, deterministic LWW), but proving it
    // end-to-end requires two repositories backed by separate DBs running
    // through a real sync engine with HLC tiebreaking.
    test(
      'two repositories with opposing manual snapshots converge to one HLC winner',
      () {
        // Stub: needs a multi-peer harness (see skip message).
      },
      skip: 'Deferred: cross-device LWW with real HLC tiebreaking requires '
          'a multi-peer test harness not currently set up. The integration '
          'tests exercise applyFields in sequence on one DB but do not '
          'simulate real cross-device merge.',
    );

    // Cross-device sort-mode-only race regression test.
    // Needs the same multi-peer harness to show that a setGroupSortMode
    // call and a setGroupManualOrderSnapshot call converge atomically
    // (both write to the single sort_state field).
    test(
      'sort-mode-only race: loser writes are not visible (single-field LWW)',
      () {
        // Stub: needs a multi-peer harness (see skip message).
      },
      skip: 'Deferred: cross-device LWW with real HLC tiebreaking requires '
          'a multi-peer test harness not currently set up. The integration '
          'tests exercise applyFields in sequence on one DB but do not '
          'simulate real cross-device merge.',
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

  // ── Duplicate detection in setGroupManualOrderSnapshot ─────────────────
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

  // ── Atomicity of entry write + parent sort_state update ────────────────
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

  // ── Corrupt-local-row regression ────────────────────────────────────────
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

  // ── updateGroup patch-style emission (item #14 of the drift-repo
  //    diffSyncFields migration plan). The existing _RecordingRepo above
  //    overrides syncRecord* directly, so the install-sink harness is wired
  //    here with a fresh vanilla repo so we get exactly the same emission
  //    path the production app uses (null syncHandle → mixin's install sink
  //    intercepts pre-FFI). ────────────────────────────────────────────────
  group('updateGroup patch-style emission', () {
    late AppDatabase patchDb;
    late MemberGroupsDao patchDao;
    late DriftMemberGroupsRepository patchRepo;
    late List<CapturedSyncOp> captured;

    final baseTime = DateTime.utc(2026, 5, 1, 12);

    Future<void> seedDirect({
      required String id,
      String name = 'Original name',
      String? description,
      String? colorHex,
      String? emoji,
      int displayOrder = 0,
      String? parentGroupId,
      int groupType = 0,
      String? filterRules,
      String? pluralkitUuid,
      String? pluralkitId,
      DateTime? lastSeenFromPkAt,
      GroupSortState? sortState,
      bool isDeleted = false,
    }) {
      final state = sortState ?? GroupSortState.manualEmpty;
      return patchDb.into(patchDb.memberGroups).insert(
            MemberGroupsCompanion.insert(
              id: id,
              name: name,
              description: Value(description),
              colorHex: Value(colorHex),
              emoji: Value(emoji),
              displayOrder: Value(displayOrder),
              parentGroupId: Value(parentGroupId),
              groupType: Value(groupType),
              filterRules: Value(filterRules),
              createdAt: baseTime,
              pluralkitId: Value(pluralkitId),
              pluralkitUuid: Value(pluralkitUuid),
              lastSeenFromPkAt: Value(lastSeenFromPkAt),
              isDeleted: Value(isDeleted),
              sortState: Value(
                MemberGroupMapper.encodeSortStateForColumn(state),
              ),
            ),
          );
    }

    group_domain.MemberGroup buildDomain({
      String id = 'g-patch',
      String name = 'Original name',
      String? description,
      String? colorHex,
      String? emoji,
      int displayOrder = 0,
      String? parentGroupId,
      int groupType = 0,
      String? filterRules,
      DateTime? createdAt,
      GroupSortState sortState = GroupSortState.manualEmpty,
    }) {
      return group_domain.MemberGroup(
        id: id,
        name: name,
        description: description,
        colorHex: colorHex,
        emoji: emoji,
        displayOrder: displayOrder,
        parentGroupId: parentGroupId,
        groupType: groupType,
        filterRules: filterRules,
        createdAt: createdAt ?? baseTime,
        sortState: sortState,
      );
    }

    setUp(() async {
      patchDb = AppDatabase(NativeDatabase.memory());
      patchDao = MemberGroupsDao(patchDb);
      patchRepo = DriftMemberGroupsRepository(
        patchDao,
        null,
        memberRepository: _FakeMemberRepository(),
      );
      captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);
    });

    tearDown(() async {
      await patchDb.close();
    });

    test('emits only the changed fields', () async {
      await seedDirect(id: 'g-patch');

      await patchRepo.updateGroup(
        buildDomain(name: 'Renamed locally'),
      );

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'member_groups');
      expect(captured.single.entityId, 'g-patch');
      expect(captured.single.fields, {'name': 'Renamed locally'});
    });

    test('emits nothing when the domain matches the stored row', () async {
      await seedDirect(id: 'g-patch');

      await patchRepo.updateGroup(buildDomain());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await seedDirect(
        id: 'g-patch',
        description: 'Untouched description',
        colorHex: '#abcdef',
        displayOrder: 3,
        groupType: 1,
      );

      await patchRepo.updateGroup(
        buildDomain(
          name: 'Renamed locally',
          description: 'Untouched description',
          colorHex: '#abcdef',
          displayOrder: 3,
          groupType: 1,
        ),
      );

      final row = await patchDao.getGroupById('g-patch');
      expect(row, isNotNull);
      expect(row!.name, 'Renamed locally');
      expect(row.description, 'Untouched description');
      expect(row.colorHex, '#abcdef');
      expect(row.displayOrder, 3);
      expect(row.groupType, 1);
    });

    test('null-clearing on a nullable column emits the null patch', () async {
      await seedDirect(
        id: 'g-patch',
        description: 'Has a description',
        colorHex: '#abcdef',
      );

      await patchRepo.updateGroup(
        buildDomain(
          description: null,
          colorHex: '#abcdef',
        ),
      );

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('description'), isTrue);
      expect(captured.single.fields['description'], isNull);

      final row = await patchDao.getGroupById('g-patch');
      expect(row!.description, isNull);
      expect(row.colorHex, '#abcdef');
    });

    test(
      'silently no-ops on a tombstoned row (no emit, no resurrection)',
      () async {
        await seedDirect(id: 'g-patch', isDeleted: true);

        await patchRepo.updateGroup(
          buildDomain(name: 'Attempted resurrection'),
        );

        expect(captured, isEmpty);
        // Stored row stays tombstoned; the active getter therefore returns
        // null (it filters out deleted rows).
        final activeRow = await patchDao.getGroupById('g-patch');
        expect(activeRow, isNull);
      },
    );

    test('silently no-ops when the row does not exist', () async {
      await patchRepo.updateGroup(
        buildDomain(id: 'missing-group', name: 'Whatever'),
      );

      expect(captured, isEmpty);
    });

    test('does not emit is_deleted in the patch', () async {
      await seedDirect(id: 'g-patch');

      await patchRepo.updateGroup(buildDomain(name: 'Renamed'));

      expect(captured, hasLength(1));
      expect(
        captured.single.fields.containsKey('is_deleted'),
        isFalse,
        reason:
            'diffSyncFields strips is_deleted; tombstones/resurrection are '
            'owned by syncRecordDelete/syncRecordCreate, not update.',
      );
    });

    test(
      'preserves PK-link gating: PK-backed group with v2 disabled does not '
      'emit even when fields changed',
      () async {
        // PK v2 enablement defaults to false on a fresh AppDatabase.
        await patchDb.systemSettingsDao.getSettings();
        await patchDb.systemSettingsDao.updatePkGroupSyncV2Enabled(false);

        await seedDirect(
          id: 'g-patch',
          pluralkitUuid: 'pk-uuid-1',
          pluralkitId: 'pk-id-1',
        );

        await patchRepo.updateGroup(
          buildDomain(name: 'Renamed locally'),
        );

        // The DB write happens (so local state is correct), but no sync
        // emission because the PK-link gate said "hold back".
        final row = await patchDao.getGroupById('g-patch');
        expect(row!.name, 'Renamed locally');
        expect(captured, isEmpty);
      },
    );

    test(
      'sort_state.manualOrder: identical order produces no emission; '
      'reordered order produces a patch (manualOrder is ORDERED, not a set)',
      () async {
        const original = GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['a', 'b', 'c'],
        );
        await seedDirect(id: 'g-patch', sortState: original);

        // Same order → no diff.
        await patchRepo.updateGroup(buildDomain(sortState: original));
        expect(
          captured,
          isEmpty,
          reason:
              'identical manualOrder must produce no false-positive emission',
        );

        // Reordered → real edit, should emit a sort_state patch.
        const reordered = GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['c', 'a', 'b'],
        );
        await patchRepo.updateGroup(buildDomain(sortState: reordered));

        expect(captured, hasLength(1));
        expect(captured.single.fields.keys.toSet(), {'sort_state'});
        final emitted = tryDecodeSortState(
          captured.single.fields['sort_state'] as String?,
        )!;
        expect(
          emitted.manualOrder,
          ['c', 'a', 'b'],
          reason: 'manualOrder is the user-chosen order; reordering is a real '
              'edit and must ship as a sort_state patch',
        );
      },
    );
  });
}
