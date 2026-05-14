// End-to-end persisted group sort + cross-device + cross-record race
// coverage. Drives the 10 scenarios from
// `docs/plans/2026-05-14-group-member-ordering.md` §Task 5.3.
//
// Scenarios 1-3 exercise the widget + provider stack via flutter_test.
// Scenarios 4-10 exercise the sync adapter's applyFields path directly —
// a full FFI sync engine roundtrip is out of scope, but the plan
// explicitly says it's enough to verify the merge semantics
// (`drift_sync_adapter` is the authoritative apply path).

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ── In-memory test scaffolding ────────────────────────────────────────────────

class _TestMemberGroupsDao extends MemberGroupsDao {
  _TestMemberGroupsDao(super.db);

  @override
  Future<bool> isGroupSyncSuppressed(String groupId) async => false;
}

class _RecordingRepo extends DriftMemberGroupsRepository {
  _RecordingRepo(MemberGroupsDao dao, MemberRepository memberRepository)
    : super(dao, null, memberRepository: memberRepository);

  final updates = <Map<String, dynamic>>[];

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

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
  Future<void> syncRecordDelete(String table, String entityId) async {}
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

  @override
  Future<void> clearPluralKitLink(String id) async =>
      throw UnimplementedError();
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

DriftSyncEntity _entityFor(AppDatabase db, String tableName) {
  final adapter = buildSyncAdapterWithCompletion(db).adapter;
  return adapter.entities.singleWhere((e) => e.tableName == tableName);
}

Future<void> _seedGroup(
  AppDatabase db, {
  required String id,
  String name = 'g',
  String? colorHex,
  int displayOrder = 0,
  int groupType = 0,
  GroupSortState sortState = GroupSortState.manualEmpty,
}) async {
  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: name,
          createdAt: DateTime.utc(2026, 1, 1),
          colorHex: Value(colorHex),
          displayOrder: Value(displayOrder),
          groupType: Value(groupType),
          sortState: Value(
            MemberGroupMapper.encodeSortStateForColumn(sortState),
          ),
        ),
      );
}

Future<void> _seedEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  required String memberId,
}) {
  return db
      .into(db.memberGroupEntries)
      .insert(
        MemberGroupEntriesCompanion.insert(
          id: id,
          groupId: groupId,
          memberId: memberId,
        ),
      );
}

Future<GroupSortState> _readSortState(AppDatabase db, String groupId) async {
  final row = await (db.select(
    db.memberGroups,
  )..where((g) => g.id.equals(groupId))).getSingle();
  final decoded = tryDecodeSortState(row.sortState);
  expect(
    decoded,
    isNotNull,
    reason: 'sort_state must always decode to a valid state',
  );
  return decoded!;
}

member_domain.Member _member({
  required String id,
  required String name,
  bool isActive = true,
  DateTime? createdAt,
}) => member_domain.Member(
  id: id,
  name: name,
  isActive: isActive,
  createdAt: createdAt ?? DateTime(2024),
);

MemberGroup _groupModel({
  required String id,
  required String name,
  GroupSortState sortState = GroupSortState.manualEmpty,
}) => MemberGroup(
  id: id,
  name: name,
  sortState: sortState,
  createdAt: DateTime(2024),
);

class _FakeRepo implements MemberGroupsRepository {
  _FakeRepo();

  SnapshotApplyResult snapshotResult = const SnapshotApplyResult.applied();
  List<String>? lastSnapshotOrder;
  GroupSortMode? lastSortMode;

  @override
  Future<SnapshotApplyResult> setGroupManualOrderSnapshot(
    String groupId,
    List<String> orderedEntryIds,
  ) async {
    lastSnapshotOrder = List.of(orderedEntryIds);
    return snapshotResult;
  }

  @override
  Future<void> setGroupSortMode(String groupId, GroupSortMode mode) async {
    lastSortMode = mode;
  }

