import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';

bool canMentionMember(Member? member) {
  return member != null &&
      member.id != unknownSentinelMemberId &&
      member.isActive &&
      !member.isDeleted;
}

bool canMentionGroup(MemberGroup? group, Set<String> visibleGroupIds) {
  return group != null && visibleGroupIds.contains(group.id);
}

bool canMentionNote(Note? note, {required bool notesEnabled}) {
  return notesEnabled && note != null;
}

bool canActiveFrontViewBoardPost(
  MemberBoardPost? post, {
  required Iterable<Member> activeFronters,
}) {
  if (post == null || post.isDeleted) return false;
  if (post.audience == 'public') return true;
  if (post.audience != 'private') return false;

  for (final member in activeFronters) {
    if (!canMentionMember(member)) continue;
    if (post.targetMemberId == member.id || post.authorId == member.id) {
      return true;
    }
  }
  return false;
}

bool canActiveFrontViewConversation(
  Conversation? conversation, {
  required Iterable<Member> activeFronters,
}) {
  if (conversation == null) return false;
  return activeFrontersWhoCanViewConversation(
    conversation,
    activeFronters: activeFronters,
  ).isNotEmpty;
}

List<Member> activeFrontersWhoCanViewConversation(
  Conversation conversation, {
  required Iterable<Member> activeFronters,
}) {
  return [
    for (final member in activeFronters)
      if (_canMemberViewConversation(conversation, member)) member,
  ];
}

List<Member> currentActiveFronters({
  required Iterable<FrontingSession> activeSessions,
  required Iterable<Member> activeMembers,
}) {
  final activeMembersById = {
    for (final member in activeMembers)
      if (canMentionMember(member)) member.id: member,
  };
  final seen = <String>{};
  final fronters = <Member>[];
  for (final session in activeSessions) {
    final id = session.memberId;
    if (id == null ||
        session.endTime != null ||
        session.isSleep ||
        !seen.add(id)) {
      continue;
    }
    final member = activeMembersById[id];
    if (member != null) fronters.add(member);
  }
  return fronters;
}

bool _canMemberViewConversation(Conversation conversation, Member member) {
  if (!canMentionMember(member)) return false;
  final permissions = ConversationPermissions(
    conversation: conversation,
    speakingAsMemberId: member.id,
    speakingAsMember: member,
  );
  return permissions.canView;
}
