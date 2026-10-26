// Write-time validation for DriftMemberGroupsRepository.reorderGroups.
//
// The UI computes a reorder from groups it read earlier. Sync can delete or
// re-parent a group before the write runs, so the repository re-reads the
// stored rows inside the write transaction and only renumbers groups that are
// still active children of the same parent, comparing against STORED display
// orders.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;

Future<void> _insert(
  AppDatabase db,
  String id, {
  required int displayOrder,
  String? parentGroupId,
  bool isDeleted = false,
}) => db
    .into(db.memberGroups)
    .insert(
      MemberGroupsCompanion.insert(
        id: id,
        name: id,
        createdAt: DateTime.utc(2026, 1, 1),
        displayOrder: Value(displayOrder),
        parentGroupId: Value(parentGroupId),
        isDeleted: Value(isDeleted),
      ),
    );

/// The caller's (possibly stale) copy of a group.
domain.MemberGroup _group(
  String id, {
  int displayOrder = 0,
  String? parentGroupId,
}) => domain.MemberGroup(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 1, 1),
  displayOrder: displayOrder,
  parentGroupId: parentGroupId,
);

Future<Map<String, MemberGroupRow>> _rows(AppDatabase db) async => {
  for (final row in await db.select(db.memberGroups).get()) row.id: row,
};

/// Runs [body] and returns the ids of the member_groups sync updates it emits.
Future<List<String>> _emittedGroupUpdates(Future<void> Function() body) async {
  final ids = <String>[];
  await SyncRecordMixin.suppressAndCapture(body, (op) {
    if (op.table == 'member_groups') ids.add(op.entityId);
  });
  return ids;
}

