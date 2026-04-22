import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

/// Shows a sheet to select a new conversation owner.
///
/// If there is only one remaining member, returns their ID directly without
/// showing the picker.
///
/// Returns the selected member's ID, or null if the picker is dismissed.
Future<String?> showCreatorTransferPicker(
  BuildContext context, {
  required List<Member> remainingMembers,
}) async {
  // Fast path: skip UI entirely when only one candidate exists.
  if (remainingMembers.length == 1) {
    return remainingMembers.first.id;
  }

  final result = await MemberSearchSheet.showSingle(
    context,
    members: remainingMembers,
    termPlural: 'members',
  );

  return switch (result) {
    MemberSearchResultSelected(:final memberId) => memberId,
    _ => null,
  };
}
