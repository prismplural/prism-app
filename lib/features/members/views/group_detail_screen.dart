import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/delete_group_sheet.dart';
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Detail screen for a single member group.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    this.settingsBranch = true,
  });

  final String groupId;
  final bool settingsBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupAsync = ref.watch(groupByIdProvider(groupId));

    return groupAsync.when(
      loading: () => const PrismPageScaffold(
        topBar: PrismTopBar(title: '', showBackButton: true),
        body: PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: const PrismTopBar(title: '', showBackButton: true),
        body: Center(child: Text(l10n.memberGroupErrorLoadingDetail(e))),
      ),
      data: (group) {
        if (group == null) {
          return PrismPageScaffold(
            topBar: const PrismTopBar(title: '', showBackButton: true),
            body: Center(child: Text(l10n.memberGroupNotFound)),
          );
        }
        return _GroupDetailBody(group: group, settingsBranch: settingsBranch);
      },
    );
  }
}

class _GroupDetailBody extends ConsumerStatefulWidget {
  const _GroupDetailBody({required this.group, required this.settingsBranch});

  final MemberGroup group;
  final bool settingsBranch;

  @override
  ConsumerState<_GroupDetailBody> createState() => _GroupDetailBodyState();
}

class _GroupDetailBodyState extends ConsumerState<_GroupDetailBody> {
  final GlobalKey<BlurPopupAnchorState> _optionsPopupKey = GlobalKey();

  /// FocusNodes per entry id for best-effort focus retention across a11y
  /// reorder. Lazily allocated by [_focusNodeFor] and disposed in [dispose].
  /// When a custom semantic action moves a row, we schedule a post-frame
  /// `requestFocus` on the moved entry's node so the screen reader's
  /// caret tracks the moved item. The polite `_announce` call remains the
  /// reliable signal — focus retention is BEST EFFORT (Flutter's focus
  /// system isn't a guaranteed contract for non-input widgets).
  final Map<String, FocusNode> _entryFocusNodes = {};
  String? _pendingFocusEntryId;

  MemberGroup get group => widget.group;
  bool get settingsBranch => widget.settingsBranch;

  FocusNode _focusNodeFor(String entryId) {
    return _entryFocusNodes.putIfAbsent(
      entryId,
      () =>
          FocusNode(debugLabel: 'group_member_$entryId', skipTraversal: false),
    );
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
    final terms = watchTerminology(context, ref);
    final entriesAsync = ref.watch(groupEntriesProvider(group.id));
    ref.watch(activeMembersProvider);
    final allGroupsAsync = ref.watch(allGroupsProvider);
    ref.watch(allGroupEntriesProvider);
    final canAddSubGroup = allGroupsAsync.hasValue;
    final allGroups =
        allGroupsAsync.whenOrNull(data: (g) => g) ?? const <MemberGroup>[];
    final ancestors = _resolveAncestors(group, allGroups);
    final entries = entriesAsync.whenOrNull(data: (entries) => entries);
    final hasMembers = entries?.isNotEmpty ?? false;

    // sortedGroupMembersProvider handles all the read-path invariants:
    // filtering (showInactive, missing members), per-mode ordering, and
    // dedupe of stale ids in sortState.manualOrder. See plan §"Read path
    // invariants".
    final visiblePairs = ref.watch(sortedGroupMembersProvider(group.id));
    final liveEntryIds = visiblePairs.map((pair) => pair.$1.id).toSet();
    final staleEntryIds = _entryFocusNodes.keys
        .where((id) => !liveEntryIds.contains(id))
        .toList();
    for (final id in staleEntryIds) {
      _entryFocusNodes.remove(id)?.dispose();
    }
    final visibleMembers = [for (final pair in visiblePairs) pair.$2];

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: l10n.edit,
            onPressed: () => _openEditSheet(context),
          ),
          _buildOptionsMenuAction(visiblePairs, visibleMembers, terms),
          PrismPopupMenu<_GroupMenuAction>(
            tooltip: l10n.moreOptions,
            items: [
              if (hasMembers) ...[
                PrismMenuItem(
                  value: _GroupMenuAction.frontGroup,
                  label: l10n.memberGroupFrontGroup,
                  icon: Icons.group_outlined,
                ),
                PrismMenuItem(
                  value: _GroupMenuAction.startChat,
                  label: l10n.memberGroupStartChat,
                  icon: Icons.chat_bubble_outline,
                ),
              ],
              if (canAddSubGroup)
                PrismMenuItem(
                  value: _GroupMenuAction.addSubGroup,
                  label: l10n.memberGroupAddSubGroup,
                  icon: AppIcons.add,
                ),
              PrismMenuItem(
                value: _GroupMenuAction.delete,
                label: l10n.delete,
                icon: AppIcons.deleteOutline,
                destructive: true,
              ),
            ],
            onSelected: (action) => _handleMenuAction(
              context,
              ref,
              action,
              entries ?? const <MemberGroupEntry>[],
            ),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GroupInfoHeader(group: group, ancestors: ancestors),
            ),

