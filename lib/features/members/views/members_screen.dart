import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/widgets/member_group_filter_bar.dart';
import 'package:prism_plurality/features/members/widgets/group_section_header.dart';
import 'package:prism_plurality/features/members/widgets/manage_groups_sheet.dart';
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
import 'package:prism_plurality/features/members/widgets/member_list_view_settings_sheet.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/optimistic_list_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

const _kMembersViewSettingsBannerSeenKey =
    'prism.members.view_settings_banner_seen';

String _memberOptimisticKey(Member member) => member.id;

enum _MemberDetailPaneMode { detail, edit }

class _MemberTilePrefs {
  const _MemberTilePrefs({
    required this.showPronouns,
    required this.showFrontButtons,
    required this.frontButtonBehavior,
    required this.frontingActionBusy,
  });

  final bool showPronouns;
  final bool showFrontButtons;
  final FrontStartBehavior frontButtonBehavior;
  final bool frontingActionBusy;
}

/// Main member list screen.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({
    super.key,
    this.showBackButton = true,
    this.branch = MemberNavigationBranch.settings,
  });

  final bool showBackButton;
  final MemberNavigationBranch branch;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen>
    with ListDetailSelectionState<MembersScreen> {
  bool? _viewSettingsBannerSeen;
  _MemberDetailPaneMode _detailPaneMode = _MemberDetailPaneMode.detail;
  final List<String> _paneGroupStack = [];
  final AddEditMemberSheetController _editMemberController =
      AddEditMemberSheetController();

  // Section keys for scroll-to-section navigation in the grouped list.
  final Map<String, GlobalKey> _sectionKeys = {};
  final GlobalKey _ungroupedKey = GlobalKey();
  final GlobalKey<BlurPopupAnchorState> _optionsPopupKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final OptimisticListController<Member, String> _optimisticMembers =
      OptimisticListController<Member, String>(keyOf: _memberOptimisticKey);

  @override
  void initState() {
    super.initState();
    unawaited(_loadViewSettingsBannerSeen());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadViewSettingsBannerSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _viewSettingsBannerSeen =
          prefs.getBool(_kMembersViewSettingsBannerSeenKey) ?? false;
    });
  }

  Future<void> _markViewSettingsBannerSeen() async {
    if (mounted && _viewSettingsBannerSeen != true) {
      setState(() => _viewSettingsBannerSeen = true);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMembersViewSettingsBannerSeenKey, true);
    } catch (_) {
      // Hint persistence should not block opening settings.
    }
  }

  String _memberPath(String id) => widget.branch.memberPath(id);

  String _groupPath(String id) => widget.branch.groupPath(id);

  int get _shellBranchIndex => switch (widget.branch) {
    MemberNavigationBranch.settings => appShellBranchIndex(
      AppShellTabId.settings,
    ),
    MemberNavigationBranch.members => appShellBranchIndex(
      AppShellTabId.members,
    ),
    MemberNavigationBranch.groups => appShellBranchIndex(AppShellTabId.groups),
  };

  Widget _buildOptionsMenuAction(
    List<Member>? members,
    Terminology terms,
    bool showInactive,
  ) {
    final l10n = context.l10n;
    final availableMembers = members ?? const <Member>[];
    final canSearch = availableMembers.isNotEmpty;

    final entries = <Widget Function(BuildContext, VoidCallback)>[
      (ctx, close) {
        final theme = Theme.of(ctx);
        final ctxL10n = ctx.l10n;
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          leading: Icon(AppIcons.search, size: 20),
          title: Text(
            ctxL10n.terminologySearchHint(terms.pluralLower),
            style: theme.textTheme.bodyMedium,
          ),
          enabled: canSearch,
          onTap: canSearch
              ? () {
                  close();
                  _openSearch(availableMembers);
                }
              : null,
        );
      },
      (ctx, close) {
        final theme = Theme.of(ctx);
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          leading: Icon(AppIcons.visibilityOutlined, size: 20),
          title: Text(
            ctx.l10n.memberShowInactive,
            style: theme.textTheme.bodyMedium,
          ),
          trailing: showInactive
              ? Icon(AppIcons.check, size: 18, color: theme.colorScheme.primary)
              : null,
          onTap: () {
            close();
            ref.read(showInactiveMembersProvider.notifier).set(!showInactive);
          },
        );
      },
      (ctx, close) {
        final theme = Theme.of(ctx);
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          leading: Icon(AppIcons.tuneOutlined, size: 20),
          title: Text(
            ctx.l10n.memberListViewSettingsTitle,
            style: theme.textTheme.bodyMedium,
          ),
          onTap: () {
            close();
            unawaited(_openViewSettingsSheet());
          },
        );
      },
    ];

    if (availableMembers.length > 1) {
      entries.addAll([
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
            _reorderBy(
              availableMembers,
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          },
        ),
        (ctx, close) => _buildSortMenuRow(
          context: ctx,
          icon: AppIcons.arrowDownward,
          label: ctx.l10n.memberSortNameZA,
          onTap: () {
            close();
            _reorderBy(
              availableMembers,
              (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
            );
          },
        ),
        (ctx, close) => _buildSortMenuRow(
          context: ctx,
          icon: AppIcons.history,
          label: ctx.l10n.memberSortRecentlyCreated,
          onTap: () {
            close();
            _reorderBy(
              availableMembers,
              (a, b) => b.createdAt.compareTo(a.createdAt),
            );
          },
        ),
        (ctx, close) => _buildSortMenuRow(
          context: ctx,
          icon: AppIcons.flashOn,
          label: ctx.l10n.memberSortMostFronting,
          onTap: () {
            close();
            _reorderByFronting(availableMembers, descending: true);
          },
        ),
        (ctx, close) => _buildSortMenuRow(
          context: ctx,
          icon: AppIcons.frontHandOutlined,
          label: ctx.l10n.memberSortLeastFronting,
          onTap: () {
            close();
            _reorderByFronting(availableMembers, descending: false);
          },
        ),
      ]);
    }

    return BlurPopupAnchor(
      key: _optionsPopupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: BlurPopupDirection.down,
      width: 240,
      maxHeight: 384,
      itemCount: entries.length,
      semanticLabel: l10n.options,
      itemBuilder: (ctx, index, close) => entries[index](ctx, close),
      child: PrismTopBarAction(
        icon: AppIcons.moreVert,
        tooltip: l10n.options,
        onPressed: () => _optionsPopupKey.currentState?.show(),
        onSecondaryTap: () => _optionsPopupKey.currentState?.show(),
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

  void _openAddSheet() {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          AddEditMemberSheet(scrollController: scrollController),
    );
  }

  Future<void> _openViewSettingsSheet() async {
    await _markViewSettingsBannerSeen();
    if (!mounted) return;
    await PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          MemberListViewSettingsSheet(scrollController: scrollController),
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
        unawaited(context.push(_memberPath(memberId)));
      case MemberSearchResultDismissed():
      case MemberSearchResultCleared():
      case MemberSearchResultUnknown():
        break;
    }
  }

  bool _shouldShowViewSettingsBanner({
    required MembersListViewMode viewMode,
    required MembersGroupedDefaultState groupedDefault,
    required MembersFolderMemberVisibility folderVisibility,
    required bool showPronouns,
    required bool showFrontButtons,
    required FrontStartBehavior frontButtonBehavior,
  }) {
    if (_viewSettingsBannerSeen != false) return false;
    final unchangedRowPrefs =
        showPronouns &&
        !showFrontButtons &&
        frontButtonBehavior == FrontStartBehavior.additive;
    final oldDefaultLayout =
        viewMode == MembersListViewMode.groupedSections &&
        groupedDefault == MembersGroupedDefaultState.open &&
        folderVisibility == MembersFolderMemberVisibility.allMembers;
    final newDefaultLayout =
        viewMode == MembersListViewMode.folders &&
        folderVisibility == MembersFolderMemberVisibility.allMembers;
    return unchangedRowPrefs && (oldDefaultLayout || newDefaultLayout);
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

  List<Member> _displayMembers(List<Member> providerMembers) {
    final optimisticMembers = _optimisticMembers.items;
    if (optimisticMembers == null) return providerMembers;

    if (!sameItemSet(
      providerMembers,
      optimisticMembers,
      keyOf: _memberOptimisticKey,
    )) {
      _optimisticMembers.clear();
      return providerMembers;
    }

    if (sameItemOrder(
      providerMembers,
      optimisticMembers,
      keyOf: _memberOptimisticKey,
    )) {
      _clearOptimisticMembersAfterBuild(optimisticMembers);
    }

    return optimisticMembers;
  }

  void _setOptimisticMembers(List<Member> members) {
    setState(() {
      _optimisticMembers.set(members);
    });
  }

  void _clearOptimisticMembersAfterBuild(List<Member> optimisticMembers) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_optimisticMembers.isCurrent(optimisticMembers)) {
        return;
      }
      setState(_optimisticMembers.clear);
    });
  }

  void _toggleMemberActive(Member member) {
    final newActive = !member.isActive;
    unawaited(
      ref.read(memberRepositoryProvider).updateMemberFields(member.id, {
        'is_active': newActive,
      }),
    );
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
    _setOptimisticMembers(sorted);
    unawaited(
      ref.read(membersNotifierProvider.notifier).reorderMembers(sorted),
    );
    Haptics.selection();
    _scrollToTop();
    if (mounted) {
      PrismToast.show(context, message: context.l10n.memberOrderUpdated);
    }
  }

  Future<void> _reorderByFronting(
    List<Member> members, {
    required bool descending,
  }) async {
    final statsMap = await ref.read(allMemberFrontingStatsProvider.future);
    final sorted = [...members]
      ..sort((a, b) {
        final aDuration = statsMap[a.id]?.totalDuration ?? Duration.zero;
        final bDuration = statsMap[b.id]?.totalDuration ?? Duration.zero;
        return descending
            ? bDuration.compareTo(aDuration)
            : aDuration.compareTo(bDuration);
      });
    if (!mounted) return;
    _setOptimisticMembers(sorted);
    unawaited(
      ref.read(membersNotifierProvider.notifier).reorderMembers(sorted),
    );
    Haptics.selection();
    _scrollToTop();
    if (mounted) {
      PrismToast.show(context, message: context.l10n.memberOrderUpdated);
    }
  }

  // Sort actions reorder the underlying list, but Flutter preserves the inner
  // scroll offset across the rebuild — so a user scrolled mid-list stays at
  // the same offset with the new top row hidden behind the pinned top bar.
  void _scrollToTop() {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _onReorder(List<Member> members, int oldIndex, int newIndex) {
    final reordered = reorderedItems(members, oldIndex, newIndex);
    if (reordered == null) return;
    _setOptimisticMembers(reordered);
    unawaited(
      ref.read(membersNotifierProvider.notifier).reorderMembers(reordered),
    );
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
    ref.listen<TabSelectionEvent?>(tabSelectionProvider, (_, next) {
      if (next?.branchIndex != _shellBranchIndex) return;
      _resetPaneForTabSelection();
    });

    // Member-list screen is user-facing — hide the Unknown sentinel from both
    // the active and "show inactive" views. Sentinel still resolves for any
    // session that points at it via the unfiltered providers used elsewhere.
    final showInactive = ref.watch(showInactiveMembersProvider);
    final membersAsync = showInactive
        ? ref.watch(userVisibleAllMemberListProvider)
        : ref.watch(userVisibleMemberListProvider);
    final menuMembers = membersAsync.value == null
        ? null
        : _displayMembers(membersAsync.value!);
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
    final viewMode = ref.watch(membersListViewModeProvider);
    final groupedDefault = ref.watch(membersGroupedDefaultStateProvider);
    final folderVisibility = ref.watch(membersFolderMemberVisibilityProvider);
    final showPronouns = ref.watch(membersShowPronounsProvider);
    final showFrontButtons = ref.watch(membersShowFrontButtonsProvider);
    final frontButtonBehavior = ref.watch(membersFrontButtonBehaviorProvider);
    final frontingActionBusy = ref.watch(frontingNotifierProvider).isLoading;
    final memberTilePrefs = _MemberTilePrefs(
      showPronouns: showPronouns,
      showFrontButtons: showFrontButtons,
      frontButtonBehavior: frontButtonBehavior,
      frontingActionBusy: frontingActionBusy,
    );
    final showGroups = ref.watch(membersShowGroupsProvider);
    final showGroupedSections = viewMode == MembersListViewMode.groupedSections;
    final showViewSettingsBanner = _shouldShowViewSettingsBanner(
      viewMode: viewMode,
      groupedDefault: groupedDefault,
      folderVisibility: folderVisibility,
      showPronouns: showPronouns,
      showFrontButtons: showFrontButtons,
      frontButtonBehavior: frontButtonBehavior,
    );

    return ListDetailLayout(
      onClearSelection: _detailPaneMode == _MemberDetailPaneMode.edit
          ? null
          : _clearDetailPane,
      onSelectDetail: _openMemberInDetailPane,
      detail: (context) => _buildDetailPane(terms, membersAsync, showInactive),
      list: (context, isWide) {
        setListDetailWide(isWide);
        if (isWide && _paneGroupStack.isNotEmpty) {
          return _listPane(
            levelKey: 'group_${_paneGroupStack.last}',
            child: GroupDetailScreen(
              key: ValueKey('pane_group_${_paneGroupStack.last}'),
              groupId: _paneGroupStack.last,
              branch: widget.branch,
            ),
          );
        }
        return _listPane(
          levelKey: '__root__',
          child: PrismPageScaffold(
            topBar: PrismTopBar(
              title: terms.plural,
              showBackButton: widget.showBackButton,
              actions: [
                PrismTopBarAction(
                  icon: AppIcons.add,
                  tooltip: context.l10n.terminologyAddButton(terms.singular),
                  onPressed: _openAddSheet,
                ),
                _buildOptionsMenuAction(menuMembers, terms, showInactive),
              ],
            ),
            bodyPadding: EdgeInsets.zero,
            body: Column(
              children: [
                if (showViewSettingsBanner)
                  _MemberViewSettingsBanner(
                    terms: terms,
                    onOpenSettings: () => unawaited(_openViewSettingsSheet()),
                    onDismiss: () => unawaited(_markViewSettingsBannerSeen()),
                  ),
                if (showGroupedSections && showGroups)
                  MemberGroupFilterBar(
                    onChipTap: hasGroups ? _scrollToGroup : null,
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Anim.md,
                    child: KeyedSubtree(
                      key: ValueKey((viewMode, showGroups)),
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
                          final members = _displayMembers(rawMembers);
                          if (members.isEmpty) {
                            return EmptyState(
                              icon: Icon(AppIcons.peopleOutline),
                              title: showInactive
                                  ? context.l10n.terminologyEmptyTitle(
                                      terms.pluralLower,
                                    )
                                  : context.l10n.terminologyEmptyActiveTitle(
                                      terms.pluralLower,
                                    ),
                              subtitle: context.l10n
                                  .terminologyAddFirstSubtitle(
                                    terms.singularLower,
                                  ),
                              actionLabel: context.l10n.terminologyAddButton(
                                terms.singular,
                              ),
                              onAction: _openAddSheet,
                            );
                          }

                          if (!hasGroups || !showGroups) {
                            return _buildFlatList(
                              members,
                              frontingIds,
                              memberTilePrefs,
                            );
                          }

                          if (viewMode == MembersListViewMode.folders) {
                            return _buildFolderList(
                              members,
                              frontingIds,
                              memberTilePrefs,
                            );
                          }

                          final groupedItems = ref.watch(
                            groupedMemberListProvider,
                          );
                          final counts = ref.watch(groupMemberCountsProvider);
                          return _buildGroupedList(
                            groupedItems,
                            counts,
                            frontingIds,
                            memberTilePrefs,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds a list-pane level: a directional drill-down animation around the
  /// content, all under the pane scope. [levelKey] must change per drill level
  /// so the animation can tell levels apart.
  Widget _listPane({required String levelKey, required Widget child}) {
    return _wrapListPane(
      PaneNavigationSwitcher(
        depth: _paneGroupStack.length,
        child: KeyedSubtree(key: ValueKey(levelKey), child: child),
      ),
    );
  }

  Widget _wrapListPane(Widget child) {
    if (!isDetailPaneVisible) return child;
    final hasPaneBackAction =
        _detailPaneMode == _MemberDetailPaneMode.edit ||
        _paneGroupStack.isNotEmpty ||
        selectedDetailId != null;
    return PopScope<void>(
      canPop: !hasPaneBackAction,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handlePaneBack());
      },
      child: ListDetailPaneScope(
        selectDetail: (id) => _selectMember(id, navigate: () {}),
        openInPane: _openGroupInPane,
        popPane: _popGroupPane,
        canPopPane: _paneGroupStack.isNotEmpty,
        selectedDetailId: selectedDetailId,
        child: child,
      ),
    );
  }

  void _openGroupInPane(String id) => setState(() => _paneGroupStack.add(id));

  void _popGroupPane() {
    if (_paneGroupStack.isEmpty) return;
    _paneGroupStack.removeLast();
    setState(() {});
  }

  Future<void> _handlePaneBack() async {
    if (_detailPaneMode == _MemberDetailPaneMode.edit) {
      final shouldClose = await _editMemberController.confirmDiscardIfNeeded();
      if (!shouldClose || !mounted) return;
      _closeEditPane();
      return;
    }
    if (_paneGroupStack.isNotEmpty) {
      _popGroupPane();
      return;
    }
    if (selectedDetailId != null) {
      _clearDetailPane();
    }
  }

  void _resetPaneForTabSelection() {
    if (_detailPaneMode == _MemberDetailPaneMode.edit) return;
    if (_paneGroupStack.isEmpty && selectedDetailId == null) {
      return;
    }
    setState(() {
      _paneGroupStack.clear();
      selectedDetailId = null;
      _detailPaneMode = _MemberDetailPaneMode.detail;
    });
  }

  void _selectMember(String id, {required VoidCallback navigate}) {
    if (_detailPaneMode == _MemberDetailPaneMode.edit) return;
    if (isDetailPaneVisible) {
      setState(() {
        selectedDetailId = selectedDetailId == id ? null : id;
        _detailPaneMode = _MemberDetailPaneMode.detail;
      });
    } else {
      navigate();
    }
  }

  void _clearDetailPane() {
    _detailPaneMode = _MemberDetailPaneMode.detail;
    clearDetailSelection();
  }

  void _openEditInPane(String memberId) {
    if (!isDetailPaneVisible) return;
    setState(() {
      selectedDetailId = memberId;
      _detailPaneMode = _MemberDetailPaneMode.edit;
    });
  }

  void _openMemberInDetailPane(String memberId) {
    if (!isDetailPaneVisible) return;
    setState(() {
      selectedDetailId = memberId;
      _detailPaneMode = _MemberDetailPaneMode.detail;
    });
  }

  void _closeEditPane() {
    if (!isDetailPaneVisible) return;
    setState(() => _detailPaneMode = _MemberDetailPaneMode.detail);
  }

  void _openGroup(String id) {
    if (isDetailPaneVisible) {
      _openGroupInPane(id);
    } else {
      unawaited(context.push(_groupPath(id)));
    }
  }

  /// Wide-layout member detail pane.
  Widget _buildDetailPane(
    Terminology terms,
    AsyncValue<List<Member>> membersAsync,
    bool showInactive,
  ) {
    final id = selectedDetailId;
    if (id == null) {
      return membersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (_, _) => Center(child: Text(context.l10n.error)),
        data: (members) => members.isEmpty
            ? EmptyState(
                icon: Icon(AppIcons.peopleOutline),
                title: showInactive
                    ? context.l10n.terminologyEmptyTitle(terms.pluralLower)
                    : context.l10n.terminologyEmptyActiveTitle(
                        terms.pluralLower,
                      ),
                subtitle: context.l10n.terminologyAddFirstSubtitle(
                  terms.singularLower,
                ),
              )
            : EmptyState(
                icon: Icon(AppIcons.peopleOutline),
                title: context.l10n.memberSelectDetailPaneEmptyTitle(
                  terms.singularLower,
                ),
                subtitle: context.l10n.memberSelectDetailPaneEmptySubtitle(
                  terms.singularLower,
                ),
              ),
      );
    }
    if (_detailPaneMode == _MemberDetailPaneMode.edit) {
      final memberAsync = ref.watch(activeMemberByIdProvider(id));
      return memberAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.terminologyLoadError(
                terms.singularLower,
                e.toString(),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (member) {
          if (member == null) {
            return EmptyState(
              icon: Icon(AppIcons.peopleOutline),
              title: context.l10n.terminologyEmptyTitle(terms.singularLower),
              subtitle: '${terms.singular} not found',
            );
          }
          return Material(
            child: AddEditMemberSheet(
              key: ValueKey('edit_${member.id}'),
              member: member,
              controller: _editMemberController,
              embedded: true,
              onCancel: _closeEditPane,
              onSaved: (_) => _closeEditPane(),
            ),
          );
        },
      );
    }
    // ListDetailLayout isolates this pane's NestedScrollView for us.
    return MemberDetailScreen(
      key: ValueKey(id),
      memberId: id,
      branch: widget.branch,
      showBackButton: false,
      onEdit: () => _openEditInPane(id),
    );
  }

  Widget _buildFolderList(
    List<Member> members,
    Set<String> frontingIds,
    _MemberTilePrefs memberTilePrefs,
  ) {
    final terms = watchTerminology(context, ref);
    final rootGroups = ref.watch(childGroupsProvider(null));
    final counts = ref.watch(groupMemberCountsProvider);
    final hideMemberCounts =
        ref
            .watch(hideMemberCountsProvider)
            .whenOrNull(data: (value) => value) ??
        true;
    final entries = ref.watch(allGroupEntriesProvider).value ?? [];
    final visibility = ref.watch(membersFolderMemberVisibilityProvider);
    final groupedMemberIds = entries.map((entry) => entry.memberId).toSet();
    final visibleMembers =
        visibility == MembersFolderMemberVisibility.ungroupedOnly
        ? members
              .where((member) => !groupedMemberIds.contains(member.id))
              .toList()
        : members;
    final memberSectionExtraCount = visibleMembers.isEmpty ? 0 : 2;
    final childCount =
        rootGroups.length + memberSectionExtraCount + visibleMembers.length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 4, bottom: NavBarInset.of(context)),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index < rootGroups.length) {
                final group = rootGroups[index];
                return MemberGroupRow(
                  key: ValueKey('folder_${group.id}'),
                  group: group,
                  memberCount: counts[group.id] ?? 0,
                  showMemberCount: !hideMemberCounts,
                  onTap: () => _openGroup(group.id),
                );
              }

              final memberSectionIndex = index - rootGroups.length;
              if (visibleMembers.isNotEmpty && memberSectionIndex == 0) {
                return const Divider(height: 24, indent: 16, endIndent: 16);
              }
              if (visibleMembers.isNotEmpty && memberSectionIndex == 1) {
                return _MemberListSectionHeader(
                  label:
                      visibility == MembersFolderMemberVisibility.ungroupedOnly
                      ? context.l10n.memberGroupFilterUngrouped
                      : terms.plural,
                );
              }

              final memberIndex = memberSectionIndex - memberSectionExtraCount;
              final member = visibleMembers[memberIndex];
              return _buildMemberTile(
                member,
                frontingIds.contains(member.id),
                memberTilePrefs,
              );
            }, childCount: childCount),
          ),
        ),
      ],
    );
  }

  Widget _buildFlatList(
    List<Member> members,
    Set<String> frontingIds,
    _MemberTilePrefs memberTilePrefs,
  ) {
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
        final member = members[index];
        final isFronting = frontingIds.contains(member.id);
        return _buildMemberTile(
          member,
          isFronting,
          memberTilePrefs,
          reorderIndex: index,
        );
      },
    );
  }

  Widget _buildGroupedList(
    List<GroupedMemberListItem> items,
    Map<String, int> counts,
    Set<String> frontingIds,
    _MemberTilePrefs memberTilePrefs,
  ) {
    final tree = ref.watch(groupTreeProvider);
    final hideMemberCounts =
        ref
            .watch(hideMemberCountsProvider)
            .whenOrNull(data: (value) => value) ??
        true;
    final itemIndexes = <Key, int>{
      for (var i = 0; i < items.length; i++) _keyForGroupedItem(items[i]): i,
    };
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 4, bottom: NavBarInset.of(context)),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final itemKey = _keyForGroupedItem(item);
                if (item is GroupSectionItem) {
                  final key = _sectionKeys.putIfAbsent(
                    item.group.id,
                    GlobalKey.new,
                  );
                  final header = GroupSectionHeader(
                    key: key,
                    group: item.group,
                    depth: item.depth.clamp(0, kSectionsVisualDepthCap),
                    memberCount: counts[item.group.id] ?? 0,
                    showMemberCount: !hideMemberCounts,
                    isCollapsed: item.isCollapsed,
                    canCollapse: true,
                    onToggle: () => ref
                        .read(collapsedGroupsProvider.notifier)
                        .toggle(item.group.id),
                    hasDeeperDescendants:
                        item.depth >= kSectionsVisualDepthCap &&
                        (tree[item.group.id]?.isNotEmpty ?? false),
                    onOpenDetail: () => _openGroup(item.group.id),
                  );
                  if (item.depth == 0 && index > 0) {
                    return Column(
                      key: itemKey,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        const SizedBox(height: 4),
                        header,
                      ],
                    );
                  }
                  return KeyedSubtree(key: itemKey, child: header);
                }
                if (item is UngroupedSectionItem) {
                  return KeyedSubtree(
                    key: itemKey,
                    child: GroupSectionHeader(
                      key: _ungroupedKey,
                      group: null,
                      depth: 0,
                      memberCount: item.memberCount,
                      showMemberCount: !hideMemberCounts,
                      isCollapsed: false,
                      canCollapse: false,
                      onToggle: null,
                    ),
                  );
                }
                if (item is MemberRowItem) {
                  final isFronting = frontingIds.contains(item.member.id);
                  final indent =
                      item.depth.clamp(0, kSectionsVisualDepthCap) * 8.0;
                  return Padding(
                    key: itemKey,
                    padding: EdgeInsets.only(left: indent),
                    child: _buildMemberTile(
                      item.member,
                      isFronting,
                      memberTilePrefs,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              childCount: items.length,
              findChildIndexCallback: (key) => itemIndexes[key],
            ),
          ),
        ),
      ],
    );
  }

  Key _keyForGroupedItem(GroupedMemberListItem item) {
    if (item is GroupSectionItem) {
      return ValueKey(('members-grouped-section', item.group.id));
    }
    if (item is UngroupedSectionItem) {
      return const ValueKey(('members-grouped-section', '__ungrouped__'));
    }
    if (item is MemberRowItem) {
      final groupId = item.groupId ?? '__ungrouped__';
      return ValueKey(('members-grouped-member', groupId, item.member.id));
    }
    return ValueKey(item);
  }

  Widget _buildMemberTile(
    Member member,
    bool isFronting,
    _MemberTilePrefs memberTilePrefs, {
    int? reorderIndex,
  }) {
    final theme = Theme.of(context);
    final actions = _memberContextActions(member, isFronting);
    final frontButtonLabel = switch (memberTilePrefs.frontButtonBehavior) {
      FrontStartBehavior.additive => context.l10n.memberFrontButtonAddSemantic(
        member.name,
      ),
      FrontStartBehavior.replace =>
        context.l10n.memberFrontButtonReplaceSemantic(member.name),
    };

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
        deferAvatarLookup: true,
        showPronouns: memberTilePrefs.showPronouns,
        selected: isDetailSelected(member.id),
        onTap: () => _selectMember(
          member.id,
          navigate: () => unawaited(context.push(_memberPath(member.id))),
        ),
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
            if (memberTilePrefs.showFrontButtons && !isFronting) ...[
              IconButton(
                tooltip: frontButtonLabel,
                icon: Icon(AppIcons.add),
                onPressed: memberTilePrefs.frontingActionBusy
                    ? null
                    : () {
                        Haptics.selection();
                        unawaited(_startFronting(member));
                      },
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
        label: member.isActive ? 'Archive' : 'Unarchive',
        icon: member.isActive
            ? AppIcons.archiveOutlined
            : AppIcons.unarchiveOutlined,
        onSelected: () => _handleArchiveAction(member),
      ),
      _MemberContextAction(
        label: context.l10n.delete,
        icon: AppIcons.deleteOutline,
        destructive: true,
        onSelected: () => _confirmDeleteMember(context, member.id, member.name),
      ),
    ];
  }

  Future<void> _handleArchiveAction(Member member) async {
    if (!member.isActive) {
      _toggleMemberActive(member);
      return;
    }

    final terms = readTerminology(context, ref);
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Archive ${terms.singularLower}?',
      message:
          '${member.name} will be moved to inactive ${terms.pluralLower}. '
          'You can show inactive ${terms.pluralLower} and unarchive them later.',
      confirmLabel: 'Archive',
    );
    if (confirmed && mounted) {
      _toggleMemberActive(member);
    }
  }

  Future<void> _startFronting(Member member) async {
    try {
      final behavior = ref.read(membersFrontButtonBehaviorProvider);
      final notifier = ref.read(frontingNotifierProvider.notifier);
      switch (behavior) {
        case FrontStartBehavior.additive:
          await notifier.startFronting([member.id]);
        case FrontStartBehavior.replace:
          await notifier.replaceFronting([member.id]);
      }
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
    ManageGroupsSheet.show(
      context,
      memberId: member.id,
      memberName: member.name,
    );
  }
}

class _MemberViewSettingsBanner extends StatelessWidget {
  const _MemberViewSettingsBanner({
    required this.terms,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final Terminology terms;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InfoBanner(
        icon: AppIcons.moreVert,
        iconColor: theme.colorScheme.primary,
        title: context.l10n.memberViewSettingsBannerTitle(terms.singular),
        message: context.l10n.memberViewSettingsBannerMessage(
          terms.singularLower,
        ),
        buttonText: context.l10n.memberListViewSettingsTitle,
        onButtonPressed: onOpenSettings,
        onDismiss: onDismiss,
        dismissLabel: context.l10n.dismiss,
        actionsBelow: true,
      ),
    );
  }
}

class _MemberListSectionHeader extends StatelessWidget {
  const _MemberListSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
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
