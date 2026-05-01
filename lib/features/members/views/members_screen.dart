import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/widgets/member_group_filter_bar.dart';
import 'package:prism_plurality/features/members/widgets/group_section_header.dart';
import 'package:prism_plurality/features/members/widgets/manage_groups_sheet.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Main member list screen.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  bool _showInactive = false;

  // Section keys for scroll-to-section navigation in the grouped list.
  final Map<String, GlobalKey> _sectionKeys = {};
  final GlobalKey _ungroupedKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Whether we're inside the top-level /members branch or /settings/members.
  bool get _isTopLevelBranch {
    final location = GoRouterState.of(context).uri.path;
    return location.startsWith(AppRoutePaths.members) &&
        !location.startsWith(AppRoutePaths.settings);
  }

  String _memberPath(BuildContext context, String id) {
    return _isTopLevelBranch
        ? AppRoutePaths.member(id)
        : AppRoutePaths.settingsMember(id);
  }

  void _showOptionsMenu(List<Member>? members, dynamic terms) {
    final l10n = context.l10n;
    final canSearch = members != null && members.isNotEmpty;
    PrismSheet.show<void>(
      context: context,
      title: l10n.options,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final ctxL10n = ctx.l10n;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PrismListRow(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Icon(AppIcons.search),
              title: Text(ctxL10n.terminologySearchHint(terms.pluralLower)),
              enabled: canSearch,
              onTap: canSearch
                  ? () {
                      Navigator.of(ctx).pop();
                      _openSearch(members);
                    }
                  : null,
            ),
            const Divider(height: 1),
            PrismListRow(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Icon(
                _showInactive
                    ? AppIcons.visibility
                    : AppIcons.visibilityOutlined,
              ),
              title: Text(
                _showInactive
                    ? ctxL10n.memberHideInactive
                    : ctxL10n.memberShowInactive,
              ),
              trailing: _showInactive
                  ? Icon(
                      AppIcons.check,
                      size: 18,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() => _showInactive = !_showInactive);
                ref
                    .read(showInactiveInGroupedListProvider.notifier)
                    .set(_showInactive);
              },
            ),
            if (members != null && members.length > 1) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                child: Text(
                  ctxL10n.memberReorderBy,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                dense: true,
                title: Text(ctxL10n.memberSortNameAZ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderBy(
                    members,
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                dense: true,
                title: Text(ctxL10n.memberSortNameZA),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderBy(
                    members,
                    (a, b) =>
                        b.name.toLowerCase().compareTo(a.name.toLowerCase()),
                  );
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                dense: true,
                title: Text(ctxL10n.memberSortRecentlyCreated),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderBy(
                    members,
                    (a, b) => b.createdAt.compareTo(a.createdAt),
                  );
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                dense: true,
                title: Text(ctxL10n.memberSortMostFronting),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderByFronting(members, descending: true);
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                dense: true,
                title: Text(ctxL10n.memberSortLeastFronting),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderByFronting(members, descending: false);
                },
              ),
            ],
          ],
        );
      },
    );
  }

  void _openAddSheet() {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          AddEditMemberSheet(scrollController: scrollController),
    );
  }

  Future<void> _openSearch(List<Member> members) async {
    final terms = readTerminology(context, ref);
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      groups: readMemberSearchGroups(ref, members),
    );
    if (!mounted) return;
    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        unawaited(context.push(_memberPath(context, memberId)));
      case MemberSearchResultDismissed():
      case MemberSearchResultCleared():
      case MemberSearchResultUnknown():
        break;
    }
  }

  Future<bool?> _confirmDeleteMember(
    BuildContext context,
    String memberId,
    String memberName,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.terminologyDeleteItem(
        readTerminology(context, ref).singular,
      ),
      message:
          'Are you sure you want to delete $memberName? This action cannot be undone.',
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(
        ref.read(membersNotifierProvider.notifier).deleteMember(memberId),
      );
    }
    return confirmed;
  }

  void _toggleMemberActive(Member member) {
    final newActive = !member.isActive;
    ref
        .read(membersNotifierProvider.notifier)
        .updateMember(member.copyWith(isActive: newActive));
    Haptics.selection();
    PrismToast.show(
      context,
      message: newActive
          ? context.l10n.memberActivated(member.name)
          : context.l10n.memberDeactivated(member.name),
    );
  }

  Future<void> _reorderBy(
    List<Member> members,
    int Function(Member a, Member b) compare,
  ) async {
    final sorted = [...members]..sort(compare);
    unawaited(
      ref.read(membersNotifierProvider.notifier).reorderMembers(sorted),
    );
    Haptics.selection();
    if (mounted) {
      PrismToast.show(context, message: context.l10n.memberOrderUpdated);
    }
  }

  Future<void> _reorderByFronting(
    List<Member> members, {
    required bool descending,
  }) async {
    final statsFutures = members.map(
      (m) => ref.read(memberFrontingStatsProvider(m.id).future),
    );
    final allStats = await Future.wait(statsFutures);
    final statsMap = <String, int>{
      for (var i = 0; i < members.length; i++)
        members[i].id: allStats[i].totalSessions,
    };
    final sorted = [...members]
      ..sort((a, b) {
        final aCount = statsMap[a.id] ?? 0;
        final bCount = statsMap[b.id] ?? 0;
        return descending ? bCount.compareTo(aCount) : aCount.compareTo(bCount);
      });
    unawaited(
      ref.read(membersNotifierProvider.notifier).reorderMembers(sorted),
    );
    Haptics.selection();
    if (mounted) {
      PrismToast.show(context, message: context.l10n.memberOrderUpdated);
    }
  }

  void _onReorder(List<Member> members, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<Member>.from(members);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    ref.read(membersNotifierProvider.notifier).reorderMembers(reordered);
  }

  void _scrollToGroup(String? groupId) {
    if (groupId == null) {
      // "All" — expand everything; no scroll.
      ref.read(collapsedGroupsProvider.notifier).expandAll();
      return;
    }

    GlobalKey? key;
    if (groupId == '__ungrouped__') {
      key = _ungroupedKey;
    } else {
      key = _sectionKeys[groupId];
    }

    final collapsed = ref.read(collapsedGroupsProvider);
    final needsExpand =
        groupId != '__ungrouped__' && collapsed.contains(groupId);
    if (needsExpand) {
      ref.read(collapsedGroupsProvider.notifier).toggle(groupId);
    }

    void doScroll() {
      final ctx = key?.currentContext;
      final renderObject = ctx?.findRenderObject();
      if (renderObject == null || !_scrollController.hasClients) return;

      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) return;

      final position = _scrollController.position;
      // Keep the jump scoped to the grouped list. Scrollable.ensureVisible
      // also walks the outer NestedScrollView, which can hide the chip bar
      // under the pinned top bar.
      final targetOffset = viewport
          .getOffsetToReveal(renderObject, 0)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);

      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (needsExpand || key?.currentContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    } else {
      doScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Member-list screen is user-facing — hide the Unknown sentinel from both
    // the active and "show inactive" views. Sentinel still resolves for any
    // session that points at it via the unfiltered providers used elsewhere.
    final membersAsync = _showInactive
        ? ref.watch(userVisibleAllMembersProvider)
        : ref.watch(userVisibleMembersProvider);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final terms = watchTerminology(context, ref);

    // Build a set of currently-fronting member IDs.
    final frontingIds =
        activeSessionsAsync.whenOrNull(
          data: (sessions) =>
              sessions.map((s) => s.memberId).whereType<String>().toSet(),
        ) ??
        <String>{};

    final groups = ref.watch(allGroupsProvider).value ?? [];
    final hasGroups = groups.isNotEmpty;

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: terms.plural,
        showBackButton: widget.showBackButton,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.add,
            tooltip: context.l10n.terminologyAddButton(terms.singular),
            onPressed: _openAddSheet,
          ),
          PrismTopBarAction(
            icon: AppIcons.moreVert,
            tooltip: context.l10n.options,
            onPressed: () => _showOptionsMenu(membersAsync.value, terms),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          MemberGroupFilterBar(onChipTap: hasGroups ? _scrollToGroup : null),
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.md,
              child: KeyedSubtree(
                key: ValueKey(_showInactive),
                child: membersAsync.when(
                  loading: () => const PrismLoadingState(),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.l10n.terminologyLoadError(
                          terms.pluralLower,
                          e.toString(),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  data: (rawMembers) {
                    if (rawMembers.isEmpty) {
                      return EmptyState(
                        icon: Icon(AppIcons.peopleOutline),
                        title: _showInactive
                            ? context.l10n.terminologyEmptyTitle(
                                terms.pluralLower,
                              )
                            : context.l10n.terminologyEmptyActiveTitle(
                                terms.pluralLower,
                              ),
                        subtitle: context.l10n.terminologyAddFirstSubtitle(
                          terms.singularLower,
                        ),
                        actionLabel: context.l10n.terminologyAddButton(
                          terms.singular,
                        ),
                        onAction: _openAddSheet,
                      );
                    }

                    if (!hasGroups) {
                      return _buildFlatList(rawMembers, frontingIds);
                    }

                    final groupedItems = ref.watch(groupedMemberListProvider);
                    final counts = ref.watch(groupMemberCountsProvider);
                    return _buildGroupedList(groupedItems, counts, frontingIds);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatList(List<Member> members, Set<String> frontingIds) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
      itemCount: members.length,
      onReorder: (oldIndex, newIndex) =>
          _onReorder(members, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final member = members[index];
        final isFronting = frontingIds.contains(member.id);
        return _buildMemberTile(member, isFronting, reorderIndex: index);
      },
    );
  }

  Widget _buildGroupedList(
    List<GroupedMemberListItem> items,
    Map<String, int> counts,
    Set<String> frontingIds,
  ) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 4, bottom: NavBarInset.of(context)),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = items[index];
              if (item is GroupSectionItem) {
                final key = _sectionKeys.putIfAbsent(
                  item.group.id,
                  GlobalKey.new,
                );
                final header = GroupSectionHeader(
                  key: key,
                  group: item.group,
                  depth: item.depth.clamp(0, 2),
                  memberCount: counts[item.group.id] ?? 0,
                  isCollapsed: item.isCollapsed,
                  canCollapse: true,
                  onToggle: () => ref
                      .read(collapsedGroupsProvider.notifier)
                      .toggle(item.group.id),
                );
                if (item.depth == 0 && index > 0) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      const SizedBox(height: 4),
                      header,
                    ],
                  );
                }
                return header;
              }
              if (item is UngroupedSectionItem) {
                final ungroupedCount = items
                    .skip(index + 1)
                    .whereType<MemberRowItem>()
                    .length;
                return GroupSectionHeader(
                  key: _ungroupedKey,
                  group: null,
                  depth: 0,
                  memberCount: ungroupedCount,
                  isCollapsed: false,
                  canCollapse: false,
                  onToggle: null,
                );
              }
              if (item is MemberRowItem) {
                final isFronting = frontingIds.contains(item.member.id);
                final indent = item.depth.clamp(0, 2) * 16.0;
                return Padding(
                  padding: EdgeInsets.only(left: indent),
                  child: _buildMemberTile(item.member, isFronting),
                );
              }
              return const SizedBox.shrink();
            }, childCount: items.length),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberTile(Member member, bool isFronting, {int? reorderIndex}) {
    final theme = Theme.of(context);
    final actions = _memberContextActions(member, isFronting);

    return BlurPopupAnchor(
      key: reorderIndex != null ? ValueKey(member.id) : null,
      trigger: BlurPopupTrigger.longPress,
      width: 220,
      maxHeight: 320,
      semanticLabel: context.l10n.memberMoreOptionsTooltip,
      itemCount: actions.length,
      itemBuilder: (context, index, close) {
        final action = actions[index];
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: Icon(action.icon, size: 20),
          title: Text(action.label),
          destructive: action.destructive,
          onTap: () {
            close();
            unawaited(Future<void>.sync(action.onSelected));
          },
        );
      },
      child: MemberCard(
        member: member,
        onTap: () => context.push(_memberPath(context, member.id)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFronting) ...[
              PrismPill(
                label: context.l10n.memberFrontingChip,
                icon: AppIcons.flashOn,
                color: AppColors.fronting(theme.brightness),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              const SizedBox(width: 4),
            ],
            if (reorderIndex != null)
              ReorderableDragStartListener(
                index: reorderIndex,
                child: Icon(
                  AppIcons.dragHandle,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_MemberContextAction> _memberContextActions(
    Member member,
    bool isFronting,
  ) {
    return [
      if (!isFronting)
        _MemberContextAction(
          label: context.l10n.memberSetAsFronter,
          icon: AppIcons.flashOn,
          onSelected: () => _startFronting(member),
        ),
      _MemberContextAction(
        label: context.l10n.memberGroupAddToGroup,
        icon: AppIcons.groupOutlined,
        onSelected: () => _showManageGroupsSheet(member),
      ),
      _MemberContextAction(
        label: member.isActive
            ? context.l10n.deactivate
            : context.l10n.activate,
        icon: member.isActive
            ? AppIcons.archiveOutlined
            : AppIcons.unarchiveOutlined,
        onSelected: () => _toggleMemberActive(member),
      ),
      _MemberContextAction(
        label: context.l10n.delete,
        icon: AppIcons.deleteOutline,
        destructive: true,
        onSelected: () => _confirmDeleteMember(context, member.id, member.name),
      ),
    ];
  }

  Future<void> _startFronting(Member member) async {
    try {
      await ref.read(frontingNotifierProvider.notifier).startFronting([
        member.id,
      ]);
      if (!mounted) return;
      PrismToast.show(
        context,
        message: context.l10n.memberIsFronting(member.name),
      );
    } catch (e) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.frontingErrorSwitchingFronter(e),
      );
    }
  }

  void _showManageGroupsSheet(Member member) {
    PrismSheet.show<void>(
      context: context,
      title: context.l10n.memberGroupManageTitle,
      builder: (_) =>
          ManageGroupsSheet(memberId: member.id, memberName: member.name),
    );
  }
}

class _MemberContextAction {
  const _MemberContextAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function() onSelected;
  final bool destructive;
}