            const SizedBox(height: 24),

            _SubGroupsSection(
              groupId: group.id,
              settingsBranch: settingsBranch,
              canAddSubGroup: canAddSubGroup,
              onAddSubGroup: () => _addSubGroup(context),
            ),

            Padding(
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
                  // Lock chip — right-aligned, inline. Hidden in manual mode.
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

            entriesAsync.when(
              loading: () => const PrismLoadingState(),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Error: $e'),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
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
                  );
                }
                if (visiblePairs.isEmpty) {
                  // All entries are filtered out — every member in this group
                  // is inactive and the toggle hides them.
                  return Padding(
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
                  );
                }

                // Drag-reorder list. Handles always live in the trailing slot
                // of each MemberCard (see MemberCard.reorderIndex). Dragging
                // in a sorted mode does *implicit unlock* (plan §Task 5.1 B).
                return ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  buildDefaultDragHandles: false,
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
                      settingsBranch: settingsBranch,
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

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Reorder + sort-mode plumbing ───────────────────────────────────────────

  Future<void> _onReorder(
    List<(MemberGroupEntry, Member)> pairs,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final reordered = [...pairs];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final newOrder = [for (final p in reordered) p.$1.id];
    await _applyManualOrder(newOrder, wasManual: group.sortState.isManual);
  }

  Future<void> _moveTo(
    List<(MemberGroupEntry, Member)> pairs,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final reordered = [...pairs];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    final movedEntryId = item.$1.id;
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
    final members = [for (final p in pairs) p.$2];
    final statsFutures = members.map(
      (m) => ref.read(memberFrontingStatsProvider(m.id).future),
    );
    final allStats = await Future.wait(statsFutures);
    final statsMap = <String, Duration>{
      for (var i = 0; i < members.length; i++)
        members[i].id: allStats[i].totalDuration,
    };
    final sorted = [...pairs]
      ..sort((a, b) {
        final ad = statsMap[a.$2.id] ?? Duration.zero;
        final bd = statsMap[b.$2.id] ?? Duration.zero;
        return descending ? bd.compareTo(ad) : ad.compareTo(bd);
      });
    final newOrder = [for (final p in sorted) p.$1.id];
    if (!mounted) return;
    await _applyManualOrder(newOrder, wasManual: group.sortState.isManual);
  }

  // ── Options menu ───────────────────────────────────────────────────────────

