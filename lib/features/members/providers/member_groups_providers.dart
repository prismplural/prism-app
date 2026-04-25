import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';

// ── Stream providers ──────────────────────────────────────────────────────────

/// Watches all non-deleted groups ordered by displayOrder.
final allGroupsProvider = StreamProvider<List<MemberGroup>>((ref) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchAllGroups();
});

/// Watches groups that a specific member belongs to.
final memberGroupsProvider =
    StreamProvider.autoDispose.family<List<MemberGroup>, String>((ref, memberId) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchGroupsForMember(memberId);
});

/// Watches entries (group–member links) for a specific group.
final groupEntriesProvider =
    StreamProvider.autoDispose.family<List<MemberGroupEntry>, String>((ref, groupId) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchGroupEntries(groupId);
});

/// Watches a single group by ID.
final groupByIdProvider =
    StreamProvider.autoDispose.family<MemberGroup?, String>((ref, id) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchGroupById(id);
});

/// Watches all non-deleted group entries across every group.
final allGroupEntriesProvider = StreamProvider<List<MemberGroupEntry>>((ref) {
  return ref.watch(memberGroupsRepositoryProvider).watchAllGroupEntries();
});

// ── Tree providers ────────────────────────────────────────────────────────────

/// Hierarchical tree built from [allGroupsProvider] in a single O(n) pass.
/// Cycles from sync are resolved before building the tree.
final groupTreeProvider = Provider<Map<String?, List<MemberGroup>>>((ref) {
  final groups = ref.watch(allGroupsProvider).value ?? [];
  return GroupTreeUtils.buildGroupTree(
    GroupTreeUtils.resolveSyncCycles(groups),
  );
});

/// Memoized DFS flattening of [groupTreeProvider] into a depth-annotated list.
/// Recomputes only when the group tree changes — not on every widget rebuild.
final flatGroupListProvider =
    Provider<List<({MemberGroup group, int depth})>>((ref) {
  final tree = ref.watch(groupTreeProvider);
  return GroupTreeUtils.flattenTree(tree);
});

/// Direct children of a group (or root groups when [parentId] is null).
/// Derived from [groupTreeProvider] — no extra DB watch.
final childGroupsProvider =
    Provider.family<List<MemberGroup>, String?>((ref, parentId) {
  final tree = ref.watch(groupTreeProvider);
  return tree[parentId] ?? [];
});

/// All unique member IDs across a group and all its descendants.
final transitiveGroupMemberIdsProvider =
    Provider.family<Set<String>, String>((ref, groupId) {
  final tree = ref.watch(groupTreeProvider);
  final descendantGroupIds =
      GroupTreeUtils.getDescendantGroupIds(groupId, tree);
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];
  return allEntries
      .where((e) =>
          e.groupId == groupId || descendantGroupIds.contains(e.groupId))
      .map((e) => e.memberId)
      .toSet();
});

/// Transitive unique member counts per group.
/// Replaces the former StreamProvider-backed direct-count; callers should read
/// this map directly (no `.value` unwrap needed).
final groupMemberCountsProvider = Provider<Map<String, int>>((ref) {
  final tree = ref.watch(groupTreeProvider);
  final allGroups = ref.watch(allGroupsProvider).value ?? [];
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];

  // Pre-bucket entries in one O(E) pass to avoid O(N×E) per-group scans.
  final membersByGroup = <String, Set<String>>{};
  for (final entry in allEntries) {
    membersByGroup.putIfAbsent(entry.groupId, () => {}).add(entry.memberId);
  }

  return {
    for (final group in allGroups)
      group.id: {
        ...?membersByGroup[group.id],
        for (final did in GroupTreeUtils.getDescendantGroupIds(group.id, tree))
          ...?membersByGroup[did],
      }.length,
  };
});

// ── Collapsed state ───────────────────────────────────────────────────────────

/// In-memory set of group IDs whose section is collapsed in the members tab.
/// Resets to empty (all expanded) on app restart.
class CollapsedGroupsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String groupId) {
    state = state.contains(groupId)
        ? state.difference({groupId})
        : {...state, groupId};
  }

  void expandAll() => state = <String>{};
}

final collapsedGroupsProvider =
    NotifierProvider<CollapsedGroupsNotifier, Set<String>>(
        CollapsedGroupsNotifier.new);

/// When true, the grouped member list includes inactive members.
/// Kept in sync with the show-inactive toggle in MembersScreen.
class ShowInactiveInGroupedListNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final showInactiveInGroupedListProvider =
    NotifierProvider<ShowInactiveInGroupedListNotifier, bool>(
        ShowInactiveInGroupedListNotifier.new);

// ── Grouped member list ───────────────────────────────────────────────────────

/// Items in the members tab grouped list.
sealed class GroupedMemberListItem {
  const GroupedMemberListItem();
}

class GroupSectionItem extends GroupedMemberListItem {
  const GroupSectionItem({
    required this.group,
    required this.depth,
    required this.isCollapsed,
  });

  final MemberGroup group;

  /// 0 = root, 1 = sub-group, 2 = sub-sub-group.
  final int depth;
  final bool isCollapsed;
}

class MemberRowItem extends GroupedMemberListItem {
  const MemberRowItem({required this.member, required this.depth});

  final Member member;

  /// Indent level matching the owning group's depth.
  final int depth;
}

class UngroupedSectionItem extends GroupedMemberListItem {
  const UngroupedSectionItem();
}

