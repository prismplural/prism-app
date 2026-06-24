import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

// ── Stream providers ──────────────────────────────────────────────────────────

/// Watches all non-deleted groups ordered by displayOrder.
final allGroupsProvider = StreamProvider<List<MemberGroup>>((ref) {
  final repo = ref.watch(memberGroupsRepositoryProvider);
  return repo.watchAllGroups();
});

/// Watches groups that a specific member belongs to.
final memberGroupsProvider = StreamProvider.autoDispose
    .family<List<MemberGroup>, String>((ref, memberId) {
      final repo = ref.watch(memberGroupsRepositoryProvider);
      return repo.watchGroupsForMember(memberId);
    });

/// Watches entries (group–member links) for a specific group.
final groupEntriesProvider = StreamProvider.autoDispose
    .family<List<MemberGroupEntry>, String>((ref, groupId) {
      final repo = ref.watch(memberGroupsRepositoryProvider);
      return repo.watchGroupEntries(groupId);
    });

/// Watches a single group by ID.
final groupByIdProvider = StreamProvider.autoDispose
    .family<MemberGroup?, String>((ref, id) {
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
final flatGroupListProvider = Provider<List<({MemberGroup group, int depth})>>((
  ref,
) {
  final tree = ref.watch(groupTreeProvider);
  return GroupTreeUtils.flattenTree(tree);
});

/// Direct children of a group (or root groups when [parentId] is null).
/// Derived from [groupTreeProvider] — no extra DB watch.
final childGroupsProvider = Provider.family<List<MemberGroup>, String?>((
  ref,
  parentId,
) {
  final tree = ref.watch(groupTreeProvider);
  return tree[parentId] ?? [];
});

/// All unique member IDs across a group and all its descendants.
final transitiveGroupMemberIdsProvider = Provider.family<Set<String>, String>((
  ref,
  groupId,
) {
  final tree = ref.watch(groupTreeProvider);
  final descendantGroupIds = GroupTreeUtils.getDescendantGroupIds(
    groupId,
    tree,
  );
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];
  return allEntries
      .where(
        (e) => e.groupId == groupId || descendantGroupIds.contains(e.groupId),
      )
      .map((e) => e.memberId)
      .toSet();
});

/// Visibility-aware transitive unique member counts per group.
/// Replaces the former StreamProvider-backed direct-count; callers should read
/// this map directly (no `.value` unwrap needed).
final groupMemberCountsProvider = Provider<Map<String, int>>((ref) {
  final tree = ref.watch(groupTreeProvider);
  final allGroups = ref.watch(allGroupsProvider).value ?? [];
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];
  final showInactive = ref.watch(showInactiveMembersProvider);
  final allMembers = ref.watch(userVisibleAllMemberListProvider).value ?? [];
  final visibleMemberIds = {
    for (final member in allMembers)
      if (showInactive || member.isActive) member.id,
  };

  // Pre-bucket entries in one O(E) pass, then fold child sets upward once.
  // Calling `getDescendantGroupIds` for every group repeats subtree walks and
  // gets expensive in large, deeply nested systems.
  final membersByGroup = <String, Set<String>>{};
  for (final entry in allEntries) {
    if (!visibleMemberIds.contains(entry.memberId)) continue;
    membersByGroup.putIfAbsent(entry.groupId, () => {}).add(entry.memberId);
  }

  final counts = <String, int>{};
  final transitiveMembersByGroup = <String, Set<String>>{};
  final visited = <String>{};
  final stack = <(MemberGroup group, bool expanded)>[];
  final roots = tree[null] ?? const <MemberGroup>[];
  for (var i = roots.length - 1; i >= 0; i--) {
    stack.add((roots[i], false));
  }

  while (stack.isNotEmpty) {
    final (group, expanded) = stack.removeLast();
    if (!expanded) {
      if (!visited.add(group.id)) continue;
      stack.add((group, true));
      final children = tree[group.id] ?? const <MemberGroup>[];
      for (var i = children.length - 1; i >= 0; i--) {
        stack.add((children[i], false));
      }
      continue;
    }

    final members = <String>{...?membersByGroup[group.id]};
    for (final child in tree[group.id] ?? const <MemberGroup>[]) {
      members.addAll(transitiveMembersByGroup[child.id] ?? const <String>{});
    }
    transitiveMembersByGroup[group.id] = members;
    counts[group.id] = members.length;
  }

  for (final group in allGroups) {
    counts.putIfAbsent(group.id, () => membersByGroup[group.id]?.length ?? 0);
  }
  return counts;
});

// ── Collapsed state ───────────────────────────────────────────────────────────

