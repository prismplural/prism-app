import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';

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
      (conversation.participantIds.isNotEmpty ? conversation.participantIds.first : null);

  bool get isCreator => speakingAsMemberId != null && speakingAsMemberId == _effectiveCreatorId;
  bool get isAdmin => speakingAsMember?.isAdmin ?? false;
  bool get canManage => isCreator || isAdmin;

  bool get canEditTitleEmoji => conversation.isDirectMessage || canManage;
  bool get canAddMembers => !conversation.isDirectMessage && canManage;
  bool get canRemoveMembers => !conversation.isDirectMessage && canManage;
  bool get canDeleteConversation => !conversation.isDirectMessage && canManage;
  bool get canLeave => !conversation.isDirectMessage;
  bool get canArchive => true;

  bool canEditMessage(String? authorId) => authorId == speakingAsMemberId;
  bool canDeleteMessage(String? authorId) => authorId == speakingAsMemberId || canManage;

  bool isMemberDeparted(String? memberId) =>
      memberId != null && !conversation.participantIds.contains(memberId);
}
