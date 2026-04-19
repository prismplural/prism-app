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

  final counts = <String, int>{};
  for (final group in allGroups) {
    final descendantGroupIds =
        GroupTreeUtils.getDescendantGroupIds(group.id, tree);
    counts[group.id] = allEntries
        .where((e) =>
            e.groupId == group.id || descendantGroupIds.contains(e.groupId))
        .map((e) => e.memberId)
        .toSet()
        .length;
  }
  return counts;
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

/// Flat ordered list driving the members tab grouped list.
///
/// Order: DFS group traversal (header → sub-group sections → direct members),
/// followed by an ungrouped section when ungrouped active members exist.
final groupedMemberListProvider =
    Provider<List<GroupedMemberListItem>>((ref) {
  final tree = ref.watch(groupTreeProvider);
  final allEntries = ref.watch(allGroupEntriesProvider).value ?? [];
  final allMembers = ref.watch(allMembersProvider).value ?? [];
  final collapsed = ref.watch(collapsedGroupsProvider);

  final memberById = {for (final m in allMembers) m.id: m};

  // Map each group to its direct active members.
  final directMembersByGroup = <String, List<Member>>{};
  for (final entry in allEntries) {
    final member = memberById[entry.memberId];
    if (member != null && member.isActive) {
      directMembersByGroup.putIfAbsent(entry.groupId, () => []).add(member);
    }
  }

  final result = <GroupedMemberListItem>[];

  void visitGroup(MemberGroup group, int depth) {
    final isCollapsed = collapsed.contains(group.id);
    result.add(GroupSectionItem(
        group: group, depth: depth, isCollapsed: isCollapsed));
    if (isCollapsed) return;

    // Sub-group sections before direct members.
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

  // Ungrouped section — members with no group entry at all.
  final groupedMemberIds = allEntries.map((e) => e.memberId).toSet();
  final ungrouped = allMembers
      .where((m) => m.isActive && !groupedMemberIds.contains(m.id))
      .toList();
  if (ungrouped.isNotEmpty) {
    result.add(const UngroupedSectionItem());
    for (final m in ungrouped) {
      result.add(MemberRowItem(member: m, depth: 0));
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