/// In-memory set of group IDs whose section is collapsed in the members tab.
/// Resets to empty (all expanded) on app restart.
class CollapsedGroupsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final defaultState = ref.watch(membersGroupedDefaultStateProvider);
    if (defaultState == MembersGroupedDefaultState.open) return <String>{};
    return {
      for (final group in ref.watch(allGroupsProvider).value ?? <MemberGroup>[])
        group.id,
    };
  }

  void toggle(String groupId) {
    state = state.contains(groupId)
        ? state.difference({groupId})
        : {...state, groupId};
  }

  void expandAll() => state = <String>{};

  void collapseAll() {
    state = {
      for (final group in ref.read(allGroupsProvider).value ?? <MemberGroup>[])
        group.id,
    };
  }
}

final collapsedGroupsProvider =
    NotifierProvider<CollapsedGroupsNotifier, Set<String>>(
      CollapsedGroupsNotifier.new,
    );

/// When true, member-management surfaces include inactive members.
///
/// Shared by the members tab show-inactive toggle, the grouped member list,
/// and the group detail screen so toggling once applies everywhere.
class ShowInactiveMembersNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final showInactiveMembersProvider =
    NotifierProvider<ShowInactiveMembersNotifier, bool>(
      ShowInactiveMembersNotifier.new,
    );

/// Ordered (entry, member) pairs for a group's detail view.
///
/// Manual-mode read-path invariants:
///   1. Live entry not in manualOrder → appended at end.
///   2. Id in manualOrder without a live entry → filtered.
///   3. Duplicate id in manualOrder → first occurrence wins.
final sortedGroupMembersAsyncProvider =
    Provider.family<AsyncValue<List<(MemberGroupEntry, Member)>>, String>((
      ref,
      groupId,
    ) {
      final groupAsync = ref.watch(groupByIdProvider(groupId));
      final group = groupAsync.value;
      if (group == null) {
        return groupAsync.when(
          data: (_) => const AsyncValue.data(<(MemberGroupEntry, Member)>[]),
          loading: () => const AsyncValue.loading(),
          error: AsyncValue.error,
        );
      }

      final entriesAsync = ref.watch(groupEntriesProvider(groupId));
      final entries = entriesAsync.value;
      if (entries == null) {
        if (entriesAsync.hasError) {
          return AsyncValue.error(
            entriesAsync.error!,
            entriesAsync.stackTrace!,
          );
        }
        return const AsyncValue.loading();
      }
      if (entries.isEmpty) {
        return const AsyncValue.data(<(MemberGroupEntry, Member)>[]);
      }

      final memberIds = {for (final entry in entries) entry.memberId};
      final membersAsync = ref.watch(
        membersByIdsListProvider(memberIdsKey(memberIds)),
      );
      final membersById = membersAsync.value;
      if (membersById == null) {
        if (membersAsync.hasError) {
          return AsyncValue.error(
            membersAsync.error!,
            membersAsync.stackTrace!,
          );
        }
        return const AsyncValue.loading();
      }
      final showInactive = ref.watch(showInactiveMembersProvider);

      return AsyncValue.data(
        _sortGroupMemberPairs(
          group: group,
          entries: entries,
          membersById: membersById,
          showInactive: showInactive,
        ),
      );
    });

final sortedGroupMembersProvider =
    Provider.family<List<(MemberGroupEntry, Member)>, String>((ref, groupId) {
      return ref.watch(sortedGroupMembersAsyncProvider(groupId)).value ??
          const <(MemberGroupEntry, Member)>[];
    });

List<(MemberGroupEntry, Member)> _sortGroupMemberPairs({
  required MemberGroup group,
  required List<MemberGroupEntry> entries,
  required Map<String, Member> membersById,
  required bool showInactive,
}) {
  final pairs = <(MemberGroupEntry, Member)>[];
  for (final entry in entries) {
    final member = membersById[entry.memberId];
    if (member == null) continue;
    if (!showInactive && !member.isActive) continue;
    pairs.add((entry, member));
  }

  final sortState = group.sortState;
  switch (sortState.mode) {
    case GroupSortMode.manual:
      final position = <String, int>{};
      for (var i = 0; i < sortState.manualOrder.length; i++) {
        position.putIfAbsent(sortState.manualOrder[i], () => i);
      }
      final indexed = <(MemberGroupEntry, Member)>[];
      final unindexed = <(MemberGroupEntry, Member)>[];
      for (final pair in pairs) {
        if (position.containsKey(pair.$1.id)) {
          indexed.add(pair);
        } else {
          unindexed.add(pair);
        }
      }
      indexed.sort((a, b) => position[a.$1.id]!.compareTo(position[b.$1.id]!));
      unindexed.sort((a, b) => a.$1.id.compareTo(b.$1.id));
      return [...indexed, ...unindexed];

    case GroupSortMode.nameAsc:
      pairs.sort((a, b) {
        final cmp = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
        if (cmp != 0) return cmp;
        return a.$2.id.compareTo(b.$2.id);
      });
      return pairs;

    case GroupSortMode.nameDesc:
      pairs.sort((a, b) {
        final cmp = b.$2.name.toLowerCase().compareTo(a.$2.name.toLowerCase());
        if (cmp != 0) return cmp;
        return a.$2.id.compareTo(b.$2.id);
      });
      return pairs;

    case GroupSortMode.recentDesc:
      pairs.sort((a, b) {
        final cmp = b.$2.createdAt.compareTo(a.$2.createdAt);
        if (cmp != 0) return cmp;
        return a.$2.id.compareTo(b.$2.id);
      });
      return pairs;
  }
}

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

  /// 0 = root, then increases by 1 per nested level.
  final int depth;
  final bool isCollapsed;
}

