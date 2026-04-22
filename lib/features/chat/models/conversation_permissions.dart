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

class ConversationPermissions {
  final Conversation conversation;
  final String? speakingAsMemberId;
  final Member? speakingAsMember;

  const ConversationPermissions({
    required this.conversation,
    required this.speakingAsMemberId,
    required this.speakingAsMember,
  });

  String? get _effectiveCreatorId =>
      conversation.creatorId ??
      (conversation.participantIds.isNotEmpty
          ? conversation.participantIds.first
          : null);

  bool get isParticipant =>
      speakingAsMemberId != null &&
      conversation.participantIds.contains(speakingAsMemberId);
  bool get isDirectMessage => isDirectMessageConversation(conversation);
  bool get isCreator =>
      speakingAsMemberId != null && speakingAsMemberId == _effectiveCreatorId;
  bool get isAdmin => speakingAsMember?.isAdmin ?? false;
  bool get canView => !isDirectMessage || isParticipant || isAdmin;
  bool get canWrite => !isDirectMessage || isParticipant;
  bool get canManage => canWrite && (isCreator || isAdmin);

  bool get canEditTitleEmoji => isDirectMessage ? isParticipant : canManage;
  bool get canAddMembers => !isDirectMessage && canManage;
  bool get canRemoveMembers => !isDirectMessage && canManage;
  bool get canDeleteConversation => !isDirectMessage && canManage;
  bool get canLeave => !isDirectMessage && isParticipant;
  bool get canArchive => canWrite;
  bool get canMute => canWrite;
  bool get canMarkRead => canWrite;
  bool get canSendMessages => canWrite;
  bool get canReact => canWrite;

  bool canEditMessage(String? authorId) =>
      canWrite && authorId == speakingAsMemberId;
  bool canDeleteMessage(String? authorId) =>
      canWrite && (authorId == speakingAsMemberId || canManage);

  bool isMemberDeparted(String? memberId) =>
      memberId != null && !conversation.participantIds.contains(memberId);
}
