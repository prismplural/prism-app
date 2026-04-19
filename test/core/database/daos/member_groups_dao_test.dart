import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';

MemberGroupsCompanion _group({
  required String id,
  required int displayOrder,
  String? parentGroupId,
  bool isDeleted = false,
}) =>
    MemberGroupsCompanion.insert(
      id: id,
      name: id,
      createdAt: DateTime(2024, 1, 1),
      displayOrder: Value(displayOrder),
      parentGroupId: Value(parentGroupId),
      isDeleted: Value(isDeleted),
    );

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
      await db.into(db.memberGroups).insert(_group(id: 'a', displayOrder: 0));
      await db.into(db.memberGroups).insert(_group(id: 'b', displayOrder: 3));
      expect(await db.memberGroupsDao.nextDisplayOrder(null), 4);
    });

    test('returns 0 when no children exist under a parent', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      expect(await db.memberGroupsDao.nextDisplayOrder('root'), 0);
    });

    test('returns max + 1 for children of a given parent', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child-a', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          _group(id: 'child-b', displayOrder: 5, parentGroupId: 'root'));
      expect(await db.memberGroupsDao.nextDisplayOrder('root'), 6);
    });

    test('child siblings are scoped separately from root siblings', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 99));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 1, parentGroupId: 'root'));
      // Root max is 99 but child query should only see child siblings (max=1).
      expect(await db.memberGroupsDao.nextDisplayOrder('root'), 2);
      // Root query should only see root siblings (max=99).
      expect(await db.memberGroupsDao.nextDisplayOrder(null), 100);
    });

    test('soft-deleted groups are excluded from the count', () async {
      await db.into(db.memberGroups).insert(
          _group(id: 'dead', displayOrder: 100, isDeleted: true));
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
          .insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));

      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots.map((r) => r.id), ['root']);
    });

    test('child watch returns only direct children', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          _group(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      final children =
          await db.memberGroupsDao.watchChildGroups('root').first;
      expect(children.map((r) => r.id), ['child']);
    });

    test('soft-deleted groups are excluded', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'dead', displayOrder: 1, isDeleted: true));

      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots.map((r) => r.id), ['root']);
    });

    test('results are ordered by displayOrder ascending', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'c', displayOrder: 2));
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'a', displayOrder: 0));
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'b', displayOrder: 1));

      final roots = await db.memberGroupsDao.watchChildGroups(null).first;
      expect(roots.map((r) => r.id), ['a', 'b', 'c']);
    });
  });

  // ── getDirectChildrenOf ─────────────────────────────────────────────────────

  group('getDirectChildrenOf', () {
    test('returns empty list when group has no children', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      final children = await db.memberGroupsDao.getDirectChildrenOf('root');
      expect(children, isEmpty);
    });

    test('returns only direct children, not grandchildren', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          _group(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      final children = await db.memberGroupsDao.getDirectChildrenOf('root');
      expect(children.map((r) => r.id), ['child']);
    });

    test('excludes soft-deleted children', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'alive', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          _group(id: 'dead', displayOrder: 1, parentGroupId: 'root', isDeleted: true));

      final children = await db.memberGroupsDao.getDirectChildrenOf('root');
      expect(children.map((r) => r.id), ['alive']);
    });

    test('returns multiple children for the correct parent only', () async {
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root-a', displayOrder: 0));
      await db
          .into(db.memberGroups)
          .insert(_group(id: 'root-b', displayOrder: 1));
      await db.into(db.memberGroups).insert(
          _group(id: 'child-a1', displayOrder: 0, parentGroupId: 'root-a'));
      await db.into(db.memberGroups).insert(
          _group(id: 'child-b1', displayOrder: 0, parentGroupId: 'root-b'));

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
      await db.into(db.memberGroups).insert(_group(id: 'root-a', displayOrder: 0));
      await db.into(db.memberGroups).insert(_group(id: 'root-b', displayOrder: 1));
      await db.into(db.memberGroups).insert(
          _group(id: 'child-a', displayOrder: 0, parentGroupId: 'root-a'));
      await db.into(db.memberGroups).insert(
          _group(id: 'child-b', displayOrder: 0, parentGroupId: 'root-b'));

      await repo.deleteGroupWithDescendants('root-a');

      final remaining = await db.memberGroupsDao.getAllActiveGroups();
      final ids = remaining.map((g) => g.id).toSet();
      expect(ids, contains('root-b'));
      expect(ids, contains('child-b'));
      expect(ids, isNot(contains('root-a')));
      expect(ids, isNot(contains('child-a')));
    });

    test('deletes root, child, and grandchild all at once', () async {
      await db.into(db.memberGroups).insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          _group(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      await repo.deleteGroupWithDescendants('root');

      final remaining = await db.memberGroupsDao.getAllActiveGroups();
      expect(remaining, isEmpty);
    });

    test('group with no children: only the target is deleted', () async {
      await db.into(db.memberGroups).insert(_group(id: 'leaf', displayOrder: 0));
      await db.into(db.memberGroups).insert(_group(id: 'other', displayOrder: 1));

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
      await db.into(db.memberGroups).insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));

      await repo.promoteChildrenToRoot('root');

      final active = await db.memberGroupsDao.getAllActiveGroups();
      final child = active.firstWhere((g) => g.id == 'child');
      expect(child.parentGroupId, isNull);
    });

    test('grandchildren are NOT promoted — only direct children', () async {
      await db.into(db.memberGroups).insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));
      await db.into(db.memberGroups).insert(
          _group(id: 'grandchild', displayOrder: 0, parentGroupId: 'child'));

      await repo.promoteChildrenToRoot('root');

      final active = await db.memberGroupsDao.getAllActiveGroups();
      final grandchild = active.firstWhere((g) => g.id == 'grandchild');
      // Grandchild still points to child, not null.
      expect(grandchild.parentGroupId, 'child');
    });

    test('the parent group is soft-deleted after promotion', () async {
      await db.into(db.memberGroups).insert(_group(id: 'root', displayOrder: 0));
      await db.into(db.memberGroups).insert(
          _group(id: 'child', displayOrder: 0, parentGroupId: 'root'));

      await repo.promoteChildrenToRoot('root');

      final active = await db.memberGroupsDao.getAllActiveGroups();
      expect(active.map((g) => g.id), isNot(contains('root')));
    });
  });
}
