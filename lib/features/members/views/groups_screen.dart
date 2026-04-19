import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/delete_group_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Screen listing all member groups with reordering support.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  void _openCreateSheet() {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditGroupSheet(
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _confirmDelete(MemberGroup group) async {
    final hasChildren = ref.read(childGroupsProvider(group.id)).isNotEmpty;

    if (hasChildren) {
      PrismSheet.show(
        context: context,
        builder: (context) => DeleteGroupSheet(group: group),
      );
      return;
    }

    final l10n = context.l10n;
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberGroupDeleteTitle,
      message: l10n.memberGroupDeleteMessage(group.name),
      confirmLabel: l10n.memberGroupDeleteConfirm,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(ref.read(groupNotifierProvider.notifier).deleteGroup(group.id));
      if (mounted) {
        PrismToast.show(context, message: context.l10n.memberGroupDeleted(group.name));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final counts = ref.watch(groupMemberCountsProvider);
    final flatItems = ref.watch(flatGroupListProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.memberGroupsTitle,
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.add,
            tooltip: l10n.memberNewGroupTooltip,
            onPressed: _openCreateSheet,
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: flatItems.isEmpty
          ? EmptyState(
              icon: Icon(AppIcons.folderOutlined),
              title: l10n.memberGroupEmptyList,
              subtitle: l10n.memberGroupEmptySubtitle(
                  watchTerminology(context, ref).pluralLower),
              actionLabel: l10n.memberNewGroupTooltip,
              onAction: _openCreateSheet,
            )
          : ReorderableListView.builder(
              padding:
                  EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
              itemCount: flatItems.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final entry = flatItems[oldIndex];
                final targetEntry = flatItems[newIndex];

                // Only reorder within same parent (same-level siblings).
                if (entry.group.parentGroupId !=
                    targetEntry.group.parentGroupId) {
                  return;
                }

                final parentGroupId = entry.group.parentGroupId;
                final siblings = flatItems
                    .where((e) =>
                        e.group.parentGroupId == parentGroupId)
                    .map((e) => e.group)
                    .toList();

                final oldSiblingIndex = siblings.indexOf(entry.group);
                // Compute newSiblingIndex relative to the siblings list.
                final targetSiblingIndex = siblings.indexOf(targetEntry.group);
                final newSiblingIndex = (newIndex > oldIndex)
                    ? targetSiblingIndex - 1
                    : targetSiblingIndex;

                if (oldSiblingIndex == newSiblingIndex) return;

                final reordered = List<MemberGroup>.from(siblings);
                final item = reordered.removeAt(oldSiblingIndex);
                reordered.insert(newSiblingIndex, item);
                ref
                    .read(groupNotifierProvider.notifier)
                    .reorderGroups(reordered);
                Haptics.selection();
              },
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) => Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(
                        PrismShapes.of(context).radius(12)),
                    child: child,
                  ),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final entry = flatItems[index];
                return _GroupTile(
                  key: ValueKey(entry.group.id),
                  group: entry.group,
                  depth: entry.depth.clamp(0, 2),
                  reorderIndex: index,
                  memberCount: counts[entry.group.id] ?? 0,
                  onTap: () => context
                      .push(AppRoutePaths.settingsGroup(entry.group.id)),
                  onDelete: () => _confirmDelete(entry.group),
                );
              },
            ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    super.key,
    required this.group,
    required this.depth,
    required this.reorderIndex,
    required this.memberCount,
    required this.onTap,
    required this.onDelete,
  });

  final MemberGroup group;
  final int depth;
  final int reorderIndex;
  final int memberCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;
    final leftPadding = 16.0 + depth * 24.0;

    return Padding(
      padding: EdgeInsets.only(left: depth > 0 ? leftPadding - 16.0 : 0.0),
      child: Dismissible(
        key: ValueKey('dismiss_${group.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          color: theme.colorScheme.error,
          child: Icon(AppIcons.delete, color: theme.colorScheme.onError),
        ),
        confirmDismiss: (_) async {
          onDelete();
          return false;
        },
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(shapes.radius(14)),
          child: Container(
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 4,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(shapes.radius(14)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                if (hasColor)
                  Container(
                    width: 4,
                    height: 56,
                    color: accentColor,
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: hasColor ? 12 : 16,
                      right: 16,
                      top: 12,
                      bottom: 12,
                    ),
                    child: Row(
                      children: [
                        if (group.emoji != null && group.emoji!.isNotEmpty)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Center(
                              child: Text(
                                group.emoji!,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor ??
                                  theme.colorScheme.primaryContainer,
                            ),
                            child: Icon(
                              AppIcons.folderOutlined,
                              size: 16,
                              color: accentColor != null
                                  ? AppColors.warmWhite
                                  : theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            group.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (memberCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius:
                                  BorderRadius.circular(shapes.radius(12)),
                            ),
                            child: Text(
                              '$memberCount',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        ReorderableDragStartListener(
                          index: reorderIndex,
                          child: Icon(
                            AppIcons.dragHandle,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