/// Fully-expanded structural list (no collapse applied).
/// Rebuilds only when tree, entries, or members change — not on every toggle.
final _groupedMemberListStructureProvider =
    Provider<List<GroupedMemberListItem>>((ref) {
  final tree = ref.watch(groupTreeProvider);
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];
  final allMembers = ref.watch(allMembersProvider).value ?? [];
  final showInactive = ref.watch(showInactiveInGroupedListProvider);

  final memberById = {for (final m in allMembers) m.id: m};

  // Single pass: build direct-member map and grouped-id set simultaneously.
  final directMembersByGroup = <String, List<Member>>{};
  final groupedMemberIds = <String>{};
  for (final entry in allEntries) {
    groupedMemberIds.add(entry.memberId);
    final member = memberById[entry.memberId];
    if (member != null && (showInactive || member.isActive)) {
      directMembersByGroup.putIfAbsent(entry.groupId, () => []).add(member);
    }
  }

  final result = <GroupedMemberListItem>[];

  void visitGroup(MemberGroup group, int depth) {
    result.add(GroupSectionItem(group: group, depth: depth, isCollapsed: false));
    for (final child in tree[group.id] ?? []) {
      visitGroup(child, depth + 1);
    }
    for (final member in directMembersByGroup[group.id] ?? []) {
      result.add(MemberRowItem(member: member, depth: depth));
    }
  }

  for (final root in tree[null] ?? []) {
    visitGroup(root, 0);
  }

  final ungrouped = allMembers
      .where((m) =>
          (showInactive || m.isActive) && !groupedMemberIds.contains(m.id))
      .toList();
  if (ungrouped.isNotEmpty) {
    result.add(const UngroupedSectionItem());
    for (final m in ungrouped) {
      result.add(MemberRowItem(member: m, depth: 0));
    }
  }

  return result;
});

/// Flat ordered list driving the members tab grouped list.
///
/// Order: DFS group traversal (header → sub-group sections → direct members),
/// followed by an ungrouped section when ungrouped active members exist.
///
/// Derived from [_groupedMemberListStructureProvider] by applying collapse
/// state in a single linear pass — avoids a full DFS rebuild on every toggle.
final groupedMemberListProvider =
    Provider<List<GroupedMemberListItem>>((ref) {
  final structure = ref.watch(_groupedMemberListStructureProvider);
  final collapsed = ref.watch(collapsedGroupsProvider);

  // Fast path: nothing collapsed, return the structural list directly.
  if (collapsed.isEmpty) return structure;

  final result = <GroupedMemberListItem>[];
  int? hiddenAtDepth; // depth of the outermost collapsed section, or null

  for (final item in structure) {
    if (item is GroupSectionItem) {
      if (hiddenAtDepth != null) {
        if (item.depth > hiddenAtDepth) continue; // nested inside collapsed
        hiddenAtDepth = null; // resurfaced to same or shallower depth
      }
      final isCollapsed = collapsed.contains(item.group.id);
      result.add(GroupSectionItem(
          group: item.group, depth: item.depth, isCollapsed: isCollapsed));
      if (isCollapsed) hiddenAtDepth = item.depth;
    } else if (item is MemberRowItem) {
      if (hiddenAtDepth != null) {
        // Member row inside a collapsed subtree (same depth as collapsed
        // section = the collapsed group's own members; greater depth = a
        // descendant's members). Both should be hidden.
        if (item.depth >= hiddenAtDepth) continue;
        // Shallower depth means we've resurfaced to an ancestor's direct
        // members — those are emitted after the subtree in DFS order.
        hiddenAtDepth = null;
      }
      result.add(item);
    } else if (item is UngroupedSectionItem) {
      hiddenAtDepth = null;
      result.add(item);
    }
  }

  return result;
});

// ── Notifiers ─────────────────────────────────────────────────────────────────

/// Notifier for group CRUD and membership mutations.
class GroupNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createGroup(MemberGroup group) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.createGroup(group);
    });
  }

  Future<void> updateGroup(MemberGroup group) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.updateGroup(group);
    });
  }

  Future<void> reorderGroups(List<MemberGroup> groups) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      for (int i = 0; i < groups.length; i++) {
        if (groups[i].displayOrder != i) {
          await repo.updateGroup(groups[i].copyWith(displayOrder: i));
        }
      }
    });
  }

  Future<void> deleteGroup(String groupId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.deleteGroup(groupId);
    });
  }

  Future<void> promoteChildrenToRoot(String groupId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.promoteChildrenToRoot(groupId);
    });
  }

  Future<void> deleteGroupWithDescendants(String groupId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.deleteGroupWithDescendants(groupId);
    });
  }

  Future<void> addMemberToGroup(String groupId, String memberId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      final entryId = _uuid.v4();
      await repo.addMemberToGroup(groupId, memberId, entryId);
    });
  }

  Future<void> removeMemberFromGroup(
      String groupId, String memberId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.removeMemberFromGroup(groupId, memberId);
    });
  }
}

final groupNotifierProvider =
    AsyncNotifierProvider<GroupNotifier, void>(GroupNotifier.new);

/// Notifier for the active group filter selection.
/// null = show all, '__ungrouped__' = ungrouped members, any other value = group ID.
class ActiveGroupFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? filter) => state = filter;
}

final activeGroupFilterProvider =
    NotifierProvider.autoDispose<ActiveGroupFilterNotifier, String?>(
        ActiveGroupFilterNotifier.new);

/// True when at least one active member has no group entry.
final ungroupedMembersExistProvider = Provider.autoDispose<bool>((ref) {
  final members = ref.watch(allMembersProvider).value ?? [];
  final entries = ref.watch(allGroupEntriesProvider).value ?? [];
  final groupedMemberIds = entries.map((e) => e.memberId).toSet();
  return members.any((m) => m.isActive && !groupedMemberIds.contains(m.id));
});
