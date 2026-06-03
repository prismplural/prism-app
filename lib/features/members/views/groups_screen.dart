import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/delete_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/group_section_header.dart';
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/optimistic_list_controller.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

enum _GroupSortScope { topLevelOnly, allLevels }

/// Screen listing all member groups with reordering support.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({
    super.key,
    this.showBackButton = true,
    this.branch = MemberNavigationBranch.settings,
  });

  final bool showBackButton;
  final MemberNavigationBranch branch;

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  final GlobalKey<BlurPopupAnchorState> _optionsPopupKey = GlobalKey();
  late final OptimisticListController<MemberGroup, String> _optimisticGroups;

  @override
  void initState() {
    super.initState();
    _optimisticGroups = OptimisticListController<MemberGroup, String>(
      keyOf: (group) => group.id,
      providerItemsMatch: _sameGroupDisplayOrders,
    );
  }

  // Wide-layout group drill stack.
  final List<String> _paneGroupStack = [];

  String _groupPathFor(String id) => widget.branch.groupPath(id);

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
    final hideMemberCount =
        ref
            .watch(hideTotalMemberCountProvider)
            .whenOrNull(data: (value) => value) ??
        true;
    final providerFlatItems = ref.watch(flatGroupListProvider);
    final providerGroups = [for (final item in providerFlatItems) item.group];
    final optimisticGroups = _optimisticGroups.items;
    final flatItems = optimisticGroups == null
        ? providerFlatItems
        : _flattenGroups(optimisticGroups);
    if (_optimisticGroups.shouldClearFor(providerGroups)) {
      _clearOptimisticGroupsAfterBuild(optimisticGroups!);
    }
    final groups = [for (final item in flatItems) item.group];
    final usePrimaryGroupStack = shouldUseDetailSideSheet(context);
    final showingGroup = usePrimaryGroupStack && _paneGroupStack.isNotEmpty;

    return _primaryPane(
      enablePaneScope: usePrimaryGroupStack,
      levelKey: showingGroup ? 'group_${_paneGroupStack.last}' : '__root__',
      child: showingGroup
          ? GroupDetailScreen(
              key: ValueKey('primary_group_${_paneGroupStack.last}'),
              groupId: _paneGroupStack.last,
              branch: widget.branch,
            )
          : PrismPageScaffold(
              topBar: PrismTopBar(
                title: l10n.memberGroupsTitle,
                showBackButton: widget.showBackButton,
                actions: [
                  PrismTopBarAction(
                    icon: AppIcons.add,
                    tooltip: l10n.memberNewGroupTooltip,
                    onPressed: _openCreateSheet,
                  ),
                  if (groups.isNotEmpty) _buildOptionsMenuAction(groups),
                ],
              ),
              topBarMaxWidth: PrismTokens.contentMaxWidth,
              bodyPadding: EdgeInsets.zero,
              body: ClampedBody(
                child: flatItems.isEmpty
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
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: NavBarInset.of(context),
                        ),
                        itemCount: flatItems.length,
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) =>
                            _onReorder(flatItems, oldIndex, newIndex),
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
                            depth: entry.depth.clamp(
                              0,
                              kSectionsVisualDepthCap,
                            ),
                            reorderIndex: index,
                            memberCount: counts[entry.group.id] ?? 0,
                            showMemberCount: !hideMemberCount,
                            onTap: () => _openGroup(entry.group.id),
                            onDelete: () => _confirmDelete(entry.group),
                          );
                        },
                      ),
              ),
            ),
    );
  }

  /// Builds an animated primary-pane level.
  Widget _primaryPane({
    required bool enablePaneScope,
    required String levelKey,
    required Widget child,
  }) {
    final content = PaneNavigationSwitcher(
      depth: _paneGroupStack.length,
      child: KeyedSubtree(key: ValueKey(levelKey), child: child),
    );
    if (!enablePaneScope) return content;
    return ListDetailPaneScope(
      selectDetail: _openMemberDetailSheet,
      openInPane: _openGroupInPane,
      popPane: _popGroupPane,
      canPopPane: _paneGroupStack.isNotEmpty,
      selectedDetailId: null,
      child: content,
    );
  }

  void _openMemberDetailSheet(String id) {
    unawaited(
      showDetailSideSheet<void>(
        context,
        builder: (context) =>
            MemberDetailScreen(memberId: id, branch: widget.branch),
      ),
    );
  }

  void _openGroupInPane(String id) {
    if (_paneGroupStack.isNotEmpty && _paneGroupStack.last == id) return;
    setState(() => _paneGroupStack.add(id));
  }

  void _popGroupPane() {
    if (_paneGroupStack.isEmpty) return;
    _paneGroupStack.removeLast();
    setState(() {});
  }

  void _openGroup(String id) {
    if (shouldUseDetailSideSheet(context)) {
      _openGroupInPane(id);
    } else {
      unawaited(context.push(_groupPathFor(id)));
    }
  }

  void _onReorder(
    List<({MemberGroup group, int depth})> flatItems,
    int oldIndex,
    int newIndex,
  ) {
    final reordered = _reorderedSiblingsForDrop(flatItems, oldIndex, newIndex);
    if (reordered == null) return;

    final allGroups = [for (final item in flatItems) item.group];
    setState(() {
      _optimisticGroups.set(
        _groupsWithSiblingDisplayOrder(allGroups, reordered),
      );
    });
    unawaited(
      ref.read(groupNotifierProvider.notifier).reorderGroups(reordered),
    );
    Haptics.selection();
  }

  void _clearOptimisticGroupsAfterBuild(List<MemberGroup> current) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_optimisticGroups.isCurrent(current)) return;
      setState(_optimisticGroups.clear);
    });
  }

  List<MemberGroup>? _reorderedSiblingsForDrop(
    List<({MemberGroup group, int depth})> flatItems,
    int oldIndex,
    int rawNewIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= flatItems.length) return null;

    final dragged = flatItems[oldIndex].group;
    final parentGroupId = dragged.parentGroupId;
    final withoutDragged = List<({MemberGroup group, int depth})>.from(
      flatItems,
    )..removeAt(oldIndex);
    final insertionSlot =
        (rawNewIndex > oldIndex ? rawNewIndex - 1 : rawNewIndex)
            .clamp(0, withoutDragged.length)
            .toInt();

    if (!_isDropSlotInsideParentScope(
      withoutDragged,
      parentGroupId,
      insertionSlot,
    )) {
      return null;
    }

    final siblings = [
      for (final item in flatItems)
        if (item.group.parentGroupId == parentGroupId) item.group,
    ];
    final oldSiblingIndex = siblings.indexWhere((g) => g.id == dragged.id);
    if (oldSiblingIndex == -1) return null;

    final siblingsWithoutDragged = List<MemberGroup>.from(siblings)
      ..removeAt(oldSiblingIndex);
    final newSiblingIndex = withoutDragged
        .take(insertionSlot)
        .where((item) => item.group.parentGroupId == parentGroupId)
        .length
        .clamp(0, siblingsWithoutDragged.length)
        .toInt();

    final reordered = List<MemberGroup>.from(siblingsWithoutDragged)
      ..insert(newSiblingIndex, dragged);
    final before = siblings.map((g) => g.id).join('\u0000');
    final after = reordered.map((g) => g.id).join('\u0000');
    if (before == after) return null;
    return reordered;
  }

  bool _isDropSlotInsideParentScope(
    List<({MemberGroup group, int depth})> flatItems,
    String? parentGroupId,
    int insertionSlot,
  ) {
    if (parentGroupId == null) return true;

    final parentIndex = flatItems.indexWhere(
      (item) => item.group.id == parentGroupId,
    );
    if (parentIndex == -1) return false;

    final parentDepth = flatItems[parentIndex].depth;
    var subtreeEnd = parentIndex + 1;
    while (subtreeEnd < flatItems.length &&
        flatItems[subtreeEnd].depth > parentDepth) {
      subtreeEnd++;
    }

    return insertionSlot > parentIndex && insertionSlot <= subtreeEnd;
  }

  List<MemberGroup> _groupsWithSiblingDisplayOrder(
    List<MemberGroup> allGroups,
    List<MemberGroup> reorderedSiblings,
  ) {
    final displayOrders = <String, int>{
      for (var i = 0; i < reorderedSiblings.length; i++)
        reorderedSiblings[i].id: i,
    };
    return [
      for (final group in allGroups)
        if (displayOrders.containsKey(group.id))
          group.copyWith(displayOrder: displayOrders[group.id]!)
        else
          group,
    ];
  }

  List<({MemberGroup group, int depth})> _flattenGroups(
    List<MemberGroup> groups,
  ) {
    final ordered = List<MemberGroup>.from(groups)
      ..sort((a, b) {
        final order = a.displayOrder.compareTo(b.displayOrder);
        if (order != 0) return order;
        return a.id.compareTo(b.id);
      });
    return GroupTreeUtils.flattenTree(
      GroupTreeUtils.buildGroupTree(GroupTreeUtils.resolveSyncCycles(ordered)),
    );
  }

  bool _sameGroupDisplayOrders(
    List<MemberGroup> providerGroups,
    List<MemberGroup> optimisticGroups,
  ) {
    if (providerGroups.length != optimisticGroups.length) return false;
    final providerById = {for (final group in providerGroups) group.id: group};
    for (final optimistic in optimisticGroups) {
      final provider = providerById[optimistic.id];
      if (provider == null) return false;
      if (provider.parentGroupId != optimistic.parentGroupId) return false;
      if (provider.displayOrder != optimistic.displayOrder) return false;
    }
    return true;
  }

  Widget _buildOptionsMenuAction(List<MemberGroup> groups) {
    final l10n = context.l10n;
    final canApplySort = _hasSortableSiblings(groups);
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
        enabled: canApplySort,
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
        enabled: canApplySort,
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
        enabled: canApplySort,
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
      width: 240,
      maxHeight: MediaQuery.sizeOf(context).height - 24,
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
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return PrismListRow(
      dense: true,
      enabled: enabled,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: Icon(
        icon,
        size: 20,
        color: enabled ? null : theme.disabledColor,
      ),
      title: Text(label, style: theme.textTheme.bodyMedium),
      onTap: enabled ? onTap : null,
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
    final scope = await _resolveGroupSortScope(groups);
    if (scope == null) return;

    final byParent = <String?, List<MemberGroup>>{};
    for (final group in groups) {
      byParent.putIfAbsent(group.parentGroupId, () => []).add(group);
    }

    final notifier = ref.read(groupNotifierProvider.notifier);
    for (final entry in byParent.entries) {
      if (scope == _GroupSortScope.topLevelOnly && entry.key != null) {
        continue;
      }
      final siblings = entry.value;
      if (siblings.length < 2) continue;
      final sorted = [...siblings]..sort(compare);
      await notifier.reorderGroups(sorted);
    }

    Haptics.selection();
    if (!mounted) return;
    PrismToast.show(context, message: context.l10n.memberOrderUpdated);
  }

  Future<_GroupSortScope?> _resolveGroupSortScope(
    List<MemberGroup> groups,
  ) async {
    final hasSortableTopLevel =
        groups.where((group) => group.parentGroupId == null).length > 1;
    final hasSortableSubGroups = _hasSortableSubGroupSiblings(groups);
    if (!hasSortableTopLevel && !hasSortableSubGroups) return null;
    if (!hasSortableTopLevel || !hasSortableSubGroups) {
      return _GroupSortScope.allLevels;
    }

    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return null;

    return PrismDialog.show<_GroupSortScope>(
      context: context,
      title: context.l10n.groupSortScopeTitle,
      message: context.l10n.groupSortScopeMessage,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrismListRow(
              dense: true,
              leading: Icon(AppIcons.folderOutlined, size: 20),
              title: Text(dialogContext.l10n.groupSortScopeTopLevel),
              onTap: () =>
                  Navigator.of(dialogContext).pop(_GroupSortScope.topLevelOnly),
            ),
            PrismListRow(
              dense: true,
              leading: Icon(AppIcons.folderOutlined, size: 20),
              title: Text(dialogContext.l10n.groupSortScopeAllLevels),
              onTap: () =>
                  Navigator.of(dialogContext).pop(_GroupSortScope.allLevels),
            ),
          ],
        );
      },
    );
  }

  bool _hasSortableSubGroupSiblings(List<MemberGroup> groups) {
    final counts = <String, int>{};
    for (final group in groups) {
      final parentId = group.parentGroupId;
      if (parentId == null) continue;
      final count = (counts[parentId] ?? 0) + 1;
      if (count > 1) return true;
      counts[parentId] = count;
    }
    return false;
  }
}
