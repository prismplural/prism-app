import 'package:flutter/widgets.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
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
