import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/delete_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/group_avatar.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/features/members/providers/group_display_prefs_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/optimistic_list_controller.dart';

String _memberPathFor(
  MemberNavigationBranch branch,
  String currentGroupId,
  String memberId,
) => branch.memberPath(memberId, groupId: currentGroupId);

const _groupDetailRowsLoadingHeight = 160.0;

typedef _GroupMemberPair = (MemberGroupEntry, Member);

/// Detail screen for a single member group.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    this.branch = MemberNavigationBranch.settings,
  });

  final String groupId;
  final MemberNavigationBranch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupAsync = ref.watch(groupByIdProvider(groupId));
    final paneScope = ListDetailPaneScope.maybeOf(context);

    PreferredSizeWidget transientBar() => PrismTopBar(
      title: '',
      showBackButton: paneScope == null,
      leading: paneScope != null
          ? PrismTopBarAction(
              icon: AppIcons.arrowBack,
              tooltip: context.l10n.back,
              onPressed: paneScope.popPane,
            )
          : null,
    );

    return groupAsync.when(
      loading: () => PrismPageScaffold(
        topBar: transientBar(),
        topBarMaxWidth: PrismTokens.contentMaxWidth,
        body: const ClampedBody(child: PrismLoadingState()),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: transientBar(),
        topBarMaxWidth: PrismTokens.contentMaxWidth,
        body: ClampedBody(
          child: Center(child: Text(l10n.memberGroupErrorLoadingDetail(e))),
        ),
      ),
      data: (group) {
        if (group == null) {
          return PrismPageScaffold(
            topBar: transientBar(),
            topBarMaxWidth: PrismTokens.contentMaxWidth,
            body: ClampedBody(
              child: Center(child: Text(l10n.memberGroupNotFound)),
            ),
          );
        }
        return _GroupDetailBody(group: group, branch: branch);
      },
    );
  }
}

class _GroupDetailBody extends ConsumerStatefulWidget {
  const _GroupDetailBody({required this.group, required this.branch});

  final MemberGroup group;
  final MemberNavigationBranch branch;

  @override
  ConsumerState<_GroupDetailBody> createState() => _GroupDetailBodyState();
}

class _GroupDetailBodyState extends ConsumerState<_GroupDetailBody> {
  final GlobalKey<BlurPopupAnchorState> _optionsPopupKey = GlobalKey();

  /// Best-effort focus retention after a11y move actions. The polite
  /// `_announce` is the reliable signal; Flutter focus delivery to
  /// non-input rebuilt widgets is not contractual.
  final Map<String, FocusNode> _entryFocusNodes = {};
  String? _pendingFocusEntryId;
  late final OptimisticListController<_GroupMemberPair, String>
  _optimisticMemberPairs;

  MemberGroup get group => widget.group;
  MemberNavigationBranch get branch => widget.branch;

  FocusNode _focusNodeFor(String entryId) {
    return _entryFocusNodes.putIfAbsent(
      entryId,
      () =>
          FocusNode(debugLabel: 'group_member_$entryId', skipTraversal: false),
    );
  }

  @override
  void initState() {
    super.initState();
    _optimisticMemberPairs = OptimisticListController<_GroupMemberPair, String>(
      keyOf: (pair) => pair.$1.id,
    );
  }

