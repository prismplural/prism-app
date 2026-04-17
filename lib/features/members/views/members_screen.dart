import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/views/add_edit_member_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_delegate.dart';
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
              title: Text(
                ctxL10n.terminologySearchHint(terms.pluralLower),
              ),
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
              leading: Icon(_showInactive
                  ? AppIcons.visibility
                  : AppIcons.visibilityOutlined),
              title: Text(
                  _showInactive ? ctxL10n.memberHideInactive : ctxL10n.memberShowInactive),
              trailing: _showInactive
                  ? Icon(AppIcons.check,
                      size: 18, color: theme.colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() => _showInactive = !_showInactive);
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                dense: true,
                title: Text(ctxL10n.memberSortNameAZ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderBy(members, (a, b) => a.name
                      .toLowerCase()
                      .compareTo(b.name.toLowerCase()));
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                dense: true,
                title: Text(ctxL10n.memberSortNameZA),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderBy(members, (a, b) => b.name
                      .toLowerCase()
                      .compareTo(a.name.toLowerCase()));
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                dense: true,
                title: Text(ctxL10n.memberSortRecentlyCreated),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderBy(
                      members, (a, b) => b.createdAt.compareTo(a.createdAt));
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                dense: true,
                title: Text(ctxL10n.memberSortMostFronting),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reorderByFronting(members, descending: true);
                },
              ),
              PrismListRow(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      builder: (context, scrollController) => AddEditMemberSheet(
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _openSearch(List<Member> members) async {
    final terms = readTerminology(context, ref);
    final result = await showSearch<String?>(
      context: context,
      delegate: MemberSearchDelegate(
        members: members,
        searchHint: context.l10n.terminologySearchHint(terms.pluralLower),
        emptyLabel: context.l10n.terminologyNoFound(terms.pluralLower),
      ),
    );
    if (result != null && mounted) {
      unawaited(context.push(_memberPath(context, result)));
    }
  }

  Future<bool?> _confirmDeleteMember(
    BuildContext context,
    String memberId,
    String memberName,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.terminologyDeleteItem(readTerminology(context, ref).singular),
      message: 'Are you sure you want to delete $memberName? This action cannot be undone.',
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      unawaited(ref.read(membersNotifierProvider.notifier).deleteMember(memberId));
    }
    return confirmed;
  }

  void _toggleMemberActive(Member member) {
    final newActive = !member.isActive;
    ref.read(membersNotifierProvider.notifier).updateMember(
          member.copyWith(isActive: newActive),
        );
    Haptics.selection();
    PrismToast.show(
      context,
      message: newActive
          ? context.l10n.memberActivated(member.name)
          : context.l10n.memberDeactivated(member.name),
    );
  }

  Future<void> _reorderBy(List<Member> members, int Function(Member a, Member b) compare) async {
    final sorted = [...members]..sort(compare);
    unawaited(ref.read(membersNotifierProvider.notifier).reorderMembers(sorted));
    Haptics.selection();
    if (mounted) PrismToast.show(context, message: context.l10n.memberOrderUpdated);
  }

  Future<void> _reorderByFronting(List<Member> members, {required bool descending}) async {
    final statsFutures = members.map(
      (m) => ref.read(memberFrontingStatsProvider(m.id).future),
    );
    final allStats = await Future.wait(statsFutures);
    final statsMap = <String, int>{
      for (var i = 0; i < members.length; i++)
        members[i].id: allStats[i].totalSessions,
    };
    final sorted = [...members]..sort((a, b) {
      final aCount = statsMap[a.id] ?? 0;
      final bCount = statsMap[b.id] ?? 0;
      return descending ? bCount.compareTo(aCount) : aCount.compareTo(bCount);
    });
    unawaited(ref.read(membersNotifierProvider.notifier).reorderMembers(sorted));
    Haptics.selection();
    if (mounted) PrismToast.show(context, message: context.l10n.memberOrderUpdated);
  }

  void _onReorder(List<Member> members, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<Member>.from(members);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    ref.read(membersNotifierProvider.notifier).reorderMembers(reordered);
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = _showInactive
        ? ref.watch(allMembersProvider)
        : ref.watch(activeMembersProvider);
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final terms = watchTerminology(context, ref);

    // Build a set of currently-fronting member IDs.
    final frontingIds = activeSessionsAsync.whenOrNull(
          data: (sessions) =>
              sessions.map((s) => s.memberId).whereType<String>().toSet(),
        ) ??
        <String>{};

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
      body: AnimatedSwitcher(
        duration: Anim.md,
        child: KeyedSubtree(
        key: ValueKey(_showInactive),
        child: membersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.terminologyLoadError(terms.pluralLower, e.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return EmptyState(
              icon: Icon(AppIcons.peopleOutline),
              title: _showInactive
                  ? context.l10n.terminologyEmptyTitle(terms.pluralLower)
                  : context.l10n.terminologyEmptyActiveTitle(terms.pluralLower),
              subtitle: context.l10n.terminologyAddFirstSubtitle(terms.singularLower),
              actionLabel: context.l10n.terminologyAddButton(terms.singular),
              onAction: _openAddSheet,
            );
          }

          return ReorderableListView.builder(
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
                    borderRadius: BorderRadius.circular(12),
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
                  member, isFronting, terms,
                  reorderIndex: index,
                );
              },
          );
        },
      ),
        ),
      ),
    );
  }

  Widget _buildMemberTile(
    Member member,
    bool isFronting,
    dynamic terms, {
    int? reorderIndex,
  }) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(member.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: member.isActive ? Colors.orange : Colors.green,
        child: Icon(
          member.isActive ? AppIcons.archiveOutlined : AppIcons.unarchiveOutlined,
          color: AppColors.warmWhite,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.error,
        child: Icon(AppIcons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (direction) {
        if (direction == DismissDirection.endToStart) {
          return _confirmDeleteMember(context, member.id, member.name);
        }
        _toggleMemberActive(member);
        return Future.value(false);
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
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
