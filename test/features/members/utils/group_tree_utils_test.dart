import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';

MemberGroup _group({
  required String id,
  String? parentGroupId,
  DateTime? createdAt,
}) =>
    MemberGroup(
      id: id,
      name: id,
      createdAt: createdAt ?? DateTime(2024, 1, 1),
      parentGroupId: parentGroupId,
    );

void main() {
  // ── buildGroupTree ──────────────────────────────────────────────────────────

  group('buildGroupTree', () {
    test('empty list returns empty map', () {
      final tree = GroupTreeUtils.buildGroupTree([]);
      expect(tree, isEmpty);
    });

    test('root groups are keyed under null', () {
      final a = _group(id: 'a');
      final b = _group(id: 'b');
      final tree = GroupTreeUtils.buildGroupTree([a, b]);
      expect(tree[null]?.map((g) => g.id), containsAll(['a', 'b']));
      expect(tree.length, 1);
    });

    test('child groups are keyed under their parent id', () {
      final root = _group(id: 'root');
      final child = _group(id: 'child', parentGroupId: 'root');
      final tree = GroupTreeUtils.buildGroupTree([root, child]);
      expect(tree[null]?.map((g) => g.id), contains('root'));
      expect(tree['root']?.map((g) => g.id), contains('child'));
    });

    test('dangling parentGroupId is treated as root', () {
      final orphan = _group(id: 'orphan', parentGroupId: 'nonexistent');
      final tree = GroupTreeUtils.buildGroupTree([orphan]);
      expect(tree[null]?.map((g) => g.id), contains('orphan'));
    });

    test('three-level hierarchy is keyed correctly', () {
      final root = _group(id: 'root');
      final sub = _group(id: 'sub', parentGroupId: 'root');
      final subsub = _group(id: 'subsub', parentGroupId: 'sub');
      final tree = GroupTreeUtils.buildGroupTree([root, sub, subsub]);
      expect(tree[null]?.map((g) => g.id), contains('root'));
      expect(tree['root']?.map((g) => g.id), contains('sub'));
      expect(tree['sub']?.map((g) => g.id), contains('subsub'));
    });
  });

  // ── getGroupDepth ───────────────────────────────────────────────────────────

  group('getGroupDepth', () {
    late Map<String?, List<MemberGroup>> tree;

    setUp(() {
      final root = _group(id: 'root');
      final sub = _group(id: 'sub', parentGroupId: 'root');
      final subsub = _group(id: 'subsub', parentGroupId: 'sub');
      tree = GroupTreeUtils.buildGroupTree([root, sub, subsub]);
    });

    test('root group has depth 1', () {
      expect(GroupTreeUtils.getGroupDepth('root', tree), 1);
    });

    test('child of root has depth 2', () {
      expect(GroupTreeUtils.getGroupDepth('sub', tree), 2);
    });

    test('grandchild has depth 3', () {
      expect(GroupTreeUtils.getGroupDepth('subsub', tree), 3);
    });

    test('depth 3 is allowed (exactly 3 levels)', () {
      expect(GroupTreeUtils.getGroupDepth('subsub', tree), equals(3));
    });

    test('unknown group id returns depth 1', () {
      expect(GroupTreeUtils.getGroupDepth('missing', tree), 1);
    });

    test('dangling parent is treated as root (depth 1)', () {
      final orphan = _group(id: 'orphan', parentGroupId: 'ghost');
      final t = GroupTreeUtils.buildGroupTree([orphan]);
      expect(GroupTreeUtils.getGroupDepth('orphan', t), 1);
    });
  });

  // ── getDescendantGroupIds ───────────────────────────────────────────────────

  group('getDescendantGroupIds', () {
    test('leaf group has no descendants', () {
      final a = _group(id: 'a');
      final tree = GroupTreeUtils.buildGroupTree([a]);
      expect(GroupTreeUtils.getDescendantGroupIds('a', tree), isEmpty);
    });

    test('includes direct children', () {
      final root = _group(id: 'root');
      final child = _group(id: 'child', parentGroupId: 'root');
      final tree = GroupTreeUtils.buildGroupTree([root, child]);
      expect(GroupTreeUtils.getDescendantGroupIds('root', tree), {'child'});
    });

    test('includes grandchildren', () {
      final root = _group(id: 'root');
      final sub = _group(id: 'sub', parentGroupId: 'root');
      final subsub = _group(id: 'subsub', parentGroupId: 'sub');
      final tree = GroupTreeUtils.buildGroupTree([root, sub, subsub]);
      expect(GroupTreeUtils.getDescendantGroupIds('root', tree),
          {'sub', 'subsub'});
    });

    test('does not include the group itself', () {
      final root = _group(id: 'root');
      final child = _group(id: 'child', parentGroupId: 'root');
      final tree = GroupTreeUtils.buildGroupTree([root, child]);
      expect(GroupTreeUtils.getDescendantGroupIds('root', tree),
          isNot(contains('root')));
    });
  });

  // ── wouldCreateCycle ────────────────────────────────────────────────────────

  group('wouldCreateCycle', () {
    test('self-loop is a cycle', () {
      final a = _group(id: 'a');
      final tree = GroupTreeUtils.buildGroupTree([a]);
      expect(GroupTreeUtils.wouldCreateCycle('a', 'a', tree), isTrue);
    });

    test('child as proposed parent creates A→B→A cycle', () {
      final a = _group(id: 'a');
      final b = _group(id: 'b', parentGroupId: 'a');
      final tree = GroupTreeUtils.buildGroupTree([a, b]);
      expect(GroupTreeUtils.wouldCreateCycle('a', 'b', tree), isTrue);
    });

    test('grandchild as proposed parent creates A→B→C→A cycle', () {
      final a = _group(id: 'a');
      final b = _group(id: 'b', parentGroupId: 'a');
      final c = _group(id: 'c', parentGroupId: 'b');
      final tree = GroupTreeUtils.buildGroupTree([a, b, c]);
      expect(GroupTreeUtils.wouldCreateCycle('a', 'c', tree), isTrue);
    });

    test('sibling as proposed parent is not a cycle', () {
      final root = _group(id: 'root');
      final a = _group(id: 'a', parentGroupId: 'root');
      final b = _group(id: 'b', parentGroupId: 'root');
      final tree = GroupTreeUtils.buildGroupTree([root, a, b]);
      expect(GroupTreeUtils.wouldCreateCycle('a', 'b', tree), isFalse);
    });

    test('proposed parent at depth 3 is not itself a cycle', () {
      // Whether to reject it is a depth validation concern, not a cycle concern.
      final root = _group(id: 'root');
      final sub = _group(id: 'sub', parentGroupId: 'root');
      final subsub = _group(id: 'subsub', parentGroupId: 'sub');
      final other = _group(id: 'other');
      final tree = GroupTreeUtils.buildGroupTree([root, sub, subsub, other]);
      // 'other' is not a descendant of 'subsub', so no cycle.
      expect(GroupTreeUtils.wouldCreateCycle('other', 'subsub', tree), isFalse);
    });
  });

  // ── resolveSyncCycles ───────────────────────────────────────────────────────

  group('resolveSyncCycles', () {
    test('no cycles → list unchanged', () {
      final a = _group(id: 'a');
      final b = _group(id: 'b', parentGroupId: 'a');
      final result = GroupTreeUtils.resolveSyncCycles([a, b]);
      expect(result.map((g) => g.parentGroupId), [null, 'a']);
    });

    test('A→B→A: newer group becomes root', () {
      final older = _group(id: 'a', createdAt: DateTime(2024, 1, 1));
      final newer = _group(
          id: 'b', parentGroupId: 'a', createdAt: DateTime(2024, 6, 1));
      // Also wire a→b so there's a cycle: b.parentGroupId='a', a.parentGroupId='b'
      final aWithParent = older.copyWith(parentGroupId: 'b');
      final result =
          GroupTreeUtils.resolveSyncCycles([aWithParent, newer]);
      // 'a' is older (Jan) and 'b' is newer (Jun)
      // 'b' has a as parent; 'a' has b as parent → cycle
      // The newer one (b, Jun) should become root.
      final bResult = result.firstWhere((g) => g.id == 'b');
      expect(bResult.parentGroupId, isNull);
    });

    test('cycle broken by createdAt — older group keeps its parent', () {
      final older = _group(
          id: 'a', parentGroupId: 'b', createdAt: DateTime(2024, 1, 1));
      final newer = _group(
          id: 'b', parentGroupId: 'a', createdAt: DateTime(2024, 6, 1));
      final result = GroupTreeUtils.resolveSyncCycles([older, newer]);
      // 'a' is older → keeps its parent (though it will be resolved by buildGroupTree
      // since 'b' will become root, not a child of 'a').
      // 'b' is newer → becomes root.
      final bResult = result.firstWhere((g) => g.id == 'b');
      expect(bResult.parentGroupId, isNull);
    });

    test('dangling parent is not treated as a cycle', () {
      final orphan = _group(id: 'x', parentGroupId: 'ghost');
      final result = GroupTreeUtils.resolveSyncCycles([orphan]);
      // Should be unchanged — not a cycle, just a dangling ref.
      expect(result.first.parentGroupId, 'ghost');
    });

    test('valid tree with no cycles is returned unchanged', () {
      final root = _group(id: 'root');
      final sub = _group(id: 'sub', parentGroupId: 'root');
      final subsub = _group(id: 'subsub', parentGroupId: 'sub');
      final result = GroupTreeUtils.resolveSyncCycles([root, sub, subsub]);
      expect(result.map((g) => g.id), ['root', 'sub', 'subsub']);
      expect(result.map((g) => g.parentGroupId), [null, 'root', 'sub']);
    });
  });
}