  @override
  void didUpdateWidget(covariant _GroupDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _optimisticMemberPairs.clear();
    }
  }

  @override
  void dispose() {
    for (final node in _entryFocusNodes.values) {
      node.dispose();
    }
    _entryFocusNodes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final paneScope = ListDetailPaneScope.maybeOf(context);
    final canPopPane = paneScope?.canPopPane ?? false;
    final terms = watchTerminology(context, ref);
    final entriesAsync = ref.watch(groupEntriesProvider(group.id));
    final allGroupsAsync = ref.watch(allGroupsProvider);
    final canAddSubGroup = allGroupsAsync.hasValue;
    final allGroups =
        allGroupsAsync.whenOrNull(data: (g) => g) ?? const <MemberGroup>[];
    final ancestors = _resolveAncestors(group, allGroups);
    final subGroups = ref.watch(childGroupsProvider(group.id));
    final entries = entriesAsync.whenOrNull(data: (entries) => entries);
    final hasMembers = entries?.isNotEmpty ?? false;

    final providerVisiblePairsAsync = ref.watch(
      sortedGroupMembersAsyncProvider(group.id),
    );
    final providerVisiblePairs =
        providerVisiblePairsAsync.value ?? const <(MemberGroupEntry, Member)>[];
    final providerVisiblePairsInitialLoading =
        providerVisiblePairsAsync.isLoading &&
        !providerVisiblePairsAsync.hasValue;
    final providerVisiblePairsInitialError =
        providerVisiblePairsAsync.hasError &&
            !providerVisiblePairsAsync.hasValue
        ? providerVisiblePairsAsync.error
        : null;
    final optimisticVisiblePairs = _optimisticMemberPairs.items;
    final visiblePairs = _optimisticMemberPairs.displayItems(
      providerVisiblePairs,
    );
    if (_optimisticMemberPairs.shouldClearFor(providerVisiblePairs) &&
        optimisticVisiblePairs != null) {
      _clearOptimisticMemberPairsAfterBuild(optimisticVisiblePairs);
    }
    // Prune stale FocusNodes only on membership change, not every build —
    // avoids O(n) set-construction on every scroll/drag tick/keystroke.
    ref.listen<List<(MemberGroupEntry, Member)>>(
      sortedGroupMembersProvider(group.id),
      (_, next) {
        final liveIds = next.map((pair) => pair.$1.id).toSet();
        final stale = _entryFocusNodes.keys
            .where((id) => !liveIds.contains(id))
            .toList();
        for (final id in stale) {
          _entryFocusNodes.remove(id)?.dispose();
        }
      },
    );
    final visibleMembers = [for (final pair in visiblePairs) pair.$2];

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: paneScope == null,
        leading: canPopPane
            ? PrismTopBarAction(
                icon: AppIcons.arrowBack,
                tooltip: l10n.back,
                onPressed: paneScope!.popPane,
              )
            : null,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: l10n.edit,
            onPressed: () => _openEditSheet(context),
          ),
          _buildOptionsMenuAction(
            visiblePairs: visiblePairs,
            visibleMembers: visibleMembers,
            terms: terms,
            groupEntries: entries ?? const <MemberGroupEntry>[],
            subGroups: subGroups,
            hasMembers: hasMembers,
            canAddSubGroup: canAddSubGroup,
          ),
        ],
      ),
      topBarMaxWidth: PrismTokens.contentMaxWidth,
      bodyPadding: EdgeInsets.zero,
      body: ClampedBody(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _GroupInfoHeader(group: group, ancestors: ancestors),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: _SubGroupsSection(
                groupId: group.id,
                branch: branch,
                canAddSubGroup: canAddSubGroup,
                onAddSubGroup: () => _addSubGroup(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.peopleOutline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.memberGroupSectionMembers(terms.plural),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _GroupSortBadge(
                      sortMode: group.sortState.mode,
                      onTap: () => _optionsPopupKey.currentState?.show(),
                    ),
                    PrismInlineIconButton(
                      icon: AppIcons.personAddOutlined,
                      tooltip: l10n.memberGroupAddMember(terms.singularLower),
                      size: 32,
                      iconSize: 20,
                      color: theme.colorScheme.primary,
                      onPressed: () => _addMember(context, ref),
                    ),
                  ],
                ),
              ),
            ),
            entriesAsync.when(
              skipLoadingOnReload: true,
              loading: () => const SliverToBoxAdapter(
                child: SizedBox(height: _groupDetailRowsLoadingHeight),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(l10n.memberGroupErrorLoadingDetail(e)),
                ),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: EmptyState(
                        icon: Icon(AppIcons.personAddOutlined),
                        title: l10n.memberGroupNoMembers(terms.pluralLower),
                        subtitle: l10n.memberGroupNoMembersSubtitle(
                          terms.pluralLower,
                        ),
                      ),
                    ),
                  );
                }
                if (providerVisiblePairsInitialLoading) {
                  return const SliverToBoxAdapter(
                    child: SizedBox(height: _groupDetailRowsLoadingHeight),
                  );
                }
                final visiblePairsError = providerVisiblePairsInitialError;
                if (visiblePairsError != null) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.memberGroupErrorLoadingDetail(visiblePairsError),
                      ),
                    ),
                  );
                }
                if (visiblePairs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: EmptyState(
                        icon: Icon(AppIcons.visibilityOffOutlined),
                        title: l10n.memberGroupAllInactiveHiddenTitle,
                        subtitle: l10n.memberGroupAllInactiveHiddenSubtitle(
                          terms.pluralLower,
                        ),
                      ),
                    ),
                  );
                }

                return SliverReorderableList(
                  itemCount: visiblePairs.length,
                  onReorder: (oldIndex, newIndex) {
                    _onReorder(visiblePairs, oldIndex, newIndex);
                  },
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) => Material(
                        elevation: 4,
                        color: Theme.of(context).cardColor,
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
                    final (entry, member) = visiblePairs[index];
                    return _GroupMemberTile(
                      key: ValueKey('member_${entry.id}'),
                      entry: entry,
                      member: member,
                      groupId: group.id,
                      branch: branch,
                      reorderIndex: index,
                      totalCount: visiblePairs.length,
                      sortMode: group.sortState.mode,
                      focusNode: _focusNodeFor(entry.id),
                      onMoveTo: (newIndex) =>
                          _moveTo(visiblePairs, index, newIndex),
                    );
                  },
                );
              },
            ),
            SliverPadding(
              padding: EdgeInsets.only(bottom: NavBarInset.of(context) + 32),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reorder + sort-mode plumbing ───────────────────────────────────────────

  void _clearOptimisticMemberPairsAfterBuild(
    List<_GroupMemberPair> optimisticPairs,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_optimisticMemberPairs.isCurrent(optimisticPairs)) {
        return;
      }
      setState(_optimisticMemberPairs.clear);
    });
  }

  void _onReorder(
    List<(MemberGroupEntry, Member)> pairs,
    int oldIndex,
    int newIndex,
  ) {
    final reordered = reorderedItems(pairs, oldIndex, newIndex);
    if (reordered == null) return;

    setState(() {
      _optimisticMemberPairs.set(reordered);
    });

    final newOrder = [for (final p in reordered) p.$1.id];
    unawaited(_applyManualOrder(newOrder, wasManual: group.sortState.isManual));
  }

  Future<void> _moveTo(
    List<(MemberGroupEntry, Member)> pairs,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = reorderedItems(
      pairs,
      oldIndex,
      newIndex,
      adjustNewIndexForRemoval: false,
    );
    if (reordered == null) return;
    final movedEntryId = pairs[oldIndex].$1.id;

    setState(() {
      _optimisticMemberPairs.set(reordered);
    });

    final newOrder = [for (final p in reordered) p.$1.id];
    await _applyManualOrder(newOrder, wasManual: group.sortState.isManual);
    if (!mounted) return;
    final l10n = context.l10n;
    _announce(l10n.groupSortActionMoved(newIndex + 1, reordered.length));
    // Best-effort focus retention: after the list rebuilds with the new
    // order, request focus on the moved row's node so a screen-reader
    // keeps its caret tracking the moved item. The polite announcement
    // above is the reliable signal; focus is a soft contract because
    // Flutter's focus system doesn't guarantee delivery to non-input
    // widgets and the tile is rebuilt on rebuild. Mark the id as pending
    // so the next paint's post-frame callback fires the request on
    // whichever FocusNode actually exists after the rebuild.
    _pendingFocusEntryId = movedEntryId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingFocusEntryId;
      if (pending == null) return;
      _pendingFocusEntryId = null;
      final node = _entryFocusNodes[pending];
      node?.requestFocus();
    });
  }

  Future<void> _applyManualOrder(
    List<String> newOrder, {
    required bool wasManual,
  }) async {
    Haptics.selection();
    final repo = ref.read(memberGroupsRepositoryProvider);
    final result = await repo.setGroupManualOrderSnapshot(group.id, newOrder);
    if (!mounted) return;
    final l10n = context.l10n;
    if (result is SnapshotRecovered) {
      PrismToast.show(
        context,
        message: l10n.groupSortRecoveredFromConcurrentChanges,
      );
    }
    if (!wasManual) {
      PrismToast.show(context, message: l10n.groupSortSwitchedToManual);
      _announce(l10n.groupSortSwitchedToManualAnnouncement);
    }
  }

  Future<void> _setSortMode(GroupSortMode mode) async {
    final repo = ref.read(memberGroupsRepositoryProvider);
    await repo.setGroupSortMode(group.id, mode);
    Haptics.selection();
  }

  /// Fire a polite screen-reader announcement scoped to the current view.
  /// Wraps the new `SemanticsService.sendAnnouncement` API. Safe to call
  /// without awaiting; returns silently if the view can't be resolved.
  void _announce(String message) {
    if (!mounted) return;
    try {
      final view = View.maybeOf(context);
      if (view == null) return;
      unawaited(
        SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
      );
    } catch (_) {
      // Best-effort — screen-reader hints, not a contract.
    }
  }

  Future<void> _sortManuallyFromCurrent(
    List<(MemberGroupEntry, Member)> pairs,
  ) async {
    final wasManual = group.sortState.isManual;
    final newOrder = [for (final p in pairs) p.$1.id];
    await _applyManualOrder(newOrder, wasManual: wasManual);
  }

  Future<void> _applyFrontingOrder(
    List<(MemberGroupEntry, Member)> pairs, {
    required bool descending,
  }) async {
    final statsMap = await ref.read(allMemberFrontingStatsProvider.future);
    final sorted = [...pairs]
      ..sort((a, b) {
        final ad = statsMap[a.$2.id]?.totalDuration ?? Duration.zero;
        final bd = statsMap[b.$2.id]?.totalDuration ?? Duration.zero;
        return descending ? bd.compareTo(ad) : ad.compareTo(bd);
      });
    final newOrder = [for (final p in sorted) p.$1.id];
    if (!mounted) return;
    await _applyManualOrder(newOrder, wasManual: group.sortState.isManual);
  }

  Future<void> _sortSubGroupsBy(
    List<MemberGroup> subGroups,
    int Function(MemberGroup a, MemberGroup b) compare,
  ) async {
    final sorted = [...subGroups]..sort(compare);
    await ref.read(groupNotifierProvider.notifier).reorderGroups(sorted);
    Haptics.selection();
    if (!mounted) return;
    PrismToast.show(context, message: context.l10n.memberOrderUpdated);
  }

  Future<void> _openMemberSortDialog({
    required List<(MemberGroupEntry, Member)> visiblePairs,
    required Terminology terms,
    required GroupSortMode currentMode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    await PrismDialog.show<void>(
      context: context,
      title: context.l10n.groupSortMembersAction(terms.plural),
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionHeader(
              dialogContext,
              dialogContext.l10n.groupSortSectionKeepSorted,
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.arrowUpward,
              label: dialogContext.l10n.groupSortItemNameAsc,
              isActive: currentMode == GroupSortMode.nameAsc,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_setSortMode(GroupSortMode.nameAsc));
              },
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.arrowDownward,
              label: dialogContext.l10n.groupSortItemNameDesc,
              isActive: currentMode == GroupSortMode.nameDesc,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_setSortMode(GroupSortMode.nameDesc));
              },
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.history,
              label: dialogContext.l10n.groupSortItemRecentDesc,
              isActive: currentMode == GroupSortMode.recentDesc,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_setSortMode(GroupSortMode.recentDesc));
              },
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.dragHandle,
              label: dialogContext.l10n.groupSortItemManual,
              isActive: currentMode == GroupSortMode.manual,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_sortManuallyFromCurrent(visiblePairs));
              },
            ),
            _sectionHeader(
              dialogContext,
              dialogContext.l10n.groupSortSectionApplyCurrent,
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.flashOn,
              label: dialogContext.l10n.groupSortItemFrontingMost,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_applyFrontingOrder(visiblePairs, descending: true));
              },
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.frontHandOutlined,
              label: dialogContext.l10n.groupSortItemFrontingLeast,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_applyFrontingOrder(visiblePairs, descending: false));
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSubGroupSortDialog(List<MemberGroup> subGroups) async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    await PrismDialog.show<void>(
      context: context,
      title: context.l10n.groupSortSubGroupsAction,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.arrowUpward,
              label: dialogContext.l10n.memberSortNameAZ,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  _sortSubGroupsBy(
                    subGroups,
                    (a, b) => _compareText(a.name, b.name, a.id, b.id),
                  ),
                );
              },
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.arrowDownward,
              label: dialogContext.l10n.memberSortNameZA,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  _sortSubGroupsBy(
                    subGroups,
                    (a, b) => _compareText(b.name, a.name, a.id, b.id),
                  ),
                );
              },
            ),
            _sortDialogRow(
              context: dialogContext,
              icon: AppIcons.history,
              label: dialogContext.l10n.memberSortRecentlyCreated,
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(
                  _sortSubGroupsBy(subGroups, (a, b) {
                    final created = b.createdAt.compareTo(a.createdAt);
                    if (created != 0) return created;
                    return a.id.compareTo(b.id);
                  }),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ── Options menu ───────────────────────────────────────────────────────────

  Widget _buildOptionsMenuAction({
    required List<(MemberGroupEntry, Member)> visiblePairs,
    required List<Member> visibleMembers,
    required Terminology terms,
    required List<MemberGroupEntry> groupEntries,
    required List<MemberGroup> subGroups,
    required bool hasMembers,
    required bool canAddSubGroup,
  }) {
    final l10n = context.l10n;
    final canSearch = visibleMembers.isNotEmpty;
    final canSort = visibleMembers.length > 1;
    final currentMode = group.sortState.mode;

    Widget menuItemRow({
      required BuildContext ctx,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool isActive = false,
      bool destructive = false,
      bool enabled = true,
    }) {
      final theme = Theme.of(ctx);
      final iconColor = !enabled
          ? theme.disabledColor
          : destructive
          ? theme.colorScheme.error
          : theme.colorScheme.onSurface;
      return PrismListRow(
        dense: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabled: enabled,
        destructive: destructive,
        leading: Icon(icon, size: 20, color: iconColor),
        title: Text(label, style: theme.textTheme.bodyMedium),
        trailing: isActive
            ? Icon(AppIcons.check, size: 18, color: theme.colorScheme.primary)
            : null,
        onTap: enabled ? onTap : null,
      );
    }

    final entries = <Widget Function(BuildContext, VoidCallback)>[
      (ctx, close) => menuItemRow(
        ctx: ctx,
        icon: AppIcons.search,
        label: ctx.l10n.terminologySearchHint(terms.pluralLower),
        enabled: canSearch,
        onTap: () {
          close();
          _openSearch(visibleMembers);
        },
      ),
      (ctx, close) {
        final showInactive = ref.watch(showInactiveMembersProvider);
        return menuItemRow(
          ctx: ctx,
          icon: AppIcons.visibilityOutlined,
          label: ctx.l10n.memberShowInactive,
          isActive: showInactive,
          onTap: () {
            close();
            ref.read(showInactiveMembersProvider.notifier).set(!showInactive);
          },
        );
      },
    ];

    final canSortSubGroups = subGroups.length > 1;

    if (canSort) {
      entries.addAll([
        (ctx, close) => menuItemRow(
          ctx: ctx,
          icon: AppIcons.sortList,
          label: ctx.l10n.groupSortMembersAction(terms.plural),
          onTap: () {
            close();
            unawaited(
              _openMemberSortDialog(
                visiblePairs: visiblePairs,
                terms: terms,
                currentMode: currentMode,
              ),
            );
          },
        ),
      ]);
    }

    if (canSortSubGroups) {
      entries.addAll([
        (ctx, close) => menuItemRow(
          ctx: ctx,
          icon: AppIcons.folderOutlined,
          label: ctx.l10n.groupSortSubGroupsAction,
          onTap: () {
            close();
            unawaited(_openSubGroupSortDialog(subGroups));
          },
        ),
      ]);
    }

    entries.addAll([
      if (hasMembers) ...[
        (ctx, close) => menuItemRow(
          ctx: ctx,
          icon: Icons.group_outlined,
          label: ctx.l10n.memberGroupFrontGroup,
          onTap: () {
            close();
            unawaited(
              _handleMenuAction(
                context,
                ref,
                _GroupMenuAction.frontGroup,
                groupEntries,
              ),
            );
          },
        ),
        (ctx, close) => menuItemRow(
          ctx: ctx,
          icon: Icons.chat_bubble_outline,
          label: ctx.l10n.memberGroupStartChat,
          onTap: () {
            close();
            unawaited(
              _handleMenuAction(
                context,
                ref,
                _GroupMenuAction.startChat,
                groupEntries,
              ),
            );
          },
        ),
      ],
      if (canAddSubGroup)
        (ctx, close) => menuItemRow(
          ctx: ctx,
          icon: AppIcons.add,
          label: ctx.l10n.memberGroupAddSubGroup,
          onTap: () {
            close();
            unawaited(
              _handleMenuAction(
                context,
                ref,
                _GroupMenuAction.addSubGroup,
                groupEntries,
              ),
            );
          },
        ),
      (ctx, close) => menuItemRow(
        ctx: ctx,
        icon: AppIcons.deleteOutline,
        label: ctx.l10n.delete,
        destructive: true,
        onTap: () {
          close();
          unawaited(
            _handleMenuAction(
              context,
              ref,
              _GroupMenuAction.delete,
              groupEntries,
            ),
          );
        },
      ),
    ]);

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
        onSecondaryTap: () => _optionsPopupKey.currentState?.show(),
      ),
    );
  }

  int _compareText(String left, String right, String leftId, String rightId) {
    final text = left.toLowerCase().compareTo(right.toLowerCase());
    if (text != 0) return text;
    return leftId.compareTo(rightId);
  }

  Widget _sectionHeader(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sortDialogRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final theme = Theme.of(context);
    return PrismListRow(
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      leading: Icon(icon, size: 20),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: isActive
          ? Icon(AppIcons.check, size: 18, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }

  Future<void> _openSearch(List<Member> members) async {
    final terms = readTerminology(context, ref);
    final groups = await _readMemberSearchGroupsForCandidates(members);
    if (!mounted) return;
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      groups: groups,
    );
    if (!mounted) return;
    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        final paneScope = ListDetailPaneScope.maybeOf(context);
        if (paneScope != null) {
          paneScope.selectDetail(memberId);
        } else {
          unawaited(context.push(_memberPathFor(branch, group.id, memberId)));
        }
      case MemberSearchResultDismissed():
      case MemberSearchResultCleared():
      case MemberSearchResultUnknown():
        break;
    }
  }

  void _openEditSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditGroupSheet(
        scrollController: scrollController,
        group: group,
      ),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    _GroupMenuAction action,
    List<MemberGroupEntry> entries,
  ) async {
    switch (action) {
      case _GroupMenuAction.frontGroup:
        await _onFrontGroup(context, ref, group, entries);
      case _GroupMenuAction.startChat:
        _onStartChat(context, entries);
      case _GroupMenuAction.addSubGroup:
        _addSubGroup(context);
      case _GroupMenuAction.delete:
        await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final routeBacked = ListDetailPaneScope.maybeOf(context) == null;
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
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.memberGroupDeleted(group.name),
        );
        closeDetailSurface(context, routeBacked: routeBacked);
      }
    }
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final entries =
        ref.read(groupEntriesProvider(group.id)).whenOrNull(data: (e) => e) ??
        [];
    final existingMemberIds = entries.map((e) => e.memberId).toSet();
    // Non-fronting picker: hide the Unknown sentinel — you don't add the
    // placeholder member to a group.
    final visibleMembers = await _readVisibleActiveMembers(ref);
    if (!context.mounted) return;
    final availableMembers = visibleMembers
        .where((member) => !existingMemberIds.contains(member.id))
        .toList();
    final searchGroups = await _readMemberSearchGroupsForCandidates(
      availableMembers,
    );
    if (!context.mounted) return;

    final selectedIds = await MemberSearchSheet.showMulti(
      context,
      members: availableMembers,
      termPlural: readTerminology(context, ref).plural,
      groups: searchGroups,
    );
    if (!context.mounted || selectedIds == null || selectedIds.isEmpty) return;

    final notifier = ref.read(groupNotifierProvider.notifier);
    for (final memberId in selectedIds) {
      await notifier.addMemberToGroup(group.id, memberId);
    }

    if (!context.mounted) return;
    Haptics.success();
    PrismToast.show(
      context,
      message: context.l10n.memberAdded(readTerminology(context, ref).singular),
    );
  }

  Future<List<MemberSearchGroup>> _readMemberSearchGroupsForCandidates(
    Iterable<Member> members,
  ) async {
    final cachedGroups = ref.read(allGroupsProvider).value;
    final cachedEntries = ref.read(allGroupEntriesProvider).value;
    if (cachedGroups != null && cachedEntries != null) {
      return readMemberSearchGroups(ref, members);
    }

    final repo = ref.read(memberGroupsRepositoryProvider);
    final groups = cachedGroups ?? await repo.getAllGroups();
    final entries = cachedEntries ?? await repo.getAllGroupEntries();
    return buildMemberSearchGroups(
      members: members,
      allGroups: groups,
      allEntries: entries,
      groupTree: GroupTreeUtils.buildGroupTree(
        GroupTreeUtils.resolveSyncCycles(groups),
      ),
    );
  }

  void _addSubGroup(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditGroupSheet(
        scrollController: scrollController,
        initialParentGroupId: group.id,
      ),
    );
  }

  Future<void> _onFrontGroup(
    BuildContext context,
    WidgetRef ref,
    MemberGroup group,
    List<MemberGroupEntry> entries,
  ) async {
    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final memberIds = entries.map((e) => e.memberId).toList();
    if (memberIds.isEmpty) return;

    // Bail if fronting state hasn't loaded yet — collapsing to [] would
    // incorrectly treat everyone as not-fronting and replace the active front.
    final activeSessionsAsync = ref.read(activeSessionsProvider);
    if (!activeSessionsAsync.hasValue) return;
    final activeSessions = activeSessionsAsync.value!;
    // Each session is one member's continuous presence; co-fronting is emergent.
    final alreadyFronting = activeSessions
        .map((s) => s.memberId)
        .whereType<String>()
        .toSet();
    final toAdd = memberIds
        .where((id) => !alreadyFronting.contains(id))
        .toList();

    if (toAdd.isEmpty) {
      // All members already fronting — show a toast instead of a dialog
      if (!context.mounted) return;
      PrismToast.show(
        context,
        message: l10n.memberGroupFrontAllAlreadyFronting(
          terms.pluralLower,
          terms.plural,
        ),
      );
      return;
    }

    final alreadyInGroup = alreadyFronting.intersection(memberIds.toSet());

    if (alreadyInGroup.isNotEmpty) {
      // Some are already fronting — confirm adding the rest
      if (!context.mounted) return;
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: l10n.memberGroupFrontSomeAlreadyFronting(
          alreadyInGroup.length,
          alreadyInGroup.length == 1 ? terms.singularLower : terms.pluralLower,
          toAdd.length,
        ),
      );
      if (!confirmed || !context.mounted) return;
      await ref.read(frontingNotifierProvider.notifier).startFronting(toAdd);
      return;
    }

    // Check if all group members are inactive
    final allMembers =
        ref.read(allMemberListProvider).whenOrNull(data: (m) => m) ?? [];
    final groupMembers = allMembers
        .where((m) => memberIds.contains(m.id))
        .toList();
    final allInactive =
        groupMembers.isNotEmpty && groupMembers.every((m) => !m.isActive);

    if (!context.mounted) return;
    if (allInactive) {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: l10n.memberGroupFrontAllInactive(group.name, terms.pluralLower),
      );
      if (!confirmed || !context.mounted) return;
    } else {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: l10n.memberGroupFrontGroupConfirmTitle(group.name),
        message: toAdd.length > 1
            ? l10n.memberGroupFrontGroupConfirmMessage(
                toAdd.length,
                toAdd.length == 1 ? terms.singularLower : terms.pluralLower,
              )
            : null,
      );
      if (!confirmed || !context.mounted) return;
    }

    // Start a per-member session for each group member not already fronting.
    // Each id in `toAdd` gets its own session row sharing the same start_time.
    await ref.read(frontingNotifierProvider.notifier).startFronting(toAdd);
  }

  void _onStartChat(BuildContext context, List<MemberGroupEntry> entries) {
    final memberIds = entries.map((e) => e.memberId).toList();
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateConversationSheet(
        scrollController: scrollController,
        initialMemberIds: memberIds,
      ),
    );
  }
}

