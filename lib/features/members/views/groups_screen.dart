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
import 'package:prism_plurality/features/members/widgets/group_section_header.dart';
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
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
  const GroupsScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  final GlobalKey<BlurPopupAnchorState> _optionsPopupKey = GlobalKey();

  /// Path of the current location, used to derive which navigation branch
  /// this screen is rendering in (settings, members, or groups tab).
  String _groupPathFor(String id) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith(AppRoutePaths.groups)) {
      return AppRoutePaths.group(id);
    }
    if (location.startsWith(AppRoutePaths.members)) {
      return AppRoutePaths.memberGroup(id);
    }
    return AppRoutePaths.settingsGroup(id);
  }

  void _openCreateSheet() {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          CreateEditGroupSheet(scrollController: scrollController),
    );
  }

  Future<void> _confirmDelete(MemberGroup group) async {
    final hasChildren = ref.read(childGroupsProvider(group.id)).isNotEmpty;

    if (hasChildren) {
      unawaited(
        PrismSheet.show(
          context: context,
          builder: (context) => DeleteGroupSheet(group: group),
        ),
      );
      return;
    }

    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberGroupDeleteTitle,
      message: l10n.memberGroupDeleteMessage(group.name, terms.plural),
      confirmLabel: l10n.memberGroupDeleteConfirm,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(ref.read(groupNotifierProvider.notifier).deleteGroup(group.id));
      if (mounted) {
        PrismToast.show(
          context,
          message: context.l10n.memberGroupDeleted(group.name),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final counts = ref.watch(groupMemberCountsProvider);
    final flatItems = ref.watch(flatGroupListProvider);
    final groups = [for (final item in flatItems) item.group];
    final canSortGroups = _hasSortableSiblings(groups);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.memberGroupsTitle,
        showBackButton: widget.showBackButton,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.add,
            tooltip: l10n.memberNewGroupTooltip,
            onPressed: _openCreateSheet,
          ),
          if (canSortGroups) _buildOptionsMenuAction(groups),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: flatItems.isEmpty
          ? EmptyState(
              icon: Icon(AppIcons.folderOutlined),
              title: l10n.memberGroupEmptyList,
              subtitle: l10n.memberGroupEmptySubtitle(
                watchTerminology(context, ref).pluralLower,
              ),
              actionLabel: l10n.memberNewGroupTooltip,
              onAction: _openCreateSheet,
            )
          : ReorderableListView.builder(
              padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
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
                    .where((e) => e.group.parentGroupId == parentGroupId)
                    .map((e) => e.group)
                    .toList();

                final oldSiblingIndex = siblings.indexOf(entry.group);
                // Compute newSiblingIndex relative to the siblings list.
                final targetSiblingIndex = siblings.indexOf(targetEntry.group);
                final newSiblingIndex = targetSiblingIndex;

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
                      PrismShapes.of(context).radius(12),
                    ),
                    child: child,
                  ),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final entry = flatItems[index];
                return MemberGroupRow(
                  key: ValueKey(entry.group.id),
                  group: entry.group,
                  depth: entry.depth.clamp(0, kSectionsVisualDepthCap),
                  reorderIndex: index,
                  memberCount: counts[entry.group.id] ?? 0,
                  onTap: () => context.push(_groupPathFor(entry.group.id)),
                  onDelete: () => _confirmDelete(entry.group),
                );
              },
            ),
    );
  }

  Widget _buildOptionsMenuAction(List<MemberGroup> groups) {
    final l10n = context.l10n;
    final entries = <Widget Function(BuildContext, VoidCallback)>[
      (ctx, _) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            ctx.l10n.memberReorderBy,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
      (ctx, close) => _buildSortMenuRow(
        context: ctx,
        icon: AppIcons.arrowUpward,
        label: ctx.l10n.memberSortNameAZ,
        onTap: () {
          close();
          unawaited(
            _reorderSiblingGroupsBy(
              groups,
              (a, b) => _compareText(a.name, b.name, a.id, b.id),
            ),
          );
        },
      ),
      (ctx, close) => _buildSortMenuRow(
        context: ctx,
        icon: AppIcons.arrowDownward,
        label: ctx.l10n.memberSortNameZA,
        onTap: () {
          close();
          unawaited(
            _reorderSiblingGroupsBy(
              groups,
              (a, b) => _compareText(b.name, a.name, a.id, b.id),
            ),
          );
        },
      ),
      (ctx, close) => _buildSortMenuRow(
        context: ctx,
        icon: AppIcons.history,
        label: ctx.l10n.memberSortRecentlyCreated,
        onTap: () {
          close();
          unawaited(
            _reorderSiblingGroupsBy(groups, (a, b) {
              final created = b.createdAt.compareTo(a.createdAt);
              if (created != 0) return created;
              return a.id.compareTo(b.id);
            }),
          );
        },
      ),
    ];

    return BlurPopupAnchor(
      key: _optionsPopupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: BlurPopupDirection.down,
      width: 260,
      maxHeight: 320,
      itemCount: entries.length,
      semanticLabel: l10n.moreOptions,
      itemBuilder: (ctx, index, close) => entries[index](ctx, close),
      child: PrismTopBarAction(
        icon: AppIcons.moreVert,
        tooltip: l10n.moreOptions,
        onPressed: () => _optionsPopupKey.currentState?.show(),
      ),
    );
  }

  Widget _buildSortMenuRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return PrismListRow(
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: Icon(icon, size: 20),
      title: Text(label, style: theme.textTheme.bodyMedium),
      onTap: onTap,
    );
  }

  int _compareText(String left, String right, String leftId, String rightId) {
    final text = left.toLowerCase().compareTo(right.toLowerCase());
    if (text != 0) return text;
    return leftId.compareTo(rightId);
  }

  bool _hasSortableSiblings(List<MemberGroup> groups) {
    final counts = <String?, int>{};
    for (final group in groups) {
      final count = (counts[group.parentGroupId] ?? 0) + 1;
      if (count > 1) return true;
      counts[group.parentGroupId] = count;
    }
    return false;
  }

  Future<void> _reorderSiblingGroupsBy(
    List<MemberGroup> groups,
    int Function(MemberGroup a, MemberGroup b) compare,
  ) async {
    final byParent = <String?, List<MemberGroup>>{};
    for (final group in groups) {
      byParent.putIfAbsent(group.parentGroupId, () => []).add(group);
    }

    final notifier = ref.read(groupNotifierProvider.notifier);
    for (final siblings in byParent.values) {
      if (siblings.length < 2) continue;
      final sorted = [...siblings]..sort(compare);
      await notifier.reorderGroups(sorted);
    }

    Haptics.selection();
    if (!mounted) return;
    PrismToast.show(context, message: context.l10n.memberOrderUpdated);
  }
}
