import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// A compact bottom sheet for selecting a member (headmate).
///
/// Returns the selected member's ID, or an empty string `''` to indicate
/// "none" (clear the current selection). Returns `null` if dismissed.
class MemberSelectSheet extends ConsumerWidget {
  const MemberSelectSheet({
    super.key,
    this.currentMemberId,
  });

  static const double _kSheetBodyHeightFactor = 0.45;

  final String? currentMemberId;

  /// Show the member selection sheet and return the chosen member ID.
  ///
  /// Returns `''` if the user chose "None", the member ID if a member was
  /// tapped, or `null` if the sheet was dismissed without selection.
  ///
  /// The sheet opens with a fixed-height scrolling body so longer lists stay
  /// scrollable without becoming full-screen.
  static Future<String?> show(
    BuildContext context, {
    String? currentMemberId,
  }) {
    return PrismSheet.show<String>(
      context: context,
      title: context.l10n.memberNoteChooseHeadmate,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * _kSheetBodyHeightFactor,
        child: MemberSelectSheet(currentMemberId: currentMemberId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(activeMembersProvider);
    final terminology = watchTerminology(context, ref);
    final l10n = context.l10n;

    return membersAsync.when(
      loading: () => const PrismLoadingState(),
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Failed to load ${terminology.pluralLower}'),
        ),
      ),
      data: (members) {
        if (members.isEmpty) {
          return EmptyState(
            icon: Icon(AppIcons.people),
            title: l10n.noMembersFound(terminology.pluralLower),
            subtitle: l10n.terminologyAddFirstSubtitle(
              terminology.singularLower,
            ),
          );
        }

        // "None" row + one row per member — no shrinkWrap; height is bounded
        // by the explicit body height in show().
        return PrismSectionCard(
          padding: EdgeInsets.zero,
          child: ListView.builder(
            itemCount: members.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final noneSelected =
                    currentMemberId == null || currentMemberId!.isEmpty;
                return PrismListRow(
                  selected: noneSelected,
                  leading: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(AppIcons.removeCircleOutline),
                  ),
                  title: Text(l10n.memberSelectNone),
                  trailing: noneSelected ? Icon(AppIcons.check) : null,
                  onTap: () => Navigator.of(context).pop(''),
                );
              }

              final member = members[index - 1];
              final isSelected = member.id == currentMemberId;

              return PrismListRow(
                selected: isSelected,
                leading: MemberAvatar(
                  avatarImageData: member.avatarImageData,
                  memberName: member.name,
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
      },
    );
  }
}