// ── Lock chip ────────────────────────────────────────────────────────────────

/// Right-aligned chip in the Members section header that indicates the active
/// locked sort mode. Hidden in [GroupSortMode.manual] — drag is the only
/// affordance there. Tap opens the options dropdown.
///
/// Wrapped in [Semantics(liveRegion: true)] so VO/TalkBack picks up state
/// transitions (Flutter issue 122101 — `announce` alone is unreliable on
/// iOS: https://github.com/flutter/flutter/issues/122101).
class _GroupSortBadge extends StatelessWidget {
  const _GroupSortBadge({required this.sortMode, required this.onTap});

  final GroupSortMode sortMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isManual = sortMode == GroupSortMode.manual;

    return AnimatedSwitcher(
      duration: Anim.md,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.15),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: isManual
          ? const SizedBox.shrink(key: ValueKey('manual'))
          : Padding(
              key: ValueKey('badge_${sortMode.name}'),
              padding: const EdgeInsets.only(right: 4),
              child: Semantics(
                liveRegion: true,
                button: true,
                label: _labelFor(sortMode, l10n),
                hint: l10n.options,
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(
                    PrismShapes.of(context).radius(10),
                  ),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(10),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.lock,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _labelFor(sortMode, l10n),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              AppIcons.chevronRight,
                              size: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  static String _labelFor(GroupSortMode mode, dynamic l10n) {
    switch (mode) {
      case GroupSortMode.nameAsc:
        return l10n.groupSortBadgeNameAsc as String;
      case GroupSortMode.nameDesc:
        return l10n.groupSortBadgeNameDesc as String;
      case GroupSortMode.recentDesc:
        return l10n.groupSortBadgeRecentDesc as String;
      case GroupSortMode.manual:
        return l10n.groupSortBadgeManual as String;
    }
  }
}

class _GroupInfoHeader extends ConsumerWidget {
  const _GroupInfoHeader({required this.group, required this.ancestors});

  final MemberGroup group;
  final List<MemberGroup> ancestors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;
    final radius = BorderRadius.circular(PrismShapes.of(context).radius(14));
    final showEmojiOnAvatar =
        ref.watch(groupShowEmojiOnAvatarProvider(group.id)).value ?? true;
    final hasAvatar =
        group.avatarImageData != null && group.avatarImageData!.isNotEmpty;
    final leadingVisual = GroupAvatar(
      group: group,
      size: hasAvatar ? 64 : 56,
      showEmojiOnAvatar: showEmojiOnAvatar,
      tintOverride: accentColor,
    );

    final cardColor = hasAvatar && hasColor
        ? accentColor!.withValues(alpha: 0.12)
        : theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return Material(
      color: cardColor,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (hasColor && !hasAvatar)
            Positioned.fill(
              right: null,
              child: Container(width: 4, color: accentColor),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leadingVisual,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ancestors.isNotEmpty) ...[
                        AncestorBreadcrumb(ancestors: ancestors),
                        const SizedBox(height: 2),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          group.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (group.description != null &&
                          group.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        PrismMarkdownText(
                          data: group.description!,
                          enabled: true,
                          baseStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubGroupsSection extends ConsumerStatefulWidget {
  const _SubGroupsSection({
    required this.groupId,
    required this.branch,
    required this.canAddSubGroup,
    required this.onAddSubGroup,
  });

  final String groupId;
  final MemberNavigationBranch branch;
  final bool canAddSubGroup;
  final VoidCallback onAddSubGroup;

  @override
  ConsumerState<_SubGroupsSection> createState() => _SubGroupsSectionState();
}

class _SubGroupsSectionState extends ConsumerState<_SubGroupsSection> {
  final OptimisticListController<MemberGroup, String> _optimisticChildren =
      OptimisticListController<MemberGroup, String>(keyOf: (group) => group.id);

  @override
  void didUpdateWidget(covariant _SubGroupsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) {
      _optimisticChildren.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final providerChildren = ref.watch(childGroupsProvider(widget.groupId));
    final optimisticChildren = _optimisticChildren.items;
    final children = _optimisticChildren.displayItems(providerChildren);

    if (_optimisticChildren.shouldClearFor(providerChildren)) {
      _clearOptimisticChildrenAfterBuild(optimisticChildren!);
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Icon(
                AppIcons.folderOutlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.memberGroupSubGroupsLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.canAddSubGroup)
                PrismInlineIconButton(
                  icon: AppIcons.add,
                  tooltip: l10n.memberGroupAddSubGroup,
                  size: 32,
                  iconSize: 20,
                  color: theme.colorScheme.primary,
                  onPressed: widget.onAddSubGroup,
                ),
            ],
          ),
        ),
        if (children.isNotEmpty) _buildChildrenList(context, ref, children),
        const SizedBox(height: 20),
      ],
    );
  }

  void _clearOptimisticChildrenAfterBuild(List<MemberGroup> current) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_optimisticChildren.isCurrent(current)) return;
      setState(_optimisticChildren.clear);
    });
  }

  // Inline drag-reorder for sub-groups (plan §Task 5.2). When the list has
  // 2+ children we use ReorderableListView; with a single child we fall back
  // to a plain ListView (no drag handle).
  Widget _buildChildrenList(
    BuildContext context,
    WidgetRef ref,
    List<MemberGroup> children,
  ) {
    if (children.length < 2) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: children.length,
        itemBuilder: (context, index) =>
            _buildChildRow(context, ref, children[index]),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: children.length,
      onReorder: (oldIndex, newIndex) {
        final reordered = reorderedItems(children, oldIndex, newIndex);
        if (reordered == null) return;
        setState(() => _optimisticChildren.set(reordered));
        Haptics.selection();
        unawaited(
          ref.read(groupNotifierProvider.notifier).reorderGroups(reordered),
        );
      },
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(12),
          ),
          child: child,
        ),
        child: child,
      ),
      itemBuilder: (context, index) {
        final group = children[index];
        return _buildChildRow(context, ref, group, reorderIndex: index);
      },
    );
  }

  Widget _buildChildRow(
    BuildContext context,
    WidgetRef ref,
    MemberGroup group, {
    int? reorderIndex,
  }) {
    final count = ref.watch(
      groupMemberCountsProvider.select((m) => m[group.id] ?? 0),
    );
    final hideMemberCounts =
        ref
            .watch(hideMemberCountsProvider)
            .whenOrNull(data: (value) => value) ??
        true;
    final paneScope = ListDetailPaneScope.maybeOf(context);
    return MemberGroupRow(
      key: ValueKey('subgroup_${group.id}'),
      group: group,
      memberCount: count,
      showMemberCount: !hideMemberCounts,
      reorderIndex: reorderIndex,
      onTap: () {
        if (paneScope != null) {
          paneScope.openInPane(group.id);
        } else {
          context.push(widget.branch.groupPath(group.id));
        }
      },
    );
  }
}

