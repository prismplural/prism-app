import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/widgets/member_group_picker_list.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

/// Full-screen sheet for selecting a parent group.
///
/// Lists all groups that can legally be assigned as the parent of the group
/// being created or edited, filtering out:
/// - The group itself (can't be its own parent)
/// - Any descendant of the group (cycle prevention)
///
/// Always includes a "None (top level)" option at the top.
class GroupParentPicker extends ConsumerWidget {
  const GroupParentPicker({
    super.key,
    required this.excludeGroupId,
    required this.currentParentId,
    required this.onSelected,
    this.scrollController,
  });

  /// The ID of the group being edited, or null when creating a new group.
  /// This group and all its descendants are excluded from the list.
  final String? excludeGroupId;

  /// The currently selected parent group ID, or null for root level.
  final String? currentParentId;

  /// Called when the user taps a group (or the "None" option).
  /// Receives null to indicate root / no parent.
  final void Function(String? groupId) onSelected;

  /// Scroll controller supplied by [PrismSheet.showFullScreen].
  final ScrollController? scrollController;

  static Future<void> show({
    required BuildContext context,
    required String? excludeGroupId,
    required String? currentParentId,
    required void Function(String? groupId) onSelected,
  }) {
    return PrismSheet.showFullScreen<void>(
      context: context,
      builder: (sheetContext, scrollController) => GroupParentPicker(
        excludeGroupId: excludeGroupId,
        currentParentId: currentParentId,
        onSelected: onSelected,
        scrollController: scrollController,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allGroupsAsync = ref.watch(allGroupsProvider);
    final tree = ref.watch(groupTreeProvider);

    return allGroupsAsync.when(
      loading: () => Column(
        children: [
          PrismSheetTopBar(title: l10n.memberGroupParentLabel),
          const Expanded(child: PrismLoadingState()),
        ],
      ),
      error: (e, _) => Column(
        children: [
          PrismSheetTopBar(title: l10n.memberGroupParentLabel),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.error),
              ),
            ),
          ),
        ],
      ),
      data: (_) {
        bool includeGroup(String groupId) {
          if (excludeGroupId != null && groupId == excludeGroupId) return false;
          if (excludeGroupId == null) return true;
          return !GroupTreeUtils.wouldCreateCycle(
            excludeGroupId!,
            groupId,
            tree,
          );
        }

        final body = MemberGroupPickerList(
          scrollController: scrollController,
          selectedGroupIds: {?currentParentId},
          showMemberCounts: false,
          includeGroup: (group) => includeGroup(group.id),
          semanticLabelBuilder: (group, depth, isSelected) {
            final depthLabel = depth == 0 ? 'top level group' : 'nested group';
            return '${group.name}, $depthLabel${isSelected ? ', selected' : ''}';
          },
          leadingRows: [_buildNoneTile(context), const Divider(height: 1)],
          onGroupTap: (group) {
            onSelected(group.id);
            Navigator.of(context).pop();
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrismSheetTopBar(title: l10n.memberGroupParentLabel),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildNoneTile(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return PrismListRow(
      leading: Icon(
        AppIcons.folderOutlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(l10n.memberGroupParentNone),
      trailing: currentParentId == null
          ? Icon(AppIcons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () {
        onSelected(null);
        Navigator.of(context).pop();
      },
    );
  }
}
