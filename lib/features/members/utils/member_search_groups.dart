import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
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

  final transitiveIdsByGroup = <String, Set<String>>{};

  Set<String> memberIdsForGroup(String groupId) {
    return transitiveIdsByGroup.putIfAbsent(groupId, () {
      final memberIds = <String>{...?directMemberIdsByGroup[groupId]};
      for (final descendantId in GroupTreeUtils.getDescendantGroupIds(
        groupId,
        groupTree,
      )) {
        memberIds.addAll(directMemberIdsByGroup[descendantId] ?? const {});
      }
      return memberIds;
    });
  }

  return [
    for (final group in allGroups)
      if (memberIdsForGroup(group.id) case final memberIds
          when memberIds.isNotEmpty)
        MemberSearchGroup(
          id: group.id,
          name: group.name,
          memberIds: memberIds,
          emoji: group.emoji,
          colorHex: group.colorHex,
        ),
  ];
}
