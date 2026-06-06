import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
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

bool conversationIncludesImplicitMembers(Conversation conversation) =>
    conversation.includesAllMembers &&
    !isDirectMessageConversation(conversation);

bool isConversationParticipant(
  Conversation conversation,
  String memberId, {
  Member? member,
  bool requireKnownImplicitMember = false,
}) {
  if (conversation.participantIds.contains(memberId)) return true;
  if (!conversationIncludesImplicitMembers(conversation)) return false;
  if (memberId == unknownSentinelMemberId) return true;
  if (requireKnownImplicitMember && member == null) return false;
  if (member == null) return true;
  // Passed member rows must describe the member being checked.
  return member.id == memberId && member.isActive && !member.isDeleted;
}

Set<String> broadcastMentionRecipientIds({
  required Conversation conversation,
  required Iterable<Member> activeMembers,
  required String authorId,
}) {
  final ids = conversation.participantIds.toSet();
  if (conversationIncludesImplicitMembers(conversation)) {
    ids.addAll(
      activeMembers
          .where((member) => member.isActive && !member.isDeleted)
          .map((member) => member.id),
    );
  }
  ids
    ..remove(unknownSentinelMemberId)
    ..remove(authorId);
  return ids;
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

  String? get _effectiveCreatorId => effectiveConversationOwnerId(conversation);

  bool get isParticipant {
    if (speakingAsMemberId == null) return false;
    return isConversationParticipant(
      conversation,
      speakingAsMemberId!,
      member: speakingAsMember,
      requireKnownImplicitMember: true,
    );
  }

  bool get isDirectMessage => isDirectMessageConversation(conversation);
  bool get isCreator =>
      speakingAsMemberId != null && speakingAsMemberId == _effectiveCreatorId;
  bool get isAdmin => speakingAsMember?.isAdmin ?? false;
  // A DM with no participants has nothing to gate on — gating visibility/write
  // on a participant list that doesn't exist locks everyone out forever. SP
  // imports produced this shape for channels that had no `members` field.
  // Still requires a real, active, non-deleted speakingAsMember: the Unknown
  // sentinel and the null case both fall through to the "pick a member"
  // banner instead of leaking legacy DM content.
  bool get _isUnscopedDirectMessage {
    if (!isDirectMessage || conversation.participantIds.isNotEmpty) {
      return false;
    }
    final id = speakingAsMemberId;
    final member = speakingAsMember;
    return id != null &&
        id != unknownSentinelMemberId &&
        member != null &&
        member.isActive &&
        !member.isDeleted;
  }

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
      _isUnscopedDirectMessage || (isParticipant && !_isOrphanedDirectMessage);
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
  // Implicit "everyone group" members aren't in participantIds, so leaving is
  // a no-op for them — only show Leave when there's an explicit row to remove.
  bool get canLeave =>
      !isDirectMessage &&
      speakingAsMemberId != null &&
      conversation.participantIds.contains(speakingAsMemberId);
  // Personal list-state — if you can see it, you can mute/archive/read it.
  bool get canArchive => canView;
  // System-wide archive is a moderation action: admins/creators only (canManage),
  // and never on DMs. Per-member archive (canArchive) stays open to all members.
  bool get canArchiveForEveryone => !isDirectMessage && canManage;
  bool get canUnarchiveForEveryone => canArchiveForEveryone;
  bool get canMute => canView;
  bool get canMarkRead => canView;
  bool get canSendMessages => canWrite;
  bool get canReact => canWrite;

  bool canEditMessage(String? authorId) =>
      canWrite && authorId == speakingAsMemberId;
  bool canDeleteMessage(String? authorId) =>
      (canWrite && authorId == speakingAsMemberId) || canManage;

  /// Re-attribute a message. System messages (null authorId) are never eligible.
  bool canChangeMessageAuthor(String? authorId) =>
      (canWrite && authorId != null) || canManage;

  bool isMemberDeparted(String? memberId, {Member? member}) {
    if (memberId == null) return false;
    if (conversation.participantIds.contains(memberId)) return false;
    if (!conversationIncludesImplicitMembers(conversation)) return true;
    if (memberId == unknownSentinelMemberId) return false;
    if (member == null) return true;
    return member.id != memberId || !member.isActive || member.isDeleted;
  }
}