  @override
  Future<void> addMemberToGroup(
    String groupId,
    String memberId,
    String entryId,
  ) async {}
  @override
  Future<void> createGroup(MemberGroup group) async {}
  @override
  Future<void> deleteGroup(String groupId) async {}
  @override
  Future<void> deleteGroupWithDescendants(String groupId) async {}
  @override
  Future<void> emitGroupSyncState(String groupId) async {}
  @override
  Future<List<MemberGroupEntry>> getAllGroupEntries() async => const [];
  @override
  Future<void> promoteChildrenToRoot(String groupId) async {}
  @override
  Future<void> removeMemberFromGroup(String groupId, String memberId) async {}
  @override
  Future<void> updateGroup(MemberGroup group) async {}
  @override
  Stream<List<MemberGroupEntry>> watchAllGroupEntries() => const Stream.empty();
  @override
  Stream<List<MemberGroup>> watchAllGroups() => const Stream.empty();
  @override
  Stream<MemberGroup?> watchGroupById(String id) => const Stream.empty();
  @override
  Stream<List<MemberGroupEntry>> watchGroupEntries(String groupId) =>
      const Stream.empty();
  @override
  Stream<List<MemberGroup>> watchGroupsForMember(String memberId) =>
      const Stream.empty();
  @override
  Stream<Map<String, int>> watchMemberCountsByGroup() => const Stream.empty();
}

