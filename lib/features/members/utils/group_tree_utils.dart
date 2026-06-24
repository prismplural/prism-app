import 'package:prism_plurality/domain/models/member_group.dart';

/// Pure Dart utilities for building and querying the in-memory group hierarchy.
///
/// The tree is represented as `Map<String?, List<MemberGroup>>` keyed by
/// `parentGroupId`. `null` key holds root groups (no parent).
class GroupTreeUtils {
  GroupTreeUtils._();

  /// Maximum iterations when walking the parent chain in [getGroupDepth].
  ///
  /// Defends against cycles that bypass [resolveSyncCycles]. The depth value
  /// saturates at this number (chains longer than this report as this depth).
  static const int _maxDepthIterations = 64;

  /// Build an O(n) adjacency map from a flat list.
  ///
  /// Groups whose `parentGroupId` does not exist in the list are treated as
  /// roots (dangling parent → null key).
  static Map<String?, List<MemberGroup>> buildGroupTree(
    List<MemberGroup> groups,
  ) {
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

  /// Walk up the `parentGroupId` chain. Returns 1 for root groups.
  ///
  /// Saturates at [_maxDepthIterations] to defend against cycles that bypass
  /// [resolveSyncCycles]. Cycles are also caught by the visited-set guard.
  static int getGroupDepth(
    String groupId,
    Map<String?, List<MemberGroup>> tree,
  ) {
    final idMap = _buildIdMap(tree);
    final visited = <String>{};
    int depth = 1;
    String? currentId = groupId;
    for (int i = 1; i < _maxDepthIterations; i++) {
      if (currentId == null) break;
      if (!visited.add(currentId)) break; // cycle guard
      final group = idMap[currentId];
      if (group == null || group.parentGroupId == null) break;
      if (!idMap.containsKey(group.parentGroupId)) break; // dangling parent → stop
      depth++;
      currentId = group.parentGroupId;
    }
    return depth;
  }

  /// Returns a `{groupId: depth}` map for every group in [tree], in a single pass.
  ///
  /// Use this when computing depths for many nodes at once (e.g. in a list view
  /// or picker) — calling [getGroupDepth] per node is O(n) per call due to the
  /// internal id-map rebuild.
  ///
  /// Implemented as an iterative DFS using an explicit stack to avoid blowing
  /// Dart's call stack on arbitrarily deep trees.
  static Map<String, int> getGroupDepthsAll(
    Map<String?, List<MemberGroup>> tree,
  ) {
    final depths = <String, int>{};
    final visited = <String>{};
    final stack = <(MemberGroup, int)>[];
    for (final root in tree[null] ?? const <MemberGroup>[]) {
      stack.add((root, 1));
    }
    while (stack.isNotEmpty) {
      final (g, d) = stack.removeLast();
      if (!visited.add(g.id)) continue; // cycle guard
      depths[g.id] = d;
      for (final child in tree[g.id] ?? const <MemberGroup>[]) {
        stack.add((child, d + 1));
      }
    }
    return depths;
  }

  /// DFS-collect all descendant group IDs (children, grandchildren, etc.).
  ///
  /// Does not include [groupId] itself.
  static Set<String> getDescendantGroupIds(
    String groupId,
    Map<String?, List<MemberGroup>> tree,
  ) {
    final result = <String>{};
    final queue = <String>[groupId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final children = tree[current] ?? const <MemberGroup>[];
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
  static bool wouldCreateCycle(
    String groupId,
    String proposedParentId,
    Map<String?, List<MemberGroup>> tree,
  ) {
    if (groupId == proposedParentId) return true;
    return getDescendantGroupIds(groupId, tree).contains(proposedParentId);
  }

  /// Break any cycles present in a synced flat list.
  ///
  /// For each group involved in a cycle, the *newer* group (later `createdAt`)
  /// is promoted to root; the older group keeps its position. When timestamps
  /// are equal, the group with the lexicographically greater `id` wins —
  /// ensuring both devices converge to the same result.
  static List<MemberGroup> resolveSyncCycles(List<MemberGroup> groups) {
    final idMap = {for (final g in groups) g.id: g};
    final result = List<MemberGroup>.from(groups);

    for (int i = 0; i < result.length; i++) {
      final g = result[i];
      if (g.parentGroupId == null) continue;
      if (!idMap.containsKey(g.parentGroupId)) {
        continue; // dangling, not a cycle
      }

      // A self-parent is a degenerate cycle the tiebreak below can't resolve
      // (a group can't win against itself); promote it to root deterministically.
      if (g.parentGroupId == g.id) {
        result[i] = g.copyWith(parentGroupId: null);
        idMap[g.id] = result[i];
        continue;
      }

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
        final winsOnTime =
            parent != null && g.createdAt.isAfter(parent.createdAt);
        final winsOnId =
            parent != null &&
            !g.createdAt.isBefore(parent.createdAt) &&
            g.id.compareTo(parent.id) > 0;
        if (winsOnTime || winsOnId) {
          // This group is newer (or same age with higher id) → break cycle.
          result[i] = g.copyWith(parentGroupId: null);
          idMap[g.id] = result[i];
        }
        // If g is older, we leave it; the parent will be promoted when its
        // turn comes.
      }
    }

    return result;
  }

  /// DFS flattening of the group tree into a depth-annotated list.
  /// Includes a visited-set guard to prevent infinite recursion from malformed
  /// trees (e.g. cycles slipping past `resolveSyncCycles`).
  static List<({MemberGroup group, int depth})> flattenTree(
    Map<String?, List<MemberGroup>> tree,
  ) {
    final result = <({MemberGroup group, int depth})>[];
    final visited = <String>{};
    void visit(MemberGroup g, int d) {
      if (!visited.add(g.id)) return; // cycle guard
      result.add((group: g, depth: d));
      for (final child in tree[g.id] ?? const <MemberGroup>[]) {
        visit(child, d + 1);
      }
    }

    for (final root in tree[null] ?? const <MemberGroup>[]) {
      visit(root, 0);
    }
    return result;
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  static Map<String, MemberGroup> _buildIdMap(
    Map<String?, List<MemberGroup>> tree,
  ) {
    final map = <String, MemberGroup>{};
    for (final groups in tree.values) {
      for (final g in groups) {
        map[g.id] = g;
      }
    }
    return map;
  }
}
