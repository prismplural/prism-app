import 'package:prism_plurality/domain/models/member_group.dart';

/// Pure Dart utilities for building and querying the in-memory group hierarchy.
///
/// The tree is represented as `Map<String?, List<MemberGroup>>` keyed by
/// `parentGroupId`. `null` key holds root groups (no parent).
class GroupTreeUtils {
  GroupTreeUtils._();

  /// Build an O(n) adjacency map from a flat list.
  ///
  /// Groups whose `parentGroupId` does not exist in the list are treated as
  /// roots (dangling parent → null key).
  static Map<String?, List<MemberGroup>> buildGroupTree(
      List<MemberGroup> groups) {
    final ids = {for (final g in groups) g.id};
    final tree = <String?, List<MemberGroup>>{};
    for (final g in groups) {
      final parentKey =
          (g.parentGroupId != null && ids.contains(g.parentGroupId))
              ? g.parentGroupId
              : null;
      tree.putIfAbsent(parentKey, () => []).add(g);
    }
    return tree;
  }

  /// Walk up the `parentGroupId` chain up to 3 hops. Returns 1 for root groups.
  ///
  /// Groups deeper than 3 (from sync) are clamped and reported as depth 3.
  static int getGroupDepth(
      String groupId, Map<String?, List<MemberGroup>> tree) {
    final idMap = _buildIdMap(tree);
    int depth = 1;
    String? currentId = groupId;
    for (int i = 0; i < 3; i++) {
      final group = idMap[currentId];
      if (group == null || group.parentGroupId == null) break;
      final parent = idMap[group.parentGroupId!];
      if (parent == null) break; // dangling parent → stop
      depth++;
      currentId = group.parentGroupId;
    }
    return depth;
  }

  /// DFS-collect all descendant group IDs (children, grandchildren, etc.).
  ///
  /// Does not include [groupId] itself. Respects the 3-level cap implicitly
  /// because the tree was built from validated/clamped data.
  static Set<String> getDescendantGroupIds(
      String groupId, Map<String?, List<MemberGroup>> tree) {
    final result = <String>{};
    final queue = <String>[groupId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final children = tree[current] ?? [];
      for (final child in children) {
        if (result.add(child.id)) {
          queue.add(child.id);
        }
      }
    }
    return result;
  }

  /// Returns `true` if setting [proposedParentId] as the parent of [groupId]
  /// would create a cycle (i.e. [proposedParentId] is already a descendant).
  static bool wouldCreateCycle(String groupId, String proposedParentId,
      Map<String?, List<MemberGroup>> tree) {
    if (groupId == proposedParentId) return true;
    return getDescendantGroupIds(groupId, tree).contains(proposedParentId);
  }

  /// Break any cycles present in a synced flat list.
  ///
  /// For each group involved in a cycle, the *newer* group (later `createdAt`)
  /// is promoted to root; the older group keeps its position. This is
  /// deterministic: both devices running this algorithm converge to the same
  /// result because `createdAt` is immutable and unique enough in practice.
  static List<MemberGroup> resolveSyncCycles(List<MemberGroup> groups) {
    final idMap = {for (final g in groups) g.id: g};
    final result = List<MemberGroup>.from(groups);

    for (int i = 0; i < result.length; i++) {
      final g = result[i];
      if (g.parentGroupId == null) continue;
      if (!idMap.containsKey(g.parentGroupId)) continue; // dangling, not a cycle

      // Walk up to detect a cycle involving g.
      final visited = <String>{g.id};
      String? current = g.parentGroupId;
      bool hasCycle = false;
      while (current != null && idMap.containsKey(current)) {
        if (visited.contains(current)) {
          hasCycle = true;
          break;
        }
        visited.add(current);
        current = idMap[current]?.parentGroupId;
      }

      if (hasCycle) {
        final parent = idMap[g.parentGroupId!];
        if (parent != null && g.createdAt.isAfter(parent.createdAt)) {
          // This group is newer → break cycle by making it a root.
          result[i] = g.copyWith(parentGroupId: null);
          idMap[g.id] = result[i];
        }
        // If g is older, we leave it; the parent will be promoted when its
        // turn comes.
      }
    }

    return result;
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  static Map<String, MemberGroup> _buildIdMap(
      Map<String?, List<MemberGroup>> tree) {
    final map = <String, MemberGroup>{};
    for (final groups in tree.values) {
      for (final g in groups) {
        map[g.id] = g;
      }
    }
    return map;
  }
}
