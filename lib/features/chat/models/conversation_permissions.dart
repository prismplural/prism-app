import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';

bool isDirectMessageConversation(Conversation conversation) {
  if (conversation.isDirectMessage) return true;

  final hasBlankTitle =
      conversation.title == null || conversation.title!.trim().isEmpty;
  return hasBlankTitle &&
      conversation.emoji == null &&
      conversation.categoryId == null &&
      conversation.participantIds.length == 2;
}

String? effectiveConversationOwnerId(Conversation conversation) =>
    conversation.creatorId ??
    (conversation.participantIds.isNotEmpty
        ? conversation.participantIds.first
        : null);

class ConversationPermissions {
  final Conversation conversation;
  final String? speakingAsMemberId;
  final Member? speakingAsMember;

  const ConversationPermissions({
    required this.conversation,
    required this.speakingAsMemberId,
    required this.speakingAsMember,
  });

  String? get _effectiveCreatorId => effectiveConversationOwnerId(conversation);

  bool get isParticipant {
    if (speakingAsMemberId == null) return false;
    if (conversation.participantIds.contains(speakingAsMemberId)) return true;
    // "Everyone" groups: any active, non-deleted member is implicitly a
    // participant. The flag short-circuits the explicit participantIds list
    // so adding/removing members doesn't fan out into thousands of sync ops.
    if (conversation.includesAllMembers && !isDirectMessage) {
      final member = speakingAsMember;
      if (member != null && member.isActive && !member.isDeleted) {
        return true;
      }
    }
    return false;
  }
  bool get isDirectMessage => isDirectMessageConversation(conversation);
  bool get isCreator =>
      speakingAsMemberId != null && speakingAsMemberId == _effectiveCreatorId;
  bool get isAdmin => speakingAsMember?.isAdmin ?? false;
  // A DM with no participants has nothing to gate on — gating visibility/write
  // on a participant list that doesn't exist locks everyone out forever. SP
  // imports produced this shape for channels that had no `members` field.
  bool get _isUnscopedDirectMessage =>
      isDirectMessage && conversation.participantIds.isEmpty;
  bool get _isOrphanedDirectMessage =>
      isDirectMessage && conversation.participantIds.length == 1;
  /// Admin viewing a group they aren't a member of. Admins get read +
  /// moderate access on these (delete messages/conversation, rename, add
  /// or remove members, transfer ownership) but cannot post or react —
  /// "see and moderate, don't speak". The override never applies to DMs:
  /// admins can only see DMs they're a participant of.
  bool get isAdminNonParticipantGroup =>
      !isDirectMessage && isAdmin && !isParticipant;
  bool get canView =>
      _isUnscopedDirectMessage || isParticipant || isAdminNonParticipantGroup;
  bool get canWrite =>
      _isUnscopedDirectMessage ||
      (isParticipant && !_isOrphanedDirectMessage);
  bool get canManage {
    // DMs never get admin override — moderating in someone else's DM is a
    // privacy hole even with moderation framing.
    if (isDirectMessage) {
      return canWrite && (isCreator || isAdmin);
    }
    return (isParticipant && (isCreator || isAdmin)) ||
        isAdminNonParticipantGroup;
  }

  bool get canEditTitleEmoji => isDirectMessage ? canWrite : canManage;
  // add/remove are no-ops on everyone-groups — toggle the flag off first.
  bool get canAddMembers =>
      !isDirectMessage && canManage && !conversation.includesAllMembers;
  bool get canRemoveMembers =>
      !isDirectMessage && canManage && !conversation.includesAllMembers;
  bool get canTransferOwnership => !isDirectMessage && canManage;
  bool get canDeleteConversation => isDirectMessage ? canView : canManage;
  bool get canLeave => !isDirectMessage && isParticipant;
  // Personal list-state — if you can see it, you can mute/archive/read it.
  bool get canArchive => canView;
  bool get canMute => canView;
  bool get canMarkRead => canView;
  bool get canSendMessages => canWrite;
  bool get canReact => canWrite;

  bool canEditMessage(String? authorId) =>
      canWrite && authorId == speakingAsMemberId;
  bool canDeleteMessage(String? authorId) =>
      (canWrite && authorId == speakingAsMemberId) || canManage;

  bool isMemberDeparted(String? memberId) =>
      memberId != null && !conversation.participantIds.contains(memberId);
}
