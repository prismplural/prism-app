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

  bool get isParticipant =>
      speakingAsMemberId != null &&
      conversation.participantIds.contains(speakingAsMemberId);
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
  // Anonymous viewer (no speaking-as picked) can browse the group conversation
  // list metadata so the chat list isn't empty when no member is fronting.
  // Once a member is picked, the participant gate engages for groups too.
  // Scoped DMs stay hidden from anonymous viewers regardless.
  bool get _isAnonymousBrowsingGroup =>
      !isDirectMessage && speakingAsMemberId == null;
  bool get canView =>
      _isUnscopedDirectMessage || isParticipant || _isAnonymousBrowsingGroup;
  bool get canWrite =>
      _isUnscopedDirectMessage ||
      (isParticipant && !_isOrphanedDirectMessage);
  bool get canManage => canWrite && (isCreator || isAdmin);

  bool get canEditTitleEmoji => isDirectMessage ? canWrite : canManage;
  bool get canAddMembers => !isDirectMessage && canManage;
  bool get canRemoveMembers => !isDirectMessage && canManage;
  bool get canTransferOwnership => !isDirectMessage && canManage;
  bool get canDeleteConversation => isDirectMessage ? canView : canManage;
  bool get canLeave => !isDirectMessage && isParticipant;
  bool get canArchive => isDirectMessage ? canView : canWrite;
  bool get canMute => isDirectMessage ? canView : canWrite;
  bool get canMarkRead => isDirectMessage ? canView : canWrite;
  bool get canSendMessages => canWrite;
  bool get canReact => canWrite;

  bool canEditMessage(String? authorId) =>
      canWrite && authorId == speakingAsMemberId;
  bool canDeleteMessage(String? authorId) =>
      canWrite && (authorId == speakingAsMemberId || canManage);

  bool isMemberDeparted(String? memberId) =>
      memberId != null && !conversation.participantIds.contains(memberId);
}