class _GroupMemberTile extends ConsumerWidget {
  const _GroupMemberTile({
    super.key,
    required this.entry,
    required this.member,
    required this.groupId,
    required this.branch,
    required this.reorderIndex,
    required this.totalCount,
    required this.sortMode,
    required this.focusNode,
    required this.onMoveTo,
  });

  final MemberGroupEntry entry;
  final Member member;
  final String groupId;
  final MemberNavigationBranch branch;
  final int reorderIndex;
  final int totalCount;
  final GroupSortMode sortMode;

  /// Per-entry focus node owned by the parent state. After a custom-action
  /// reorder, the parent requests focus on this node so screen-reader
  /// caret tracking follows the moved row. Best-effort — see
  /// `_GroupDetailBodyState._moveTo` for the rationale.
  final FocusNode focusNode;
  final Future<void> Function(int newIndex) onMoveTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isManual = sortMode == GroupSortMode.manual;

    return Focus(
      key: ValueKey('member_focus_${entry.id}'),
      focusNode: focusNode,
      child: Semantics(
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          if (reorderIndex > 0)
            CustomSemanticsAction(label: l10n.groupSortActionMoveUp): () =>
                unawaited(onMoveTo(reorderIndex - 1)),
          if (reorderIndex < totalCount - 1)
            CustomSemanticsAction(label: l10n.groupSortActionMoveDown): () =>
                unawaited(onMoveTo(reorderIndex + 1)),
          if (reorderIndex > 0)
            CustomSemanticsAction(label: l10n.groupSortActionMoveToTop): () =>
                unawaited(onMoveTo(0)),
          if (reorderIndex < totalCount - 1)
            CustomSemanticsAction(
              label: l10n.groupSortActionMoveToBottom,
            ): () =>
                unawaited(onMoveTo(totalCount - 1)),
        },
        child: Dismissible(
          key: ValueKey('member_dismiss_${entry.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: theme.colorScheme.error,
            child: Icon(
              AppIcons.removeCircleOutline,
              color: theme.colorScheme.onError,
            ),
          ),
          confirmDismiss: (_) => _confirmRemove(context, ref, member),
          child: MemberCard(
            member: member,
            deferAvatarLookup: true,
            reorderIndex: reorderIndex,
            dragHandleHint: isManual
                ? l10n.groupMemberDragHandleHintManual
                : l10n.groupMemberDragHandleHintSorted,
            selected:
                ListDetailPaneScope.maybeOf(context)?.selectedDetailId ==
                member.id,
            onTap: () {
              final paneScope = ListDetailPaneScope.maybeOf(context);
              if (paneScope != null) {
                paneScope.selectDetail(member.id);
              } else {
                context.push(_memberPathFor(branch, groupId, member.id));
              }
            },
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) async {
    final l10n = context.l10n;
    final terms = readTerminology(context, ref);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.memberRemoveFromGroupTitle(terms.singular),
      message: l10n.memberRemoveFromGroupMessage(
        member.name,
        terms.singularLower,
      ),
      confirmLabel: l10n.confirm,
      destructive: true,
    );
    if (confirmed) {
      Haptics.selection();
      unawaited(
        ref
            .read(groupNotifierProvider.notifier)
            .removeMemberFromGroup(groupId, entry.memberId),
      );
      if (context.mounted) {
        PrismToast.show(
          context,
          message: context.l10n.memberRemoved(member.name),
        );
      }
    }
    return false; // Don't auto-dismiss; provider stream will update
  }
}

Future<List<Member>> _readVisibleActiveMembers(WidgetRef ref) async {
  final cached = ref.read(userVisibleMemberListProvider).value;
  if (cached != null) return cached;

  final completer = Completer<List<Member>>();
  final subscription = ref.listenManual<AsyncValue<List<Member>>>(
    activeMemberListProvider,
    (_, next) {
      if (completer.isCompleted) return;
      if (next.hasValue) {
        final members = next.requireValue
            .where((member) => member.id != unknownSentinelMemberId)
            .toList();
        completer.complete(members);
      } else if (next.hasError) {
        completer.completeError(
          next.error ?? StateError('Failed to load members'),
          next.stackTrace ?? StackTrace.current,
        );
      }
    },
    fireImmediately: true,
  );

  try {
    return await completer.future;
  } finally {
    subscription.close();
  }
}

enum _GroupMenuAction { frontGroup, startChat, addSubGroup, delete }

List<MemberGroup> _resolveAncestors(MemberGroup group, List<MemberGroup> all) {
  const maxWalk = 64;
  final byId = {for (final g in all) g.id: g};
  final chain = <MemberGroup>[];
  final visited = <String>{group.id};
  String? cur = group.parentGroupId;
  for (int i = 0; i < maxWalk && cur != null && !visited.contains(cur); i++) {
    final parent = byId[cur];
    if (parent == null) break;
    chain.insert(0, parent);
    visited.add(cur);
    cur = parent.parentGroupId;
  }
  return chain;
}

@visibleForTesting
class AncestorBreadcrumb extends StatelessWidget {
  const AncestorBreadcrumb({super.key, required this.ancestors});

