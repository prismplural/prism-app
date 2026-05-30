import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/manage_groups_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/group_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Groups section shown on the member detail screen.
///
/// Mirrors the visual structure of [NotesSection]: a labelled section header
/// with an inline `+` button that opens [ManageGroupsSheet], and a body that
/// shows the member's current groups as chips (or an empty-state surface).
class MemberGroupsSection extends ConsumerWidget {
  const MemberGroupsSection({
    super.key,
    required this.memberId,
    required this.memberName,
    this.branch = MemberNavigationBranch.settings,
  });

  final String memberId;
  final String memberName;
  final MemberNavigationBranch branch;

  String _groupPath(String id) => branch.groupPath(id);

  void _openManageGroupsSheet(BuildContext context) {
    ManageGroupsSheet.show(
      context,
      memberId: memberId,
      memberName: memberName,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final groupsAsync = ref.watch(memberGroupsProvider(memberId));

    return groupsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (groups) {
        final flatList = ref.watch(flatGroupListProvider);
        final order = <String, int>{
          for (var i = 0; i < flatList.length; i++) flatList[i].group.id: i,
        };
        final sortedGroups = [...groups]
          ..sort((a, b) {
            final ai = order[a.id] ?? 1 << 30;
            final bi = order[b.id] ?? 1 << 30;
            return ai.compareTo(bi);
          });

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.groupOutlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.memberGroupManageTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  PrismInlineIconButton(
                    icon: AppIcons.add,
                    iconSize: 20,
                    color: theme.colorScheme.primary,
                    onPressed: () => _openManageGroupsSheet(context),
                    tooltip: l10n.memberGroupAddToGroup,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (groups.isEmpty)
                SizedBox(
                  width: double.infinity,
                  child: PrismSurface(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        l10n.memberGroupManageNoGroups,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: PrismSurface(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final group in sortedGroups)
                          PrismChip(
                            label: group.name,
                            selected: false,
                            avatar: GroupAvatar(
                              group: group,
                              size: 20,
                              showEmojiOnAvatar: false,
                            ),
                            tintColor:
                                group.colorHex != null &&
                                    group.colorHex!.isNotEmpty
                                ? AppColors.fromHex(group.colorHex!)
                                : null,
                            onTap: () => context.push(_groupPath(group.id)),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
