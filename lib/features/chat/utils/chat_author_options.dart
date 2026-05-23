import 'package:flutter/widgets.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

bool isUnknownChatAuthor(String? memberId) =>
    memberId == unknownSentinelMemberId;

Member unknownChatAuthorMember(BuildContext context) => Member(
  id: unknownSentinelMemberId,
  name: context.l10n.unknown,
  emoji: '\u2754',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  isActive: true,
);

List<Member> withUnknownChatAuthorOption(
  BuildContext context,
  List<Member> members,
) {
  final existingUnknown = members
      .where((member) => member.id == unknownSentinelMemberId)
      .firstOrNull;
  return [
    existingUnknown ?? unknownChatAuthorMember(context),
    ...members.where((member) => member.id != unknownSentinelMemberId),
  ];
}

Member? findChatAuthorOption(
  BuildContext context,
  List<Member> members,
  String? memberId,
) {
  if (memberId == null) return null;
  for (final member in members) {
    if (member.id == memberId) return member;
  }
  if (memberId == unknownSentinelMemberId) {
    return unknownChatAuthorMember(context);
  }
  return null;
}

/// Pure (no l10n) variant of [chatAuthorCandidates]. Use from notifiers and
/// write-path validation. Returns the same id set the list version would.
Set<String> chatAuthorCandidateIds(
  Conversation conversation,
  List<Member> activeMembers, {
  String? currentAuthorId,
  Member? currentAuthor,
}) {
  final body = _buildCandidateMembers(
    conversation,
    activeMembers,
    currentAuthorId: currentAuthorId,
    currentAuthor: currentAuthor,
  );
  final ids = body.map((m) => m.id).toSet();

  final bool addUnknown;
  if (isDirectMessageConversation(conversation) &&
      conversation.participantIds.isNotEmpty) {
    addUnknown =
        conversation.participantIds.contains(unknownSentinelMemberId);
  } else {
    addUnknown = true;
  }
  if (addUnknown) ids.add(unknownSentinelMemberId);
  return ids;
}

/// Ordered author candidates for [conversation]. The Unknown sentinel is the
/// last entry. The member matching [currentAuthorId] is pinned to index 0;
/// supply [currentAuthor] when the current author is no longer in
/// [activeMembers] (departed/deleted).
///
/// DMs with a non-empty [Conversation.participantIds] are restricted to those
/// participants and exclude Unknown unless the sentinel id is listed.
List<Member> chatAuthorCandidates(
  Conversation conversation,
  List<Member> activeMembers,
  AppLocalizations l10n, {
  String? currentAuthorId,
  Member? currentAuthor,
}) {
  final body = _buildCandidateMembers(
    conversation,
    activeMembers,
    currentAuthorId: currentAuthorId,
    currentAuthor: currentAuthor,
  );

  final bool addUnknown;
  if (isDirectMessageConversation(conversation) &&
      conversation.participantIds.isNotEmpty) {
    addUnknown =
        conversation.participantIds.contains(unknownSentinelMemberId);
  } else {
    addUnknown = true;
  }

  final unknown = Member(
    id: unknownSentinelMemberId,
    name: l10n.unknown,
    emoji: '❔',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isActive: true,
  );

  return [
    ...body.where((m) => m.id != unknownSentinelMemberId),
    if (addUnknown) unknown,
  ];
}

/// Shared ordered candidate list (without the Unknown sentinel). Callers may
/// pass an [activeMembers] list that contains the sentinel row — it is
/// filtered out here.
List<Member> _buildCandidateMembers(
  Conversation conversation,
  List<Member> activeMembers, {
  String? currentAuthorId,
  Member? currentAuthor,
}) {
  final visible = activeMembers
      .where((m) => m.id != unknownSentinelMemberId)
      .toList(growable: false);

  final List<Member> pool;
  if (isDirectMessageConversation(conversation) &&
      conversation.participantIds.isNotEmpty) {
    final participantSet = conversation.participantIds
        .where((id) => id != unknownSentinelMemberId)
        .toSet();
    pool = visible
        .where((m) => participantSet.contains(m.id))
        .toList(growable: false);
  } else {
    pool = visible;
  }

  if (currentAuthorId == null) return pool;

  final current =
      pool.where((m) => m.id == currentAuthorId).firstOrNull ??
      (currentAuthor?.id == currentAuthorId ? currentAuthor : null);

  if (current == null) return pool;

  return [
    current,
    ...pool.where((m) => m.id != currentAuthorId),
  ];
}
