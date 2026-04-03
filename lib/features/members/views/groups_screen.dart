import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';

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
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete group',
      message: 'Are you sure you want to delete "${group.name}"? '
          'Members will not be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      ref.read(groupNotifierProvider.notifier).deleteGroup(group.id);
      if (mounted) {
        PrismToast.show(context, message: '${group.name} deleted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(allGroupsProvider);
    final countsAsync = ref.watch(groupMemberCountsProvider);
    final counts = countsAsync.whenOrNull(data: (c) => c) ?? {};

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Groups',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: Icons.add,
            tooltip: 'New group',
            onPressed: _openCreateSheet,
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: groupsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading groups: $e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return EmptyState(
              icon: Icons.folder_outlined,
              title: 'No groups yet',
              subtitle: 'Create groups to organize your system members',
              actionLabel: 'New group',
              onAction: _openCreateSheet,
            );
          }

          return ReorderableListView.builder(
            padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
            itemCount: groups.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final reordered = List<MemberGroup>.from(groups);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              ref.read(groupNotifierProvider.notifier).reorderGroups(reordered);
              Haptics.selection();
            },
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final group = groups[index];
              return _GroupTile(
                key: ValueKey(group.id),
                group: group,
                reorderIndex: index,
                memberCount: counts[group.id] ?? 0,
                onTap: () =>
                    context.push(AppRoutePaths.settingsGroup(group.id)),
                onDelete: () => _confirmDelete(group),
              );
            },
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
    required this.reorderIndex,
    required this.memberCount,
    required this.onTap,
    required this.onDelete,
  });

  final MemberGroup group;
  final int reorderIndex;
  final int memberCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;

    return Dismissible(
      key: ValueKey('dismiss_${group.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
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
                      // Emoji or colored circle fallback
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
                            Icons.folder_outlined,
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
                            borderRadius: BorderRadius.circular(12),
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
                          Icons.drag_handle,
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
    );
  }
}