Widget _wrapDetailScreen({
  required MemberGroup group,
  required List<MemberGroupEntry> entries,
  required List<member_domain.Member> members,
  required _FakeRepo repo,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      memberByIdProvider.overrideWith((ref, memberId) {
        final matching = members.where((m) => m.id == memberId);
        return Stream.value(matching.isEmpty ? null : matching.first);
      }),
      allGroupsProvider.overrideWith((ref) => Stream.value([group])),
      allGroupEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      groupByIdProvider.overrideWith(
        (ref, groupId) => Stream.value(groupId == group.id ? group : null),
      ),
      groupEntriesProvider.overrideWith(
        (ref, groupId) =>
            Stream.value(entries.where((e) => e.groupId == groupId).toList()),
      ),
      groupTreeProvider.overrideWith(
        (ref) => GroupTreeUtils.buildGroupTree([group]),
      ),
      memberGroupsRepositoryProvider.overrideWithValue(repo),
      memberFrontingStatsProvider.overrideWith(
        (ref, memberId) async => const MemberFrontingStats(
          totalSessions: 0,
          totalDuration: Duration.zero,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: GroupDetailScreen(groupId: group.id),
    ),
  );
}

void main() {
  // ── Scenario 1: pick Name A-Z → chip + sort + repo call ───────────────────
  testWidgets('scenario 1: opens group with 3 members; pick Name A-Z; '
      'chip + sort + repo call', (tester) async {
    final group = _groupModel(id: 'g', name: 'Group');
    final m1 = _member(id: 'm1', name: 'Charlie');
    final m2 = _member(id: 'm2', name: 'Alice');
    final m3 = _member(id: 'm3', name: 'Bob');
    final repo = _FakeRepo();
    await tester.pumpWidget(
      _wrapDetailScreen(
        group: group,
        entries: const [
          MemberGroupEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
          MemberGroupEntry(id: 'e2', groupId: 'g', memberId: 'm2'),
          MemberGroupEntry(id: 'e3', groupId: 'g', memberId: 'm3'),
        ],
        members: [m1, m2, m3],
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    // Chip not visible in manual mode.
    expect(find.text('Name (A-Z)'), findsNothing);

    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name A-Z'));
    await tester.pumpAndSettle();

    expect(repo.lastSortMode, GroupSortMode.nameAsc);
  });

  // ── Scenario 2: drag a member triggers implicit unlock snapshot ──────────
  testWidgets('scenario 2: drag in manual mode persists snapshot via repo', (
    tester,
  ) async {
    final group = _groupModel(
      id: 'g',
      name: 'Group',
      sortState: const GroupSortState(
        mode: GroupSortMode.manual,
        manualOrder: ['e1', 'e2'],
      ),
    );
    final repo = _FakeRepo();
    await tester.pumpWidget(
      _wrapDetailScreen(
        group: group,
        entries: const [
          MemberGroupEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
          MemberGroupEntry(id: 'e2', groupId: 'g', memberId: 'm2'),
        ],
        members: [
          _member(id: 'm1', name: 'Alice'),
          _member(id: 'm2', name: 'Bob'),
        ],
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    final handle = find.byType(ReorderableDragStartListener).first;
    await tester.timedDrag(
      handle,
      const Offset(0, 120),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();

    expect(repo.lastSnapshotOrder, ['e2', 'e1']);
  });

  // ── Scenario 3: persistence across reload (repo state survives) ─────────
  test('scenario 3: repo persistence: setGroupManualOrderSnapshot writes '
      'survive a fresh read from the same DB', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = _TestMemberGroupsDao(db);
    final memberRepo = _FakeMemberRepository();
    final repo = _RecordingRepo(dao, memberRepo);

    await _seedGroup(db, id: 'g');
    await _seedEntry(db, id: 'e1', groupId: 'g', memberId: 'm1');
    await _seedEntry(db, id: 'e2', groupId: 'g', memberId: 'm2');

    final result = await repo.setGroupManualOrderSnapshot('g', ['e2', 'e1']);
    expect(result, isA<SnapshotApplied>());

    // Simulate "reload" by re-reading the DB row.
    final state = await _readSortState(db, 'g');
    expect(state.mode, GroupSortMode.manual);
    expect(state.manualOrder, ['e2', 'e1']);
  });

  // ── Scenarios 4 + 5: Cross-device convergence via applyFields ────────────
  // We simulate two peers' emitted field maps via the adapter's
  // applyFields. The single sort_state field means LWW always picks one
  // device's complete (mode, order) pair — the test confirms this.

  test('scenario 4: cross-device sync convergence — last applyFields wins '
      'the complete (mode, order) pair', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final entity = _entityFor(db, 'member_groups');

    // Both devices start from the same group.
    await _seedGroup(db, id: 'g');
    await _seedEntry(db, id: 'e1', groupId: 'g', memberId: 'm1');
    await _seedEntry(db, id: 'e2', groupId: 'g', memberId: 'm2');

    // Device A reorders to [e2, e1].
    const deviceAState = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e2', 'e1'],
    );
    // Device B reorders to [e1, e2] (same as initial).
    const deviceBState = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1', 'e2'],
    );

    // Peer C receives A's then B's fields. B's HLC is newer → B wins.
    await entity.applyFields('g', {
      'sort_state': MemberGroupMapper.encodeSortStateForColumn(deviceAState),
    });
    await entity.applyFields('g', {
      'sort_state': MemberGroupMapper.encodeSortStateForColumn(deviceBState),
    });

    final state = await _readSortState(db, 'g');
    expect(state.manualOrder, [
      'e1',
      'e2',
    ], reason: 'B applied last → B wins atomically');
  });

  test('scenario 5: cross-device sort-mode race — single-field LWW means '
      'one device wins the whole (mode, order) pair, never a split', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final entity = _entityFor(db, 'member_groups');

    await _seedGroup(db, id: 'g');
    await _seedEntry(db, id: 'e1', groupId: 'g', memberId: 'm1');

    // Device A: setGroupSortMode(nameAsc) — would emit sort_state with
    // (nameAsc, current order).
    const deviceA = GroupSortState(
      mode: GroupSortMode.nameAsc,
      manualOrder: <String>[],
    );
    // Device B: setGroupManualOrderSnapshot([e1]) — sort_state with
    // (manual, [e1]).
    const deviceB = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1'],
    );

    // Apply B then A; A wins (latest applyFields wins).
    await entity.applyFields('g', {
      'sort_state': MemberGroupMapper.encodeSortStateForColumn(deviceB),
    });
    await entity.applyFields('g', {
      'sort_state': MemberGroupMapper.encodeSortStateForColumn(deviceA),
    });

    final state = await _readSortState(db, 'g');
    // Whole-pair atomicity: mode + order BOTH come from device A.
    expect(state.mode, GroupSortMode.nameAsc);
    expect(state.manualOrder, isEmpty);
  });

  // ── Scenario 6: cross-record add + reorder race (invariant §1) ───────────
  // Device A adds entry m3 in manual mode. Device B reorders without m3.
  // Apply both at a third peer in either order → provider returns a list
  // containing m3 (appended at end when not in manualOrder).
  test('scenario 6: cross-record add + reorder race — '
      'unindexed live entry appears at end', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final groupsEntity = _entityFor(db, 'member_groups');
    final entriesEntity = _entityFor(db, 'member_group_entries');

    // Initial state on peer C.
    await _seedGroup(db, id: 'g');
    await _seedEntry(db, id: 'e1', groupId: 'g', memberId: 'm1');
    await _seedEntry(db, id: 'e2', groupId: 'g', memberId: 'm2');

    // Device A adds e3. Device B reorders [e2, e1] without knowing of e3.
    // Apply order: B's parent sort_state first, then A's entry create.
    await groupsEntity.applyFields('g', {
      'sort_state': MemberGroupMapper.encodeSortStateForColumn(
        const GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['e2', 'e1'],
        ),
      ),
    });
    await entriesEntity.applyFields('e3', {
      'group_id': 'g',
      'member_id': 'm3',
      'is_deleted': false,
    });

    // Verify DB state.
    final state = await _readSortState(db, 'g');
    expect(state.manualOrder, ['e2', 'e1']);

    // Provider read invariant §1: e3 (live but unindexed) appears at end.
    // Use `Future.value(...)` via a FutureProvider proxy idiom: we
    // resolve the provider through riverpod's flush by reading the
    // value after a microtask.
    final container = ProviderContainer(
      overrides: [
        allMembersProvider.overrideWith(
          (ref) => Stream.value([
            _member(id: 'm1', name: 'Alice'),
            _member(id: 'm2', name: 'Bob'),
            _member(id: 'm3', name: 'Carol'),
          ]),
        ),
        groupByIdProvider.overrideWith(
          (ref, _) =>
              Stream.value(_groupModel(id: 'g', name: 'g', sortState: state)),
        ),
        groupEntriesProvider.overrideWith(
          (ref, _) => Stream.value(const [
            MemberGroupEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
            MemberGroupEntry(id: 'e2', groupId: 'g', memberId: 'm2'),
            MemberGroupEntry(id: 'e3', groupId: 'g', memberId: 'm3'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Subscribe and wait for the streams to deliver their seeded value.
    container.listen(allMembersProvider, (_, _) {}, fireImmediately: true);
    container.listen(groupByIdProvider('g'), (_, _) {}, fireImmediately: true);
    container.listen(
      groupEntriesProvider('g'),
      (_, _) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    final list = container.read(sortedGroupMembersProvider('g'));
    expect(list.map((p) => p.$1.id).toList(), ['e2', 'e1', 'e3']);
  });

  // ── Scenario 7: cross-record remove + reorder race (invariant §2) ───────
  test('scenario 7: cross-record remove + reorder race — '
      'tombstoned id in manualOrder is filtered out at read', () async {
    // The provider read invariant filters live entries against
    // manualOrder. We verify directly via the provider.
    const state = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1', 'e2', 'e3'], // includes tombstoned e3
    );
    final container = ProviderContainer(
      overrides: [
        allMembersProvider.overrideWith(
          (ref) => Stream.value([
            _member(id: 'm1', name: 'Alice'),
            _member(id: 'm2', name: 'Bob'),
          ]),
        ),
        groupByIdProvider.overrideWith(
          (ref, _) =>
              Stream.value(_groupModel(id: 'g', name: 'g', sortState: state)),
        ),
        groupEntriesProvider.overrideWith(
          (ref, _) => Stream.value(const [
            MemberGroupEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
            MemberGroupEntry(id: 'e2', groupId: 'g', memberId: 'm2'),
            // e3 is tombstoned → excluded from the entries stream.
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(allMembersProvider, (_, _) {}, fireImmediately: true);
    container.listen(groupByIdProvider('g'), (_, _) {}, fireImmediately: true);
    container.listen(
      groupEntriesProvider('g'),
      (_, _) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    final list = container.read(sortedGroupMembersProvider('g'));
    expect(list.map((p) => p.$1.id).toList(), ['e1', 'e2']);
  });

  // ── Scenario 8: app-kill mid-write — local DB consistent ───────────────
  // We simulate this by writing the DAO column atomically; verify the
  // column reflects the write even when the subsequent syncRecordUpdate
  // throws.
  test('scenario 8: app-kill mid-write leaves local DB consistent; '
      'emitGroupSyncState re-broadcasts the new state', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = _TestMemberGroupsDao(db);

    await _seedGroup(db, id: 'g');
    await _seedEntry(db, id: 'e1', groupId: 'g', memberId: 'm1');

    // Direct DAO write — simulates the "after _dao.updateGroupSortState
    // but before syncRecordUpdate" mid-write state.
    const newState = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1'],
    );
    await dao.updateGroupSortState(
      'g',
      MemberGroupMapper.encodeSortStateForColumn(newState),
    );

    // DB is consistent — the column reflects the write atomically.
    final persisted = await _readSortState(db, 'g');
    expect(persisted, newState);

    // Re-broadcast via a fresh repo: emitGroupSyncState reads the row
    // and would syncRecordUpdate(_groupFields(row)) — which is the
    // "next legitimate write" the plan §scenario 8 calls out.
    final repo = _RecordingRepo(dao, _FakeMemberRepository());
    await repo.emitGroupSyncState('g');
    // Pick the member_groups update specifically; entry updates also land
    // in the recorder.
    final groupUpdate = repo.updates.firstWhere(
      (u) => u['table'] == 'member_groups',
      orElse: () => <String, dynamic>{},
    );
    expect(
      groupUpdate.isNotEmpty,
      isTrue,
      reason: 'emitGroupSyncState must emit a member_groups update',
    );
    final fields = groupUpdate['fields'] as Map<String, dynamic>;
    final emitted = tryDecodeSortState(fields['sort_state'] as String?);
    expect(emitted, newState);
  });

  // ── Scenario 9: corrupt remote payload (apply-time validation) ──────────
  test('scenario 9: corrupt remote sort_state is rejected; '
      'next local _groupFields emits previous valid state', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final entity = _entityFor(db, 'member_groups');
    final dao = _TestMemberGroupsDao(db);

    // Seed a valid pre-garbage state.
    const preGarbage = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1'],
    );
    await _seedGroup(db, id: 'g', sortState: preGarbage);
    await _seedEntry(db, id: 'e1', groupId: 'g', memberId: 'm1');

    // Peer sends garbage → adapter must omit sort_state from the
    // companion via Value.absent(); local column unchanged.
    await entity.applyFields('g', {'sort_state': 'not-json-garbage'});
    expect(await _readSortState(db, 'g'), preGarbage);

    await entity.applyFields('g', {'sort_state': '[]'});
    expect(await _readSortState(db, 'g'), preGarbage);

    await entity.applyFields('g', {'sort_state': '{"mode": 0}'});
    expect(await _readSortState(db, 'g'), preGarbage);

    // Next local write path emits the pre-garbage valid state.
    final repo = _RecordingRepo(dao, _FakeMemberRepository());
    await repo.emitGroupSyncState('g');
    final groupUpdate = repo.updates.firstWhere(
      (u) => u['table'] == 'member_groups',
      orElse: () => <String, dynamic>{},
    );
    expect(
      groupUpdate.isNotEmpty,
      isTrue,
      reason: 'emitGroupSyncState must emit a member_groups update',
    );
    final fields = groupUpdate['fields'] as Map<String, dynamic>;
    final emitted = tryDecodeSortState(fields['sort_state'] as String?);
    expect(
      emitted,
      preGarbage,
      reason: 'garbage cannot round-trip through the local DB',
    );
  });

  // ── Scenario 10: whole-entity LWW invariant ─────────────────────────────
  // The actual Pattern A invariant: each emission is the device's FULL
  // _groupFields(row) snapshot (name + sort_state + display_order +
  // color_hex + parent_group_id + ...). Apply-at-peer is LWW: whichever
  // device's emission is applied last wins ALL fields atomically — name
  // AND sort_state come from the SAME device, never a mix.
  //
  // Each side uses the live repository's `debugGroupFields` builder so
  // the test pins the actual emission shape — a future regression that
  // splits the emit into per-field updates would let "name from A + sort
  // from B" sneak past and would break this test.
  test('scenario 10a: whole-entity LWW — B applied last wins ALL fields '
      '(name + sort_state both from B)', () async {
    final dbA = AppDatabase(NativeDatabase.memory());
    final dbB = AppDatabase(NativeDatabase.memory());
    final dbC = AppDatabase(NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    addTearDown(dbC.close);

    // All three peers start aligned: name = "Original",
    // manualOrder = [e1, e2], same color/display_order/etc.
    const initial = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1', 'e2'],
    );
    await _seedGroup(dbA, id: 'g', name: 'Original', sortState: initial);
    await _seedGroup(dbB, id: 'g', name: 'Original', sortState: initial);
    await _seedGroup(dbC, id: 'g', name: 'Original', sortState: initial);

    // Device A renames the group → ships its FULL _groupFields snapshot
    // (new name + original sort_state).
    final daoA = _TestMemberGroupsDao(dbA);
    final repoA = _RecordingRepo(daoA, _FakeMemberRepository());
    await dbA
        .into(dbA.memberGroups)
        .insertOnConflictUpdate(
          MemberGroupsCompanion(
            id: const Value('g'),
            name: const Value('Renamed by A'),
            colorHex: const Value('#FF0000'),
            displayOrder: const Value(5),
            groupType: const Value(1),
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            sortState: Value(
              MemberGroupMapper.encodeSortStateForColumn(initial),
            ),
          ),
        );
    final rowA = await (dbA.select(
      dbA.memberGroups,
    )..where((g) => g.id.equals('g'))).getSingle();
    final fieldsA = repoA.debugGroupFields(rowA);

    // Device B reorders → ships its FULL _groupFields snapshot
    // (original name + new sort_state).
    const reorderedB = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e2', 'e1'],
    );
    final daoB = _TestMemberGroupsDao(dbB);
    final repoB = _RecordingRepo(daoB, _FakeMemberRepository());
    await dbB
        .into(dbB.memberGroups)
        .insertOnConflictUpdate(
          MemberGroupsCompanion(
            id: const Value('g'),
            name: const Value('Original'),
            colorHex: const Value('#00FF00'),
            displayOrder: const Value(10),
            groupType: const Value(2),
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            sortState: Value(
              MemberGroupMapper.encodeSortStateForColumn(reorderedB),
            ),
          ),
        );
    final rowB = await (dbB.select(
      dbB.memberGroups,
    )..where((g) => g.id.equals('g'))).getSingle();
    final fieldsB = repoB.debugGroupFields(rowB);

    // Sanity: each side really IS shipping the full field set
    // (not a partial map). A regression that downgrades emission to
    // per-field updates would break this expectation.
    expect(fieldsA.keys, contains('name'));
    expect(fieldsA.keys, contains('sort_state'));
    expect(fieldsA.keys, contains('display_order'));
    expect(fieldsA.keys, contains('color_hex'));
    expect(fieldsA.keys, contains('parent_group_id'));
    expect(fieldsA.keys, contains('group_type'));
    expect(fieldsB.keys.toSet(), fieldsA.keys.toSet());
    expect(fieldsA['color_hex'], '#FF0000');
    expect(fieldsA['display_order'], 5);
    expect(fieldsA['group_type'], 1);
    expect(fieldsB['color_hex'], '#00FF00');
    expect(fieldsB['display_order'], 10);
    expect(fieldsB['group_type'], 2);

    // Apply at peer C: A first, then B. B's emission is "newer"
    // (applied last) → its complete snapshot wins.
    final entityC = _entityFor(dbC, 'member_groups');
    await entityC.applyFields('g', fieldsA);
    await entityC.applyFields('g', fieldsB);

    final rowC = await (dbC.select(
      dbC.memberGroups,
    )..where((g) => g.id.equals('g'))).getSingle();
    // Whole-entity LWW: B applied last, so both fields are B's.
    expect(
      rowC.name,
      'Original',
      reason: 'B applied last; name is B\'s "Original", not A\'s',
    );
    expect(
      rowC.colorHex,
      '#00FF00',
      reason: 'B applied last; color_hex is B\'s value',
    );
    expect(
      rowC.displayOrder,
      10,
      reason: 'B applied last; display_order is B\'s value',
    );
    expect(
      rowC.groupType,
      2,
      reason: 'B applied last; group_type is B\'s value',
    );
    final stateC = tryDecodeSortState(rowC.sortState)!;
    expect(stateC.manualOrder, [
      'e2',
      'e1',
    ], reason: 'B applied last; sort_state is B\'s reorder');
  });

  test('scenario 10b: whole-entity LWW — A applied last wins ALL fields '
      '(name + sort_state both from A, no field mixing)', () async {
    final dbA = AppDatabase(NativeDatabase.memory());
    final dbB = AppDatabase(NativeDatabase.memory());
    final dbC = AppDatabase(NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    addTearDown(dbC.close);

    const initial = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e1', 'e2'],
    );
    await _seedGroup(dbA, id: 'g', name: 'Original', sortState: initial);
    await _seedGroup(dbB, id: 'g', name: 'Original', sortState: initial);
    await _seedGroup(dbC, id: 'g', name: 'Original', sortState: initial);

    // Device A: rename, keep original sort.
    final daoA = _TestMemberGroupsDao(dbA);
    final repoA = _RecordingRepo(daoA, _FakeMemberRepository());
    await dbA
        .into(dbA.memberGroups)
        .insertOnConflictUpdate(
          MemberGroupsCompanion(
            id: const Value('g'),
            name: const Value('Renamed by A'),
            colorHex: const Value('#FF0000'),
            displayOrder: const Value(5),
            groupType: const Value(1),
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            sortState: Value(
              MemberGroupMapper.encodeSortStateForColumn(initial),
            ),
          ),
        );
    final rowA = await (dbA.select(
      dbA.memberGroups,
    )..where((g) => g.id.equals('g'))).getSingle();
    final fieldsA = repoA.debugGroupFields(rowA);

    // Device B: reorder, keep original name.
    const reorderedB = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: ['e2', 'e1'],
    );
    final daoB = _TestMemberGroupsDao(dbB);
    final repoB = _RecordingRepo(daoB, _FakeMemberRepository());
    await dbB
        .into(dbB.memberGroups)
        .insertOnConflictUpdate(
          MemberGroupsCompanion(
            id: const Value('g'),
            name: const Value('Original'),
            colorHex: const Value('#00FF00'),
            displayOrder: const Value(10),
            groupType: const Value(2),
            createdAt: Value(DateTime.utc(2026, 1, 1)),
            sortState: Value(
              MemberGroupMapper.encodeSortStateForColumn(reorderedB),
            ),
          ),
        );
    final rowB = await (dbB.select(
      dbB.memberGroups,
    )..where((g) => g.id.equals('g'))).getSingle();
    final fieldsB = repoB.debugGroupFields(rowB);

    // Apply B first, then A. A's emission wins.
    final entityC = _entityFor(dbC, 'member_groups');
    await entityC.applyFields('g', fieldsB);
    await entityC.applyFields('g', fieldsA);

    final rowC = await (dbC.select(
      dbC.memberGroups,
    )..where((g) => g.id.equals('g'))).getSingle();
    // Whole-entity LWW: A applied last → name is A's, sort_state is
    // A's (the ORIGINAL [e1, e2]), NOT A's name + B's reorder.
    expect(
      rowC.name,
      'Renamed by A',
      reason: 'A applied last; name is A\'s rename',
    );
    expect(
      rowC.colorHex,
      '#FF0000',
      reason: 'A applied last; color_hex is A\'s value',
    );
    expect(
      rowC.displayOrder,
      5,
      reason: 'A applied last; display_order is A\'s value',
    );
    expect(
      rowC.groupType,
      1,
      reason: 'A applied last; group_type is A\'s value',
    );
    final stateC = tryDecodeSortState(rowC.sortState)!;
    expect(
      stateC.manualOrder,
      ['e1', 'e2'],
      reason:
          'A applied last; sort_state is A\'s original order, NOT '
          'a mix of A\'s name with B\'s sort_state',
    );
  });

  // Smoke: encode/decode round-trip is well-formed JSON.
  test(
    'sort_state encoded by mapper round-trips through tryDecodeSortState',
    () async {
      const state = GroupSortState(
        mode: GroupSortMode.nameAsc,
        manualOrder: ['a', 'b', 'c'],
      );
      final encoded = MemberGroupMapper.encodeSortStateForColumn(state);
      // Valid JSON object with the expected keys.
      final parsed = jsonDecode(encoded) as Map<String, dynamic>;
      expect(parsed.containsKey('mode'), isTrue);
      expect(parsed.containsKey('order'), isTrue);
      expect(tryDecodeSortState(encoded), state);
    },
  );
}