void main() {
  late AppDatabase db;
  late DriftMemberGroupsRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftMemberGroupsRepository(db.memberGroupsDao, null);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'a normal reorder writes and emits only the groups that moved',
    () async {
      await _insert(db, 'a', displayOrder: 0);
      await _insert(db, 'b', displayOrder: 1);
      await _insert(db, 'c', displayOrder: 2);

      final emitted = await _emittedGroupUpdates(
        () => repo.reorderGroups([
          _group('a', displayOrder: 0),
          _group('c', displayOrder: 2),
          _group('b', displayOrder: 1),
        ]),
      );

      final rows = await _rows(db);
      expect(rows['a']!.displayOrder, 0);
      expect(rows['c']!.displayOrder, 1);
      expect(rows['b']!.displayOrder, 2);
      expect(emitted.toSet(), {'b', 'c'});
    },
  );

  test('a group re-parented since the caller read it is skipped', () async {
    await _insert(db, 'p', displayOrder: 0);
    await _insert(db, 'a', displayOrder: 1);
    await _insert(db, 'b', displayOrder: 2);
    // Sync moved 'c' under 'p' after the caller read it as a root group.
    await _insert(db, 'c', displayOrder: 7, parentGroupId: 'p');

    final emitted = await _emittedGroupUpdates(
      () => repo.reorderGroups([
        _group('c', displayOrder: 3),
        _group('b', displayOrder: 2),
        _group('a', displayOrder: 1),
        _group('p', displayOrder: 0),
      ]),
    );

    final rows = await _rows(db);
    expect(rows['c']!.parentGroupId, 'p');
    expect(rows['c']!.displayOrder, 7);
    expect([rows['b']!.displayOrder, rows['a']!.displayOrder], [0, 1]);
    expect(rows['p']!.displayOrder, 2);
    expect(emitted, isNot(contains('c')));
  });

  test('deleted and missing groups are skipped and never revived', () async {
    await _insert(db, 'a', displayOrder: 0);
    await _insert(db, 'b', displayOrder: 1);
    await _insert(db, 'gone', displayOrder: 5, isDeleted: true);

    final emitted = await _emittedGroupUpdates(
      () => repo.reorderGroups([
        _group('gone', displayOrder: 2),
        _group('never-existed', displayOrder: 3),
        _group('b', displayOrder: 1),
        _group('a', displayOrder: 0),
      ]),
    );

    final rows = await _rows(db);
    expect(rows['gone']!.isDeleted, isTrue);
    expect(rows['gone']!.displayOrder, 5);
    expect(rows.containsKey('never-existed'), isFalse);
    expect(rows['b']!.displayOrder, 0);
    expect(rows['a']!.displayOrder, 1);
    expect(emitted, isNot(contains('gone')));
    expect(emitted, isNot(contains('never-existed')));
  });

  test(
    'a stale caller display order is ignored: the stored order decides',
    () async {
      // A pending write already moved 'b' to 0 in the caller's copy, but the
      // database still has 'b' at 1.
      await _insert(db, 'a', displayOrder: 0);
      await _insert(db, 'b', displayOrder: 1);

      final emitted = await _emittedGroupUpdates(
        () => repo.reorderGroups([
          _group('b', displayOrder: 0),
          _group('a', displayOrder: 1),
        ]),
      );

      final rows = await _rows(db);
      expect(rows['b']!.displayOrder, 0);
      expect(rows['a']!.displayOrder, 1);
      expect(emitted.toSet(), {'a', 'b'});
    },
  );

  test('a reorder that matches the stored order writes nothing', () async {
    await _insert(db, 'a', displayOrder: 0);
    await _insert(db, 'b', displayOrder: 1);

    final emitted = await _emittedGroupUpdates(
      // The caller's copy is stale, but the stored order already matches.
      () => repo.reorderGroups([
        _group('a', displayOrder: 1),
        _group('b', displayOrder: 0),
      ]),
    );

    final rows = await _rows(db);
    expect(rows['a']!.displayOrder, 0);
    expect(rows['b']!.displayOrder, 1);
    expect(emitted, isEmpty);
  });

  test('siblings not in the list are left alone', () async {
    await _insert(db, 'a', displayOrder: 0);
    await _insert(db, 'b', displayOrder: 1);
    // Synced in after the caller read the list.
    await _insert(db, 'new', displayOrder: 9);

    await _emittedGroupUpdates(
      () => repo.reorderGroups([
        _group('b', displayOrder: 1),
        _group('a', displayOrder: 0),
      ]),
    );

    final rows = await _rows(db);
    expect(rows['new']!.displayOrder, 9);
    expect(rows['new']!.isDeleted, isFalse);
    expect(rows['b']!.displayOrder, 0);
    expect(rows['a']!.displayOrder, 1);
  });

  test('mixed parents or duplicate ids fail before any write', () async {
    await _insert(db, 'p', displayOrder: 0);
    await _insert(db, 'a', displayOrder: 1);
    await _insert(db, 'b', displayOrder: 2);
    await _insert(db, 'child', displayOrder: 0, parentGroupId: 'p');
    final before = await _rows(db);

    final emitted = <String>[];
    Future<void> attempt(List<domain.MemberGroup> groups) async {
      emitted.addAll(
        await _emittedGroupUpdates(() async {
          await expectLater(
            repo.reorderGroups(groups),
            throwsA(isA<ArgumentError>()),
          );
        }),
      );
    }

    await attempt([
      _group('b', displayOrder: 2),
      _group('child', parentGroupId: 'p'),
      _group('a', displayOrder: 1),
    ]);
    await attempt([
      _group('b', displayOrder: 2),
      _group('a', displayOrder: 1),
      _group('b', displayOrder: 2),
    ]);

    final after = await _rows(db);
    for (final id in before.keys) {
      expect(after[id]!.displayOrder, before[id]!.displayOrder, reason: id);
    }
    expect(emitted, isEmpty);
  });

  test('outside any capture seam the validated write commits', () async {
    await _insert(db, 'a', displayOrder: 0);
    await _insert(db, 'b', displayOrder: 1);
    await _insert(db, 'gone', displayOrder: 2, isDeleted: true);

    await repo.reorderGroups([
      _group('gone', displayOrder: 2),
      _group('b', displayOrder: 1),
      _group('a', displayOrder: 0),
    ]);

    final rows = await _rows(db);
    expect(rows['b']!.displayOrder, 0);
    expect(rows['a']!.displayOrder, 1);
    expect(rows['gone']!.displayOrder, 2);
    expect(rows['gone']!.isDeleted, isTrue);
  });

  test('an empty list is a no-op', () async {
    await _insert(db, 'a', displayOrder: 3);
    final emitted = await _emittedGroupUpdates(() => repo.reorderGroups([]));
    expect((await _rows(db))['a']!.displayOrder, 3);
    expect(emitted, isEmpty);
  });

  test(
    'inside an outer synced transaction that rolls back, nothing is kept',
    () async {
      await _insert(db, 'a', displayOrder: 0);
      await _insert(db, 'b', displayOrder: 1);

      await expectLater(
        SyncRecordMixin.runSyncedDatabaseTransaction<void>(db, () async {
          await repo.reorderGroups([
            _group('b', displayOrder: 1),
            _group('a', displayOrder: 0),
          ]);
          throw StateError('outer write failed');
        }),
        throwsStateError,
      );

      final rows = await _rows(db);
      expect(rows['a']!.displayOrder, 0);
      expect(rows['b']!.displayOrder, 1);
      final outbox = await db
          .customSelect('SELECT COUNT(*) AS c FROM sync_op_outbox')
          .getSingle();
      expect(outbox.read<int>('c'), 0);
    },
  );
}
