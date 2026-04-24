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

/// Modal picker for selecting a parent group.
///
/// Presented inside a [PrismSheet.show] call. Lists all groups that can legally
/// be assigned as the parent of the group being created or edited, filtering out:
/// - The group itself (can't be its own parent)
/// - Any descendant of the group (cycle prevention)
/// - Groups at depth ≥ 3 (would exceed the three-level nesting limit) — shown
///   grayed out so the user understands why they are unavailable.
///
/// Always includes a "None (top level)" option at the top.
class GroupParentPicker extends ConsumerWidget {
  const GroupParentPicker({
    super.key,
    required this.excludeGroupId,
    required this.currentParentId,
    required this.onSelected,
  });

  /// The ID of the group being edited, or null when creating a new group.
  /// This group and all its descendants are excluded from the list.
  final String? excludeGroupId;

  /// The currently selected parent group ID, or null for root level.
  final String? currentParentId;

  /// Called when the user taps a group (or the "None" option).
  /// Receives null to indicate root / no parent.
  final void Function(String? groupId) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final allGroupsAsync = ref.watch(allGroupsProvider);
    final tree = ref.watch(groupTreeProvider);

    return allGroupsAsync.when(
      loading: () => const SizedBox(height: 200, child: PrismLoadingState()),
      error: (e, _) =>
          Padding(padding: const EdgeInsets.all(16), child: Text(l10n.error)),
      data: (allGroups) {
        // How tall is the group being edited (1 = leaf, 2 = has children, 3 = has grandchildren)?
        final editedSubtreeHeight = excludeGroupId != null
            ? GroupTreeUtils.getSubtreeHeight(excludeGroupId!, tree)
            : 1;

        // Build the candidate list, filtering out illegal choices.
        final candidates = <_GroupPickerItem>[];

        for (final group in allGroups) {
          // Skip the group itself.
          if (excludeGroupId != null && group.id == excludeGroupId) continue;

          // Skip descendants (cycle prevention).
          if (excludeGroupId != null &&
              GroupTreeUtils.wouldCreateCycle(
                excludeGroupId!,
                group.id,
                tree,
              )) {
            continue;
          }

          final depth = GroupTreeUtils.getGroupDepth(group.id, tree);
          candidates.add(_GroupPickerItem(group: group, depth: depth));
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  l10n.memberGroupParentLabel,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return PrismListRow(
                        leading: Icon(
                          AppIcons.folderOutlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(l10n.memberGroupParentNone),
                        trailing: currentParentId == null
                            ? Icon(
                                AppIcons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        dense: true,
                        onTap: () {
                          onSelected(null);
                          Navigator.of(context).pop();
                        },
                      );
                    }
                    if (index == 1) return const Divider(height: 1);
                    return _buildGroupTile(
                      context,
                      candidates[index - 2],
                      theme,
                      l10n,
                      editedSubtreeHeight,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupTile(
    BuildContext context,
    _GroupPickerItem item,
    ThemeData theme,
    AppLocalizations l10n,
    int editedSubtreeHeight,
  ) {
    final group = item.group;
    final isAtDepthLimit = item.depth + editedSubtreeHeight > 3;
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
      subtitle: isAtDepthLimit
          ? Text(
              l10n.memberGroupParentDepthLimit,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: isSelected
          ? Icon(AppIcons.check, color: theme.colorScheme.primary)
          : null,
      dense: true,
      enabled: !isAtDepthLimit,
      onTap: () {
        onSelected(group.id);
        Navigator.of(context).pop();
      },
    );

    if (isAtDepthLimit) {
      return Semantics(
        enabled: false,
        label: '${group.name}, cannot nest further',
        excludeSemantics: true,
        child: Opacity(opacity: 0.4, child: tile),
      );
    }

    final depthLabel = item.depth == 1
        ? 'top level group'
        : item.depth == 2
        ? 'sub-group'
        : 'sub-sub-group';
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
