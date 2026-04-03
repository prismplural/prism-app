import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// A compact bottom sheet for selecting a member (headmate).
///
/// Returns the selected member's ID, or an empty string `''` to indicate
/// "none" (clear the current selection). Returns `null` if dismissed.
class MemberSelectSheet extends ConsumerWidget {
  const MemberSelectSheet({
    super.key,
    this.currentMemberId,
  });

  final String? currentMemberId;

  /// Show the member selection sheet and return the chosen member ID.
  ///
  /// Returns `''` if the user chose "None", the member ID if a member was
  /// tapped, or `null` if the sheet was dismissed without selection.
  static Future<String?> show(
    BuildContext context, {
    String? currentMemberId,
  }) {
    return PrismSheet.show<String>(
      context: context,
      title: 'Choose Headmate',
      builder: (_) => MemberSelectSheet(currentMemberId: currentMemberId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(activeMembersProvider);
    final terminology = ref.watch(terminologyProvider);

    return membersAsync.when(
      loading: () => const PrismLoadingState(),
      error: (_, _) => Center(
        child: Text('Failed to load ${terminology.pluralLower}'),
      ),
      data: (members) => ListView.builder(
        shrinkWrap: true,
        itemCount: members.length + 1,
        itemBuilder: (context, index) {
          // "None" option at the top.
          if (index == 0) {
            return ListTile(
              leading: SizedBox(
                width: 36,
                height: 36,
                child: Icon(AppIcons.close),
              ),
              title: const Text('None'),
              trailing: currentMemberId == null || currentMemberId!.isEmpty
                  ? Icon(AppIcons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(''),
            );
          }

          final member = members[index - 1];
          final isSelected = member.id == currentMemberId;

          return ListTile(
            leading: MemberAvatar(
              avatarImageData: member.avatarImageData,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 36,
            ),
            title: Text(member.name),
            subtitle:
                member.pronouns != null ? Text(member.pronouns!) : null,
            trailing: isSelected ? Icon(AppIcons.check) : null,
            onTap: () => Navigator.of(context).pop(member.id),
          );
        },
      ),
    );
  }
}
