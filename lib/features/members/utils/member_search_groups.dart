import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

/// Watches group data and builds caller-owned filter chips for the provided
/// member candidates.
List<MemberSearchGroup> watchMemberSearchGroups(
  WidgetRef ref,
  Iterable<Member> members,
) {
  final groups = ref.watch(allGroupsProvider).value ?? const <MemberGroup>[];
  final entries =
      ref.watch(allGroupEntriesProvider).value ?? const <MemberGroupEntry>[];
  final tree = ref.watch(groupTreeProvider);
  return buildMemberSearchGroups(
    members: members,
    allGroups: groups,
    allEntries: entries,
    groupTree: tree,
  );
}

/// Keeps the group streams warm without building candidate-specific filters.
void watchMemberSearchGroupSources(WidgetRef ref) {
  ref.watch(allGroupsProvider);
  ref.watch(allGroupEntriesProvider);
  ref.watch(groupTreeProvider);
}

/// Reads the latest group data and builds filter chips for the provided member
/// candidates.
List<MemberSearchGroup> readMemberSearchGroups(
  WidgetRef ref,
  Iterable<Member> members,
) {
  final groups = ref.read(allGroupsProvider).value ?? const <MemberGroup>[];
  final entries =
      ref.read(allGroupEntriesProvider).value ?? const <MemberGroupEntry>[];
  final tree = ref.read(groupTreeProvider);
  return buildMemberSearchGroups(
    members: members,
    allGroups: groups,
    allEntries: entries,
    groupTree: tree,
  );
}

/// Builds [MemberSearchGroup] chips for the provided candidates.
///
/// Membership is transitive: a group chip includes members assigned directly to
/// that group plus members assigned to any descendant group.
List<MemberSearchGroup> buildMemberSearchGroups({
  required Iterable<Member> members,
  required List<MemberGroup> allGroups,
  required List<MemberGroupEntry> allEntries,
  required Map<String?, List<MemberGroup>> groupTree,
}) {
  final candidateIds = members.map((member) => member.id).toSet();
  if (candidateIds.isEmpty || allGroups.isEmpty) return const [];

  final directMemberIdsByGroup = <String, Set<String>>{};
  for (final entry in allEntries) {
    if (!candidateIds.contains(entry.memberId)) continue;
    directMemberIdsByGroup
        .putIfAbsent(entry.groupId, () => <String>{})
        .add(entry.memberId);
  }

  final transitiveIdsByGroup = _transitiveMemberIdsByGroup(
    allGroups,
    groupTree,
    directMemberIdsByGroup,
  );

  final searchGroups = <MemberSearchGroup>[];
  for (final group in allGroups) {
    final memberIds = transitiveIdsByGroup[group.id];
    if (memberIds == null || memberIds.isEmpty) continue;
    searchGroups.add(
      MemberSearchGroup(
        id: group.id,
        name: group.name,
        memberIds: memberIds,
        emoji: group.emoji,
        colorHex: group.colorHex,
      ),
    );
  }
  return searchGroups;
}

Map<String, Set<String>> _transitiveMemberIdsByGroup(
  List<MemberGroup> allGroups,
  Map<String?, List<MemberGroup>> groupTree,
  Map<String, Set<String>> directMemberIdsByGroup,
) {
  final transitiveIdsByGroup = <String, Set<String>>{};
  final visited = <String>{};
  final stack = <(MemberGroup group, bool expanded)>[];

  final roots = groupTree[null] ?? const <MemberGroup>[];
  for (var i = roots.length - 1; i >= 0; i--) {
    stack.add((roots[i], false));
  }

  while (stack.isNotEmpty) {
    final (group, expanded) = stack.removeLast();
    if (!expanded) {
      if (!visited.add(group.id)) continue;
      stack.add((group, true));
      final children = groupTree[group.id] ?? const <MemberGroup>[];
      for (var i = children.length - 1; i >= 0; i--) {
        stack.add((children[i], false));
      }
      continue;
    }

    final memberIds = <String>{...?directMemberIdsByGroup[group.id]};
    for (final child in groupTree[group.id] ?? const <MemberGroup>[]) {
      memberIds.addAll(transitiveIdsByGroup[child.id] ?? const <String>{});
    }
    transitiveIdsByGroup[group.id] = memberIds;
  }

  for (final group in allGroups) {
    transitiveIdsByGroup.putIfAbsent(
      group.id,
      () => directMemberIdsByGroup[group.id] ?? const <String>{},
    );
  }

  return transitiveIdsByGroup;
}
