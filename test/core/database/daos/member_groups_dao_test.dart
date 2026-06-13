import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';

import '../../../helpers/pk_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // ── nextDisplayOrder ────────────────────────────────────────────────────────

  group('nextDisplayOrder', () {
    test('returns 0 when no root groups exist', () async {
      expect(await db.memberGroupsDao.nextDisplayOrder(null), 0);
    });

    test('returns max + 1 for root siblings', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'a', displayOrder: 0));
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'b', displayOrder: 3));
      expect(await db.memberGroupsDao.nextDisplayOrder(null), 4);
    });

    test('returns 0 when no children exist under a parent', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      expect(await db.memberGroupsDao.nextDisplayOrder('root'), 0);
    });

    test('returns max + 1 for children of a given parent', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child-a', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child-b', displayOrder: 5, parentGroupId: 'root'));
      expect(await db.memberGroupsDao.nextDisplayOrder('root'), 6);
    });

    test('child siblings are scoped separately from root siblings', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 99));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 1, parentGroupId: 'root'));
      // Root max is 99 but child query should only see child siblings (max=1).
      expect(await db.memberGroupsDao.nextDisplayOrder('root'), 2);
      // Root query should only see root siblings (max=99).
      expect(await db.memberGroupsDao.nextDisplayOrder(null), 100);
    });

    test('soft-deleted groups are excluded from the count', () async {
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'dead', displayOrder: 100, isDeleted: true));
      // The only row is soft-deleted, so next order starts at 0.
      expect(await db.memberGroupsDao.nextDisplayOrder(null), 0);
    });
  });

  // ── watchChildGroups ────────────────────────────────────────────────────────

  group('watchChildGroups', () {
    test('returns empty list on completely empty database', () async {
      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots, isEmpty);
    });

    test('returns empty list for non-existent parent id', () async {
      final children =
          await db.memberGroupsDao.watchChildGroups('ghost').first;
      expect(children, isEmpty);
    });

    test('root watch returns only null-parent groups', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));

      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots.map((r) => r.id), ['root']);
    });

    test('child watch returns only direct children', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      final children =
          await db.memberGroupsDao.watchChildGroups('root').first;
      expect(children.map((r) => r.id), ['child']);
    });

    test('soft-deleted groups are excluded', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'dead', displayOrder: 1, isDeleted: true));

      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots.map((r) => r.id), ['root']);
    });

    test('results are ordered by displayOrder ascending', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'c', displayOrder: 2));
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'a', displayOrder: 0));
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'b', displayOrder: 1));

      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots.map((r) => r.id), ['a', 'b', 'c']);
    });
  });

  // ── active member entry queries ────────────────────────────────────────────

  group('active member entry queries', () {
    test('hide entries whose member row is soft-deleted', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db
          .into(db.members)
          .insert(pkFixtureMember(id: 'live', name: 'Live'));
      await db
          .into(db.members)
          .insert(pkFixtureMember(id: 'deleted', name: 'Deleted'));
      await (db.update(db.members)..where((m) => m.id.equals('deleted')))
          .write(const MembersCompanion(isDeleted: Value(true)));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'entry-live', groupId: 'g', memberId: 'live'),
          );
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'entry-deleted',
              groupId: 'g',
              memberId: 'deleted',
            ),
          );

      final allEntries = await db.memberGroupsDao.getAllGroupEntries();
      expect(allEntries.map((entry) => entry.id), ['entry-live']);

      final groupEntries =
          await db.memberGroupsDao.watchGroupEntries('g').first;
      expect(groupEntries.map((entry) => entry.id), ['entry-live']);

      final counts = await db.memberGroupsDao.watchMemberCountsByGroup().first;
      expect(counts, {'g': 1});

      final repairEntries =
          await db.memberGroupsDao.activeEntriesForMember('deleted');
      expect(repairEntries.map((entry) => entry.id), ['entry-deleted']);
    });
  });

  // ── getDirectChildrenOf ─────────────────────────────────────────────────────

  group('getDirectChildrenOf', () {
    test('returns empty list when group has no children', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      final children = await db.memberGroupsDao.getDirectChildrenOf('root');
      expect(children, isEmpty);
    });

    test('returns only direct children, not grandchildren', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      final children = await db.memberGroupsDao.getDirectChildrenOf('root');
      expect(children.map((r) => r.id), ['child']);
    });

    test('excludes soft-deleted children', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'alive', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'dead', displayOrder: 1, parentGroupId: 'root', isDeleted: true));

      final children = await db.memberGroupsDao.getDirectChildrenOf('root');
      expect(children.map((r) => r.id), ['alive']);
    });

    test('returns multiple children for the correct parent only', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root-a', displayOrder: 0));
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'root-b', displayOrder: 1));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child-a1', displayOrder: 0, parentGroupId: 'root-a'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child-b1', displayOrder: 0, parentGroupId: 'root-b'));

      final childrenA = await db.memberGroupsDao.getDirectChildrenOf('root-a');
      expect(childrenA.map((r) => r.id), ['child-a1']);

      final childrenB = await db.memberGroupsDao.getDirectChildrenOf('root-b');
      expect(childrenB.map((r) => r.id), ['child-b1']);
    });
  });

  // ── Repository: deleteGroupWithDescendants ──────────────────────────────────

  group('deleteGroupWithDescendants', () {
    late DriftMemberGroupsRepository repo;

    setUp(() {
      repo = DriftMemberGroupsRepository(db.memberGroupsDao, null);
    });

    test('sibling groups are NOT deleted', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'root-a', displayOrder: 0));
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'root-b', displayOrder: 1));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child-a', displayOrder: 0, parentGroupId: 'root-a'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child-b', displayOrder: 0, parentGroupId: 'root-b'));

      await repo.deleteGroupWithDescendants('root-a');

      final remaining = await db.memberGroupsDao.getAllActiveGroups();
      final ids = remaining.map((g) => g.id).toSet();
      expect(ids, contains('root-b'));
      expect(ids, contains('child-b'));
      expect(ids, isNot(contains('root-a')));
      expect(ids, isNot(contains('child-a')));
    });

    test('deletes root, child, and grandchild all at once', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      await repo.deleteGroupWithDescendants('root');

      final remaining = await db.memberGroupsDao.getAllActiveGroups();
      expect(remaining, isEmpty);
    });

    test('group with no children: only the target is deleted', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'leaf', displayOrder: 0));
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'other', displayOrder: 1));

      await repo.deleteGroupWithDescendants('leaf');

      final remaining = await db.memberGroupsDao.getAllActiveGroups();
      expect(remaining.map((g) => g.id), ['other']);
    });
  });

  // ── Repository: promoteChildrenToRoot ───────────────────────────────────────

  group('promoteChildrenToRoot', () {
    late DriftMemberGroupsRepository repo;

    setUp(() {
      repo = DriftMemberGroupsRepository(db.memberGroupsDao, null);
    });

    test('direct children get parentGroupId cleared', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));

      await repo.promoteChildrenToRoot('root');

      final active = await db.memberGroupsDao.getAllActiveGroups();
      final child = active.firstWhere((g) => g.id == 'child');
      expect(child.parentGroupId, isNull);
    });

    test('grandchildren are NOT promoted — only direct children', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      await repo.promoteChildrenToRoot('root');

      final active = await db.memberGroupsDao.getAllActiveGroups();
      final grandchild = active.firstWhere((g) => g.id == 'grandchild');
      // Grandchild still points to child, not null.
      expect(grandchild.parentGroupId, 'child');
    });

    test('the parent group is soft-deleted after promotion', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          pkFixtureGroup(id: 'child', displayOrder: 0, parentGroupId: 'root'));

      await repo.promoteChildrenToRoot('root');

      final active = await db.memberGroupsDao.getAllActiveGroups();
      expect(active.map((g) => g.id), isNot(contains('root')));
    });
  });

  // ── pending PK op queries (push orchestrator + reconcile) ───────────────────

  group('entriesForGroupForReconcile', () {
    test('returns active entries with pending_pk_op = none', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
          );

      final rows =
          await db.memberGroupsDao.entriesForGroupForReconcile('g');
      expect(rows.map((r) => r.id), ['e1']);
    });

    test('returns active entries with push_add intent', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'e1',
              groupId: 'g',
              memberId: 'm1',
              pendingPkOp: 'push_add',
            ),
          );

      final rows =
          await db.memberGroupsDao.entriesForGroupForReconcile('g');
      expect(rows, hasLength(1));
      expect(rows.single.pendingPkOp, 'push_add');
    });

    test(
      'returns soft-deleted entries with push_remove intent (so reconcile '
      'does not revive them when PK still reports the member)',
      () async {
        await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(
                id: 'e1',
                groupId: 'g',
                memberId: 'm1',
                isDeleted: true,
                pendingPkOp: 'push_remove',
              ),
            );

        final rows =
            await db.memberGroupsDao.entriesForGroupForReconcile('g');
        expect(rows, hasLength(1));
        expect(rows.single.isDeleted, isTrue);
        expect(rows.single.pendingPkOp, 'push_remove');
      },
    );

    test(
      'EXCLUDES soft-deleted entries with pending_pk_op = none (the existing '
      'reconcile semantic — done with this row)',
      () async {
        await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(
                id: 'e1',
                groupId: 'g',
                memberId: 'm1',
                isDeleted: true,
              ),
            );

        final rows =
            await db.memberGroupsDao.entriesForGroupForReconcile('g');
        expect(rows, isEmpty);
      },
    );

    test('scopes to the requested group', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g1'));
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g2'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'a', groupId: 'g1', memberId: 'm1'),
          );
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'b',
              groupId: 'g2',
              memberId: 'm1',
              pendingPkOp: 'push_add',
            ),
          );

      final rows =
          await db.memberGroupsDao.entriesForGroupForReconcile('g1');
      expect(rows.map((r) => r.id), ['a']);
    });
  });

  group('entriesForGroupIncludingDeleted (F06)', () {
    test(
      'returns a peer-originated tombstone (soft-deleted, pending=none) that '
      'entriesForGroupForReconcile hides',
      () async {
        await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(id: 'live', groupId: 'g', memberId: 'm1'),
            );
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(
                id: 'peer-tomb',
                groupId: 'g',
                memberId: 'm2',
                isDeleted: true,
              ),
            );

        final reconcile =
            await db.memberGroupsDao.entriesForGroupForReconcile('g');
        expect(reconcile.map((r) => r.id), ['live']);

        final full =
            await db.memberGroupsDao.entriesForGroupIncludingDeleted('g');
        expect(full.map((r) => r.id).toSet(), {'live', 'peer-tomb'});
      },
    );

    test('scopes to the requested group', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g1'));
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g2'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'a',
              groupId: 'g1',
              memberId: 'm1',
              isDeleted: true,
            ),
          );
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'b', groupId: 'g2', memberId: 'm1'),
          );

      final rows =
          await db.memberGroupsDao.entriesForGroupIncludingDeleted('g1');
      expect(rows.map((r) => r.id), ['a']);
    });
  });

  group('markEntryPushRemoveGuarded (F06)', () {
    test('flips a synced tombstone (deleted, pending=none) to push_remove',
        () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'e1',
              groupId: 'g',
              memberId: 'm1',
              isDeleted: true,
            ),
          );

      final hits = await db.memberGroupsDao.markEntryPushRemoveGuarded('e1');
      expect(hits, 1);
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((e) => e.id.equals('e1'))).getSingle();
      expect(row.pendingPkOp, 'push_remove');
    });

    test('does NOT touch an active row (guard misses)', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
          );

      final hits = await db.memberGroupsDao.markEntryPushRemoveGuarded('e1');
      expect(hits, 0);
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((e) => e.id.equals('e1'))).getSingle();
      expect(row.pendingPkOp, 'none');
    });

    test('does NOT clobber an in-flight local intent (push_add/push_remove)',
        () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'add',
              groupId: 'g',
              memberId: 'm1',
              isDeleted: true,
              pendingPkOp: 'push_add',
            ),
          );

      final hits = await db.memberGroupsDao.markEntryPushRemoveGuarded('add');
      expect(hits, 0);
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((e) => e.id.equals('add'))).getSingle();
      expect(row.pendingPkOp, 'push_add');
    });

    test(
      'refreshes created_at so an old-stamp tombstone is not born expired '
      '(M15 — the F06 sweep adopts pre-upgrade/offline tombstones)',
      () async {
        await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(
                id: 'e1',
                groupId: 'g',
                memberId: 'm1',
                isDeleted: true,
              ),
            );
        // The precise F06 case: a peer tombstone applied long before the user
        // upgraded / re-enabled PK pull, far older than pushRetryMaxAge.
        await (db.update(db.memberGroupEntries)
              ..where((e) => e.id.equals('e1')))
            .write(
          MemberGroupEntriesCompanion(
            createdAt:
                Value(DateTime.now().subtract(const Duration(days: 60))),
          ),
        );

        final before = DateTime.now().subtract(const Duration(seconds: 5));
        final hits = await db.memberGroupsDao.markEntryPushRemoveGuarded('e1');
        expect(hits, 1);

        final row = await (db.select(db.memberGroupEntries)
              ..where((e) => e.id.equals('e1')))
            .getSingle();
        expect(row.pendingPkOp, 'push_remove');
        expect(row.createdAt!.isAfter(before), isTrue,
            reason: 'adopting the remove intent must reset the intent-age '
                'clock so the cap gives it the full retry budget, not zero');
      },
    );
  });

  group('entriesWithPendingPkOp', () {
    test('returns empty when no rows have pending intent', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'e1', groupId: 'g', memberId: 'm1'),
          );

      final rows = await db.memberGroupsDao.entriesWithPendingPkOp();
      expect(rows, isEmpty);
    });

    test('returns push_add and push_remove rows across all groups', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g1'));
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g2'));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'a',
              groupId: 'g1',
              memberId: 'm1',
              pendingPkOp: 'push_add',
            ),
          );
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'b',
              groupId: 'g2',
              memberId: 'm1',
              isDeleted: true,
              pendingPkOp: 'push_remove',
            ),
          );
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'c', groupId: 'g1', memberId: 'm2'),
          );

      final rows = await db.memberGroupsDao.entriesWithPendingPkOp();
      expect(rows.map((r) => r.id).toSet(), {'a', 'b'});
    });

    test(
      'returns push_add rows even when is_deleted is true — pre-push '
      'validation must be able to see this contradiction',
      () async {
        // This state can arise when a CRDT delete from another device flips
        // is_deleted on a row that locally still has push_add queued.
        await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g'));
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(
                id: 'a',
                groupId: 'g',
                memberId: 'm1',
                isDeleted: true,
                pendingPkOp: 'push_add',
              ),
            );

        final rows = await db.memberGroupsDao.entriesWithPendingPkOp();
        expect(rows, hasLength(1));
        expect(rows.single.isDeleted, isTrue);
        expect(rows.single.pendingPkOp, 'push_add');
      },
    );
  });

  // ── updateGroupSortState ──────────────────────────────────────────────────

  group('updateGroupSortState', () {
    test('writes sort_state JSON to the targeted group row', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'g1', displayOrder: 0));

      const json = '{"mode":1,"order":["a","b"]}';
      final affected = await db.memberGroupsDao
          .updateGroupSortState('g1', json);

      expect(affected, 1);
      final row = await db.memberGroupsDao.getGroupById('g1');
      expect(row, isNotNull);
      expect(row!.sortState, json);
    });

    test('second call wins — last write semantics, no transaction abort',
        () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'g2', displayOrder: 0));

      const first = '{"mode":1,"order":["a","b"]}';
      const second = '{"mode":0,"order":["b","a","c"]}';

      final firstAffected =
          await db.memberGroupsDao.updateGroupSortState('g2', first);
      final secondAffected =
          await db.memberGroupsDao.updateGroupSortState('g2', second);

      expect(firstAffected, 1);
      expect(secondAffected, 1);

      final row = await db.memberGroupsDao.getGroupById('g2');
      expect(row, isNotNull);
      expect(row!.sortState, second);
    });

    test('does not affect other groups', () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'target', displayOrder: 0));
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'sibling', displayOrder: 1));

      const targetJson = '{"mode":2,"order":[]}';
      await db.memberGroupsDao.updateGroupSortState('target', targetJson);

      final target = await db.memberGroupsDao.getGroupById('target');
      final sibling = await db.memberGroupsDao.getGroupById('sibling');
      expect(target!.sortState, targetJson);
      // Default carried through the table default.
      expect(sibling!.sortState, '{"mode":0,"order":[]}');
    });

    test('returns 0 when no row matches the id', () async {
      final affected = await db.memberGroupsDao
          .updateGroupSortState('nonexistent', '{"mode":0,"order":[]}');
      expect(affected, 0);
    });
  });

  // Guarded DAO helpers added for the PK audit fixes.
  group('PK audit DAO methods', () {
    test('getGroupByIdIncludingDeleted finds a tombstone (M13)', () async {
      await db.into(db.memberGroups).insert(
            pkFixtureGroup(id: 'g1', isDeleted: true),
          );
      final row = await db.memberGroupsDao.getGroupByIdIncludingDeleted('g1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      // The active-only accessor must NOT see it.
      expect(await db.memberGroupsDao.getGroupById('g1'), isNull);
    });

    test('getGroupByIdIncludingDeleted returns null for an unknown id',
        () async {
      expect(
        await db.memberGroupsDao.getGroupByIdIncludingDeleted('nope'),
        isNull,
      );
    });

    test(
      'deleteGroup soft-deletes the group + its entries and KEEPS '
      'pluralkit_uuid on the tombstone (wave-3 verifier issue 3 / F15 — uuid '
      'findability for the tombstone-aware importer guard)',
      () async {
        await db.into(db.memberGroups).insert(
              pkFixtureGroup(id: 'g1', pluralkitUuid: 'pk-g1'),
            );
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(id: 'e1', groupId: 'g1', memberId: 'm1'),
            );

        await db.memberGroupsDao.deleteGroup('g1');

        final tombstone =
            await db.memberGroupsDao.getGroupByIdIncludingDeleted('g1');
        expect(tombstone!.isDeleted, isTrue);
        // F15: the uuid is PRESERVED on the soft-deleted row (the pre-fix
        // deleteGroup nulled it, which erased the tombstone evidence the
        // importer's resurrection guard relies on). The partial unique index
        // only covers active rows, so a tombstone can and must keep its uuid.
        expect(tombstone.pluralkitUuid, 'pk-g1',
            reason: 'the tombstone must keep its uuid for guard findability');

        // The group's entries are soft-deleted, not left active.
        final entry = await (db.select(db.memberGroupEntries)
              ..where((e) => e.id.equals('e1')))
            .getSingle();
        expect(entry.isDeleted, isTrue,
            reason: 'deleteGroup must soft-delete the group\'s entries too');

        // And the uuid-keyed tombstone lookup the importer guard uses sees it.
        final byUuid = await db.memberGroupsDao
            .findByPluralkitUuidIncludingDeleted('pk-g1');
        expect(byUuid, isNotNull);
        expect(byUuid!.id, 'g1');
        // Re-import-shaped insert under the same uuid must not violate the
        // partial unique index (tombstones are excluded from it).
        await db.into(db.memberGroups).insert(
              pkFixtureGroup(id: 'g1-new', pluralkitUuid: 'pk-g1'),
            );
      },
    );

    test(
      'softDeleteEntryWithPendingOp refreshes created_at '
      '(intent age, not row age)',
      () async {
        await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g1'));
        await db.into(db.memberGroupEntries).insert(
              pkFixtureEntry(id: 'e1', groupId: 'g1', memberId: 'm1'),
            );
        // Backdate to simulate a steady-state membership far older than the
        // push retry cap.
        await (db.update(db.memberGroupEntries)
              ..where((e) => e.id.equals('e1')))
            .write(
          MemberGroupEntriesCompanion(
            createdAt:
                Value(DateTime.now().subtract(const Duration(days: 60))),
          ),
        );

        final before = DateTime.now().subtract(const Duration(seconds: 5));
        await db.memberGroupsDao.softDeleteEntryWithPendingOp(
          'e1',
          pendingPkOp: 'push_remove',
        );

        final row = await (db.select(db.memberGroupEntries)
              ..where((e) => e.id.equals('e1')))
            .getSingle();
        expect(row.isDeleted, isTrue);
        expect(row.pendingPkOp, 'push_remove');
        expect(row.createdAt!.isAfter(before), isTrue,
            reason: 'queuing a remove must reset the intent-age clock');
      },
    );

    test('member_group_entries.created_at clientDefault stamps now on insert',
        () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g1'));
      final before = DateTime.now().subtract(const Duration(seconds: 5));
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(id: 'e1', groupId: 'g1', memberId: 'm1'),
          );
      final row = await (db.select(db.memberGroupEntries)
            ..where((e) => e.id.equals('e1')))
          .getSingle();
      expect(row.createdAt, isNotNull);
      expect(row.createdAt!.isAfter(before), isTrue,
          reason: 'clientDefault must stamp a recent created_at (H6b)');
    });

    test('softDeleteEntryWithPendingOpGuarded only fires on the expected state '
        '(H6c)', () async {
      await db.into(db.memberGroups).insert(pkFixtureGroup(id: 'g1'));
      // Active row, push_remove (the CRDT-revive shape).
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'e1',
              groupId: 'g1',
              memberId: 'm1',
              pendingPkOp: 'push_remove',
            ),
          );

      // Matches expectedActive=true → re-tombstones.
      final hits = await db.memberGroupsDao.softDeleteEntryWithPendingOpGuarded(
        'e1',
        pendingPkOp: 'push_remove',
        expectedActive: true,
      );
      expect(hits, 1);
      var row = await (db.select(db.memberGroupEntries)
            ..where((e) => e.id.equals('e1')))
          .getSingle();
      expect(row.isDeleted, isTrue);

      // A second call expecting active now MISSES (row is already deleted).
      final miss = await db.memberGroupsDao.softDeleteEntryWithPendingOpGuarded(
        'e1',
        pendingPkOp: 'push_remove',
        expectedActive: true,
      );
      expect(miss, 0);

      // A push_add row is never matched (guard requires push_remove).
      await db.into(db.memberGroupEntries).insert(
            pkFixtureEntry(
              id: 'e2',
              groupId: 'g1',
              memberId: 'm2',
              pendingPkOp: 'push_add',
            ),
          );
      final addMiss = await db.memberGroupsDao
          .softDeleteEntryWithPendingOpGuarded(
        'e2',
        pendingPkOp: 'push_remove',
        expectedActive: true,
      );
      expect(addMiss, 0);
      row = await (db.select(db.memberGroupEntries)
            ..where((e) => e.id.equals('e2')))
          .getSingle();
      expect(row.isDeleted, isFalse,
          reason: 'a concurrent push_add re-add must not be clobbered (H6c)');
    });
  });
}
