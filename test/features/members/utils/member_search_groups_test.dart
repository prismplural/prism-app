import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';

Member _member(String id) =>
    Member(id: id, name: id, createdAt: DateTime(2024));

MemberGroup _group(String id, {String? parentGroupId}) => MemberGroup(
  id: id,
  name: id,
  parentGroupId: parentGroupId,
  createdAt: DateTime(2024),
);

void main() {
  test('buildMemberSearchGroups includes direct and descendant members', () {
    final root = _group('root');
    final child = _group('child', parentGroupId: root.id);
    final grandchild = _group('grandchild', parentGroupId: child.id);
    final sibling = _group('sibling', parentGroupId: root.id);
    final groups = [root, child, grandchild, sibling];

    final result = buildMemberSearchGroups(
      members: [_member('root-member'), _member('leaf-member')],
      allGroups: groups,
      allEntries: const [
        MemberGroupEntry(
          id: 'entry-root',
          groupId: 'root',
          memberId: 'root-member',
        ),
        MemberGroupEntry(
          id: 'entry-leaf',
          groupId: 'grandchild',
          memberId: 'leaf-member',
        ),
        MemberGroupEntry(
          id: 'entry-filtered-out',
          groupId: 'sibling',
          memberId: 'not-a-candidate',
        ),
      ],
      groupTree: GroupTreeUtils.buildGroupTree(groups),
    );

    final idsByGroup = {for (final group in result) group.id: group.memberIds};

    expect(idsByGroup['root'], {'root-member', 'leaf-member'});
    expect(idsByGroup['child'], {'leaf-member'});
    expect(idsByGroup['grandchild'], {'leaf-member'});
    expect(idsByGroup, isNot(contains('sibling')));
  });
}
