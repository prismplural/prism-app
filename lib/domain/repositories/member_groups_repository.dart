import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart' as domain;

abstract class MemberGroupsRepository {
  Stream<List<domain.MemberGroup>> watchAllGroups();
  Stream<domain.MemberGroup?> watchGroupById(String id);
  Stream<List<domain.MemberGroup>> watchGroupsForMember(String memberId);
  Stream<List<domain.MemberGroupEntry>> watchGroupEntries(String groupId);
  Stream<List<domain.MemberGroupEntry>> watchAllGroupEntries();
  Future<List<domain.MemberGroupEntry>> getAllGroupEntries();
  Stream<Map<String, int>> watchMemberCountsByGroup();
  Future<void> createGroup(domain.MemberGroup group);
  Future<void> updateGroup(domain.MemberGroup group);
  Future<void> deleteGroup(String groupId);

  /// Promotes all direct children to root level, then deletes [groupId].
  Future<void> promoteChildrenToRoot(String groupId);

  /// Soft-deletes [groupId] and all descendant groups (and their entries).
  Future<void> deleteGroupWithDescendants(String groupId);

  Future<void> addMemberToGroup(
      String groupId, String memberId, String entryId);
  Future<void> removeMemberFromGroup(String groupId, String memberId);

  /// Re-emits sync ops for the current state of [groupId] and all of its
  /// active entries, even if the row is currently marked sync-suppressed or
  /// was recently dismissed from PK review. Used by repair/dismissal flows to
  /// push accumulated local edits to peers after the suppression window.
  Future<void> emitGroupSyncState(String groupId);
}
