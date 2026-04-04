import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Shows a dialog to select a new conversation owner.
///
/// If there is only one remaining member, returns their ID directly without
/// showing the picker.
///
/// Returns the selected member's ID, or null if the picker is dismissed.
Future<String?> showCreatorTransferPicker(
  BuildContext context, {
  required List<Member> remainingMembers,
}) async {
  // If only one member remains, return their ID directly
  if (remainingMembers.length == 1) {
    return remainingMembers.first.id;
  }

  return PrismDialog.show<String>(
    context: context,
    title: 'Select new conversation owner',
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: remainingMembers
            .map((member) => PrismListRow(
                  padding: EdgeInsets.zero,
                  leading: MemberAvatar(
                    avatarImageData: member.avatarImageData,
                    emoji: member.emoji,
                    customColorEnabled: member.customColorEnabled,
                    customColorHex: member.customColorHex,
                    size: 40,
                  ),
                  title: Text(member.name),
                  subtitle: member.pronouns != null
                      ? Text(member.pronouns!)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(member.id),
                ))
            .toList(),
      );
    },
  );
}