  Widget _buildOptionsMenuAction(
    List<(MemberGroupEntry, Member)> visiblePairs,
    List<Member> visibleMembers,
    Terminology terms,
  ) {
    final l10n = context.l10n;
    final canSearch = visibleMembers.isNotEmpty;
    final canSort = visibleMembers.length > 1;
    final currentMode = group.sortState.mode;

    Widget sortItemRow({
      required BuildContext ctx,
      required IconData icon,
      required String label,
      required bool isActive,
      required VoidCallback onTap,
    }) {
      final theme = Theme.of(ctx);
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
                  _openSearch(visibleMembers);
                }
              : null,
        );
      },
      (_, _) => const Divider(height: 1),
      (ctx, close) {
        final theme = Theme.of(ctx);
        final ctxL10n = ctx.l10n;
        final showInactive = ref.watch(showInactiveMembersProvider);
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          leading: Icon(
            showInactive ? AppIcons.visibility : AppIcons.visibilityOutlined,
            size: 20,
          ),
          title: Text(
            showInactive
                ? ctxL10n.memberHideInactive
                : ctxL10n.memberShowInactive,
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
    ];

    if (canSort) {
      entries.addAll([
        (_, _) => const Divider(height: 1),
        // ── "Sort by" — locked modes ──────────────────────────────────────
        (ctx, _) => _sectionHeader(ctx, ctx.l10n.groupSortSectionSortBy),
        (ctx, close) => sortItemRow(
          ctx: ctx,
          icon: AppIcons.arrowUpward,
          label: ctx.l10n.groupSortItemNameAsc,
          isActive: currentMode == GroupSortMode.nameAsc,
          onTap: () {
            close();
            unawaited(_setSortMode(GroupSortMode.nameAsc));
          },
        ),
        (ctx, close) => sortItemRow(
          ctx: ctx,
          icon: AppIcons.arrowDownward,
          label: ctx.l10n.groupSortItemNameDesc,
          isActive: currentMode == GroupSortMode.nameDesc,
          onTap: () {
            close();
            unawaited(_setSortMode(GroupSortMode.nameDesc));
          },
        ),
        (ctx, close) => sortItemRow(
          ctx: ctx,
          icon: AppIcons.history,
          label: ctx.l10n.groupSortItemRecentDesc,
          isActive: currentMode == GroupSortMode.recentDesc,
          onTap: () {
            close();
            unawaited(_setSortMode(GroupSortMode.recentDesc));
          },
        ),
        (ctx, close) => sortItemRow(
          ctx: ctx,
          icon: AppIcons.dragHandle,
          label: ctx.l10n.groupSortItemManual,
          isActive: currentMode == GroupSortMode.manual,
          onTap: () {
            close();
            unawaited(_sortManuallyFromCurrent(visiblePairs));
          },
        ),
        (_, _) => const Divider(height: 1),
        // ── "Apply current order" — one-shot snapshots ────────────────────
        (ctx, _) => _sectionHeader(ctx, ctx.l10n.groupSortSectionApplyCurrent),
        (ctx, close) => sortItemRow(
          ctx: ctx,
          icon: AppIcons.flashOn,
          label: ctx.l10n.groupSortItemFrontingMost,
          isActive: false,
          onTap: () {
            close();
            unawaited(_applyFrontingOrder(visiblePairs, descending: true));
          },
        ),
        (ctx, close) => sortItemRow(
          ctx: ctx,
          icon: AppIcons.frontHandOutlined,
          label: ctx.l10n.groupSortItemFrontingLeast,
          isActive: false,
          onTap: () {
            close();
            unawaited(_applyFrontingOrder(visiblePairs, descending: false));
          },
        ),
      ]);
    }

    return BlurPopupAnchor(
      key: _optionsPopupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: BlurPopupDirection.down,
      width: 280,
      maxHeight: 480,
      itemCount: entries.length,
      semanticLabel: l10n.options,
      itemBuilder: (ctx, index, close) => entries[index](ctx, close),
      child: PrismTopBarAction(
        icon: AppIcons.moreVert,
        tooltip: l10n.options,
        onPressed: () => _optionsPopupKey.currentState?.show(),
      ),
    );
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
        unawaited(
          context.push(
            settingsBranch
                ? AppRoutePaths.settingsMember(memberId)
                : AppRoutePaths.member(memberId),
          ),
        );
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
        Navigator.of(context).pop();
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
    final availableMembers =
        (ref.read(userVisibleMembersProvider).value ?? const <Member>[])
            .where((member) => !existingMemberIds.contains(member.id))
            .toList();

    final selectedIds = await MemberSearchSheet.showMulti(
      context,
      members: availableMembers,
      termPlural: readTerminology(context, ref).plural,
      groups: readMemberSearchGroups(ref, availableMembers),
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
        ref.read(allMembersProvider).whenOrNull(data: (m) => m) ?? [];
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

class _GroupInfoHeader extends StatelessWidget {
  const _GroupInfoHeader({required this.group, required this.ancestors});

  final MemberGroup group;
  final List<MemberGroup> ancestors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColor = group.colorHex != null && group.colorHex!.isNotEmpty;
    final accentColor = hasColor ? AppColors.fromHex(group.colorHex!) : null;
    final radius = BorderRadius.circular(PrismShapes.of(context).radius(14));
    final hasEmoji = group.emoji != null && group.emoji!.isNotEmpty;

    return Material(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasColor) Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hasColor ? 12 : 16, 16, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TintedGlassSurface.circle(
                      size: 56,
                      tint: accentColor ?? theme.colorScheme.primary,
                      child: Center(
                        child: hasEmoji
                            ? Text(
                                group.emoji!,
                                style: const TextStyle(fontSize: 30),
                              )
                            : Icon(
                                AppIcons.folderOutlined,
                                size: 26,
                                color: accentColor ?? theme.colorScheme.primary,
                              ),
                      ),
                    ),
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
                            MarkdownText(
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
            ),
          ],
        ),
      ),
    );
  }
}

