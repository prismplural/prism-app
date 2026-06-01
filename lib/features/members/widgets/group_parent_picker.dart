import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
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
      data: (allGroups) {
        final candidates = <_GroupPickerItem>[];
        final depthsAll = GroupTreeUtils.getGroupDepthsAll(tree);

        for (final group in allGroups) {
          if (excludeGroupId != null && group.id == excludeGroupId) continue;

          if (excludeGroupId != null &&
              GroupTreeUtils.wouldCreateCycle(
                excludeGroupId!,
                group.id,
                tree,
              )) {
            continue;
          }

          final depth = depthsAll[group.id] ?? 1;
          candidates.add(_GroupPickerItem(group: group, depth: depth));
        }

        final body = CustomScrollView(
          controller: scrollController,
          primary: scrollController == null,
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index == 0) return _buildNoneTile(context);
                if (index == 1) return const Divider(height: 1);
                return _buildGroupTile(context, candidates[index - 2]);
              }, childCount: candidates.length + 2),
            ),
          ],
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

  Widget _buildGroupTile(BuildContext context, _GroupPickerItem item) {
    final theme = Theme.of(context);
    final group = item.group;
    final isSelected = group.id == currentParentId;

    Color? groupColor;
    if (group.colorHex != null) {
      groupColor = AppColors.fromHex(group.colorHex!);
    }

    final tile = PrismListRow(
      leading: group.emoji != null
          ? Text(group.emoji!, style: const TextStyle(fontSize: 22))
          : Icon(
              AppIcons.folderOutlined,
              color: groupColor ?? theme.colorScheme.onSurfaceVariant,
            ),
      title: Text(group.name),
      trailing: isSelected
          ? Icon(AppIcons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () {
        onSelected(group.id);
        Navigator.of(context).pop();
      },
    );

    final depthLabel = item.depth == 1 ? 'top level group' : 'nested group';
    return Semantics(
      button: true,
      label: '${group.name}, $depthLabel${isSelected ? ', selected' : ''}',
      excludeSemantics: true,
      child: tile,
    );
  }
}

/// Internal data class bundling a group with its computed tree depth.
class _GroupPickerItem {
  const _GroupPickerItem({required this.group, required this.depth});
  final MemberGroup group;
  final int depth;
}
