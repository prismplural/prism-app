import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart' as domain;

abstract class MemberGroupsRepository {
  Stream<List<domain.MemberGroup>> watchAllGroups();
  Stream<domain.MemberGroup?> watchGroupById(String id);
  Stream<List<domain.MemberGroup>> watchGroupsForMember(String memberId);
  Stream<List<domain.MemberGroupEntry>> watchGroupEntries(String groupId);
  Stream<Map<String, int>> watchMemberCountsByGroup();
  Future<void> createGroup(domain.MemberGroup group);
  Future<void> updateGroup(domain.MemberGroup group);
  Future<void> deleteGroup(String groupId);
  Future<void> addMemberToGroup(
      String groupId, String memberId, String entryId);
  Future<void> removeMemberFromGroup(String groupId, String memberId);
}