class _SubGroupsSection extends ConsumerWidget {
  const _SubGroupsSection({
    required this.groupId,
    required this.settingsBranch,
    required this.canAddSubGroup,
    required this.onAddSubGroup,
  });

  final String groupId;
  final bool settingsBranch;
  final bool canAddSubGroup;
  final VoidCallback onAddSubGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final children = ref.watch(childGroupsProvider(groupId));

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
              if (canAddSubGroup)
                PrismInlineIconButton(
                  icon: AppIcons.add,
                  tooltip: l10n.memberGroupAddSubGroup,
                  size: 32,
                  iconSize: 20,
                  color: theme.colorScheme.primary,
                  onPressed: onAddSubGroup,
                ),
            ],
          ),
        ),
        if (children.isNotEmpty) _buildChildrenList(context, ref, children),
        const SizedBox(height: 20),
      ],
    );
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
        if (newIndex > oldIndex) newIndex -= 1;
        if (oldIndex == newIndex) return;
        final reordered = [...children];
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
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
    return MemberGroupRow(
      key: ValueKey('subgroup_${group.id}'),
      group: group,
      memberCount: count,
      reorderIndex: reorderIndex,
      onTap: () => context.push(
        settingsBranch
            ? AppRoutePaths.settingsGroup(group.id)
            : AppRoutePaths.memberGroup(group.id),
      ),
    );
  }
}

class _GroupMemberTile extends ConsumerWidget {
  const _GroupMemberTile({
    super.key,
    required this.entry,
    required this.member,
    required this.groupId,
    required this.settingsBranch,
    required this.reorderIndex,
    required this.totalCount,
    required this.sortMode,
    required this.focusNode,
    required this.onMoveTo,
  });

  final MemberGroupEntry entry;
  final Member member;
  final String groupId;
  final bool settingsBranch;
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
            reorderIndex: reorderIndex,
            dragHandleHint: isManual
                ? l10n.groupMemberDragHandleHintManual
                : l10n.groupMemberDragHandleHintSorted,
            onTap: () => context.push(
              settingsBranch
                  ? AppRoutePaths.settingsMember(member.id)
                  : AppRoutePaths.member(member.id),
            ),
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