class MemberRowItem extends GroupedMemberListItem {
  const MemberRowItem({
    required this.member,
    required this.depth,
    this.groupId,
  });

  final Member member;
  final String? groupId;

  /// Indent level matching the owning group's depth.
  final int depth;
}

class UngroupedSectionItem extends GroupedMemberListItem {
  const UngroupedSectionItem({required this.memberCount});

  final int memberCount;
}

int _compareMembersByDisplayOrder(Member a, Member b) {
  final order = a.displayOrder.compareTo(b.displayOrder);
  if (order != 0) return order;
  return a.id.compareTo(b.id);
}

/// Fully-expanded structural list (no collapse applied).
/// Rebuilds only when tree, entries, or members change — not on every toggle.
final _groupedMemberListStructureProvider = Provider<List<GroupedMemberListItem>>((
  ref,
) {
  final tree = ref.watch(groupTreeProvider);
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];
  // Member-management surface: hide the Unknown sentinel from the grouped list.
  final allMembers = ref.watch(userVisibleAllMemberListProvider).value ?? [];
  final showInactive = ref.watch(showInactiveMembersProvider);

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

  // Cycle guard mirroring the other walkers in group_tree_utils.dart: a cyclic
  // tree (e.g. a self-parent) would otherwise recurse forever and crash here.
  final visited = <String>{};
  void visitGroup(MemberGroup group, int depth) {
    if (!visited.add(group.id)) return;
    result.add(
      GroupSectionItem(group: group, depth: depth, isCollapsed: false),
    );
    for (final child in tree[group.id] ?? []) {
      visitGroup(child, depth + 1);
    }
    final directMembers = directMembersByGroup[group.id] ?? const <Member>[];
    final orderedDirectMembers = directMembers.length < 2
        ? directMembers
        : (List<Member>.from(directMembers)
            ..sort(_compareMembersByDisplayOrder));
    for (final member in orderedDirectMembers) {
      result.add(
        MemberRowItem(member: member, groupId: group.id, depth: depth),
      );
    }
  }

  for (final root in tree[null] ?? []) {
    visitGroup(root, 0);
  }

  final ungrouped =
      allMembers
          .where(
            (m) =>
                (showInactive || m.isActive) &&
                !groupedMemberIds.contains(m.id),
          )
          .toList()
        ..sort(_compareMembersByDisplayOrder);
  if (ungrouped.isNotEmpty) {
    result.add(UngroupedSectionItem(memberCount: ungrouped.length));
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
final groupedMemberListProvider = Provider<List<GroupedMemberListItem>>((ref) {
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
      result.add(
        GroupSectionItem(
          group: item.group,
          depth: item.depth,
          isCollapsed: isCollapsed,
        ),
      );
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
      await repo.reorderGroups(groups);
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

  Future<void> removeMemberFromGroup(String groupId, String memberId) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(memberGroupsRepositoryProvider);
      await repo.removeMemberFromGroup(groupId, memberId);
    });
  }
}

final groupNotifierProvider = AsyncNotifierProvider<GroupNotifier, void>(
  GroupNotifier.new,
);

/// Notifier for the active group filter selection.
/// null = show all, '__ungrouped__' = ungrouped members, any other value = group ID.
class ActiveGroupFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? filter) => state = filter;
}

final activeGroupFilterProvider =
    NotifierProvider.autoDispose<ActiveGroupFilterNotifier, String?>(
      ActiveGroupFilterNotifier.new,
    );

/// True when at least one active member has no group entry.
final ungroupedMembersExistProvider = Provider.autoDispose<bool>((ref) {
  // Member-management surface: ignore the Unknown sentinel — it should never
  // count as an "ungrouped member" needing UI affordance.
  final members = ref.watch(userVisibleAllMemberListProvider).value ?? [];
  final entries = ref.watch(allGroupEntriesProvider).value ?? [];
  final groupedMemberIds = entries.map((e) => e.memberId).toSet();
  return members.any((m) => m.isActive && !groupedMemberIds.contains(m.id));
});
