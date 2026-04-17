import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/manage_groups_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

/// Inline widget showing small colored chips for each group a member belongs to,
/// plus a `+` chip to open [ManageGroupsSheet].
///
/// Watches [memberGroupsProvider] for the given [memberId] and renders a
/// [Wrap] of tappable chips. Each chip shows the group emoji (if any) and name.
/// Tapping navigates to the group detail screen.
///
/// Always renders (even with no groups) so the user can add the member to a group.
class MemberGroupChips extends ConsumerWidget {
  const MemberGroupChips({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  void _openManageGroupsSheet(BuildContext context, WidgetRef ref) {
    PrismSheet.show(
      context: context,
      builder: (_) => ManageGroupsSheet(
        memberId: memberId,
        memberName: memberName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupsAsync = ref.watch(memberGroupsProvider(memberId));

    return groupsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (groups) {
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...groups.map((group) {
              final accentColor = group.colorHex != null &&
                      group.colorHex!.isNotEmpty
                  ? AppColors.fromHex(group.colorHex!)
                  : null;
              return PrismChip(
                label: group.name,
                selected: false,
                onTap: () => context.push(AppRoutePaths.settingsGroup(group.id)),
                avatar: group.emoji != null && group.emoji!.isNotEmpty
                    ? Text(group.emoji!, style: const TextStyle(fontSize: 12))
                    : null,
                tintColor: accentColor,
              );
            }),
            Semantics(
              label: l10n.memberGroupAddToGroupSemantics(memberName),
              excludeSemantics: true,
              child: Tooltip(
                message: l10n.memberGroupAddToGroup,
                child: PrismChip(
                  label: '+',
                  selected: false,
                  onTap: () => _openManageGroupsSheet(context, ref),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