  final List<MemberGroup> ancestors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final separatorColor = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.5,
    );

    // Front-truncate when the chain is longer than 5:
    // render [first, ellipsis, ...last 3].
    final visible = ancestors.length <= 5
        ? ancestors
        : [ancestors.first, ...ancestors.sublist(ancestors.length - 3)];
    final showEllipsis = ancestors.length > 5;

    Widget buildAncestorChip(MemberGroup ancestor) {
      final parts = <Widget>[];
      if (ancestor.emoji != null && ancestor.emoji!.isNotEmpty) {
        parts.add(Text(ancestor.emoji!, style: const TextStyle(fontSize: 12)));
        parts.add(const SizedBox(width: 4));
      }
      parts.add(
        Text(
          ancestor.name,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      return Row(mainAxisSize: MainAxisSize.min, children: parts);
    }

    Widget buildSeparator() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        Icon(AppIcons.chevronRight, size: 12, color: separatorColor),
        const SizedBox(width: 6),
      ],
    );

    final children = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      children.add(buildAncestorChip(visible[i]));

      if (showEllipsis && i == 0) {
        // Insert ellipsis marker after the first ancestor.
        children.add(buildSeparator());
        children.add(Text('…', style: style));
      }

      if (i < visible.length - 1) {
        children.add(buildSeparator());
      }
    }
    // Trailing chevron after the last ancestor (matches original behaviour).
    children.add(const SizedBox(width: 6));
    children.add(Icon(AppIcons.chevronRight, size: 12, color: separatorColor));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
