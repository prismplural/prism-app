import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

// ---------------------------------------------------------------------------
// SharedPreferences key — persists the last viewed sub-tab index.
// ---------------------------------------------------------------------------

const _kLastSubTabKey = 'boards.last_sub_tab';

// ---------------------------------------------------------------------------
// Sub-tab enum
// ---------------------------------------------------------------------------

enum _BoardsSubTab { public, inbox }

// ---------------------------------------------------------------------------
// BoardsScreen
// ---------------------------------------------------------------------------

/// The top-level Boards screen, rendered at `/boards`.
///
/// Contains two sub-tabs: **Public** (all public posts, keyset-paginated) and
/// **Inbox** (private posts addressed to the currently-active fronters,
/// paginated). Sub-tab selection is persisted to SharedPreferences under
/// [_kLastSubTabKey]. Swipe between tabs is supported via [PageView].
class BoardsScreen extends ConsumerStatefulWidget {
  const BoardsScreen({super.key});

  @override
  ConsumerState<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends ConsumerState<BoardsScreen> {
  late final PageController _pageController;
  _BoardsSubTab _activeTab = _BoardsSubTab.public;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadSavedTab();
  }

  Future<void> _loadSavedTab() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_kLastSubTabKey) ?? 0;
    final tab = savedIndex == 1 ? _BoardsSubTab.inbox : _BoardsSubTab.public;
    if (mounted) {
      setState(() {
        _activeTab = tab;
        _prefsLoaded = true;
      });
      // Jump (no animation on initial load) to the correct page.
      _pageController.jumpToPage(tab.index);
    }
  }

  Future<void> _selectTab(_BoardsSubTab tab) async {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    unawaited(
      _pageController.animateToPage(
        tab.index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSubTabKey, tab.index);
  }

  void _onPageChanged(int index) {
    final tab = index == 1 ? _BoardsSubTab.inbox : _BoardsSubTab.public;
    if (_activeTab != tab) {
      setState(() => _activeTab = tab);
      SharedPreferences.getInstance().then(
        (p) => p.setInt(_kLastSubTabKey, tab.index),
      );
    }
  }

  void _openCompose() {
    ComposePostSheet.show(context);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnreadDot = ref.watch(publicBoardUnreadDotProvider);
    final badgeCount = ref.watch(boardsTabBadgeProvider);

    return PrismPageScaffold(
      bodyPadding: EdgeInsets.zero,
      topBar: _BoardsTopBar(onComposeTap: _openCompose),
      body: Column(
        children: [
          // Segmented control row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: _BoardsSegmentedControl(
              activeTab: _activeTab,
              hasPublicUnread: hasUnreadDot,
              inboxBadge: badgeCount,
              onTabSelected: _selectTab,
            ),
          ),

          // Page view — fills remaining vertical space
          Expanded(
            child: Visibility(
              // Keep both pages alive so they don't lose scroll position.
              maintainState: true,
              visible: _prefsLoaded,
              replacement: const SizedBox.shrink(),
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: [
                  _PublicPage(activeTab: _activeTab),
                  _InboxPage(activeTab: _activeTab),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _BoardsTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _BoardsTopBar({required this.onComposeTap});

  final VoidCallback onComposeTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return PrismTopBar(
      title: context.l10n.boardsScreenTitle,
      trailing: PrismTopBarAction(
        icon: AppIcons.add,
        tooltip: context.l10n.add,
        onPressed: onComposeTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom segmented control with unread dot + numeric badge
// ---------------------------------------------------------------------------

/// A two-segment control styled like [PrismSegmentedControl] but with support
/// for an unread dot on the Public label and a numeric badge on the Inbox label.
class _BoardsSegmentedControl extends StatelessWidget {
  const _BoardsSegmentedControl({
    required this.activeTab,
    required this.hasPublicUnread,
    required this.inboxBadge,
    required this.onTabSelected,
  });

  final _BoardsSubTab activeTab;
  final bool hasPublicUnread;
  final int inboxBadge;
  final ValueChanged<_BoardsSubTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = context.l10n;

    final trackColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.07)
        : AppColors.warmBlack.withValues(alpha: 0.06);
    final trackBorderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.12)
        : AppColors.warmBlack.withValues(alpha: 0.10);
    final pillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.18)
        : AppColors.warmWhite.withValues(alpha: 0.85);
    final pillBorderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.15)
        : AppColors.warmBlack.withValues(alpha: 0.12);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius:
            BorderRadius.circular(PrismShapes.of(context).radius(999)),
        border: Border.all(color: trackBorderColor, width: 0.5),
      ),
      child: Row(
        children: [
          // Public segment
          Expanded(
            child: _SegmentButton(
              label: l10n.boardsTabPublic,
              isSelected: activeTab == _BoardsSubTab.public,
              onTap: () => onTabSelected(_BoardsSubTab.public),
              pillColor: pillColor,
              pillBorderColor: pillBorderColor,
              theme: theme,
              suffix: hasPublicUnread
                  ? _UnreadDot(color: theme.colorScheme.primary)
                  : null,
              semanticsLabel: hasPublicUnread
                  ? '${l10n.boardsTabPublic}, unread'
                  : l10n.boardsTabPublic,
            ),
          ),

          // Inbox segment
          Expanded(
            child: _SegmentButton(
              label: l10n.boardsTabInbox,
              isSelected: activeTab == _BoardsSubTab.inbox,
              onTap: () => onTabSelected(_BoardsSubTab.inbox),
              pillColor: pillColor,
              pillBorderColor: pillBorderColor,
              theme: theme,
              suffix: inboxBadge > 0 ? _NumericBadge(count: inboxBadge) : null,
              semanticsLabel: inboxBadge > 0
                  ? '${l10n.boardsTabInbox}, $inboxBadge unread'
                  : l10n.boardsTabInbox,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.pillColor,
    required this.pillBorderColor,
    required this.theme,
    this.suffix,
    this.semanticsLabel,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color pillColor;
  final Color pillBorderColor;
  final ThemeData theme;
  final Widget? suffix;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticsLabel ?? label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.all(2),
          decoration: isSelected
              ? BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(
                    PrismShapes.of(context).radius(999),
                  ),
                  border: Border.all(color: pillBorderColor, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.warmBlack.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                )
              : null,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  suffix!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 7pt unread dot rendered in [color].
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A compact numeric badge (max 99+).
class _NumericBadge extends StatelessWidget {
  const _NumericBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(999),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Public page
// ---------------------------------------------------------------------------

class _PublicPage extends ConsumerStatefulWidget {
  const _PublicPage({required this.activeTab});

  final _BoardsSubTab activeTab;

  @override
  ConsumerState<_PublicPage> createState() => _PublicPageState();
}

class _PublicPageState extends ConsumerState<_PublicPage> {
  bool _markedViewed = false;

  @override
  void initState() {
    super.initState();
    // Mark public viewed on first frame — clears the unread dot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_markedViewed) {
        _markedViewed = true;
        ref
            .read(memberBoardPostNotifierProvider.notifier)
            .markPublicViewed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(memberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    // First page cursor.
    const firstCursor = BoardPagingCursor();
    final postsAsync = ref.watch(publicBoardPostsProvider(firstCursor));

    return postsAsync.when(
      loading: () => Center(
        child: Builder(
          builder: (context) => PrismSpinner(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (posts) {
        if (posts.isEmpty) {
          return Center(
            child: EmptyState(
              icon: Icon(AppIcons.forum),
              title: l10n.boardsTabPublic,
              subtitle: l10n.boardsEmptyPublic,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            // Invalidate the provider to force a refresh.
            ref.invalidate(publicBoardPostsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              return PostTile(
                post: posts[index],
                viewerMember: viewerMember,
                showAudiencePill: true,
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Inbox page
// ---------------------------------------------------------------------------

class _InboxPage extends ConsumerStatefulWidget {
  const _InboxPage({required this.activeTab});

  final _BoardsSubTab activeTab;

  @override
  ConsumerState<_InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<_InboxPage> {
  /// The last-known list of active member IDs — used to detect de-front events.
  List<String> _lastActiveIds = [];
  bool _inboxOpenedCalled = false;

  @override
  void didUpdateWidget(covariant _InboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the Inbox tab becomes active, fire markInboxOpenedFor.
    if (widget.activeTab == _BoardsSubTab.inbox && !_inboxOpenedCalled) {
      _inboxOpenedCalled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _markInboxOpened());
    }
    // Reset the flag when switching away so it fires again on next open.
    if (widget.activeTab != _BoardsSubTab.inbox) {
      _inboxOpenedCalled = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // If the inbox is the initial tab, mark on first frame.
    if (widget.activeTab == _BoardsSubTab.inbox) {
      _inboxOpenedCalled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _markInboxOpened(),
      );
    }
  }

  void _markInboxOpened() {
    if (!mounted) return;
    final fronterIds = ref.read(currentFronterMemberIdsProvider);
    unawaited(
      ref
          .read(memberBoardPostNotifierProvider.notifier)
          .markInboxOpenedFor(fronterIds),
    );
  }

  /// Check whether the currently-filtered member has de-fronted and show a
  /// toast if so, resetting the filter.
  void _checkFilterStillValid(
    List<Member> activeMembers,
    String? filterId,
    BuildContext ctx,
  ) {
    if (filterId == null) return;

    final newIds = activeMembers.map((m) => m.id).toSet();
    if (!newIds.contains(filterId)) {
      // The filtered member is no longer fronting.
      final oldIds = _lastActiveIds.toSet();
      if (oldIds.contains(filterId)) {
        // Find their name from the old list if still loaded.
        final memberName =
            activeMembers
                .where((m) => !oldIds.difference(newIds).contains(m.id))
                .firstOrNull
                ?.name ??
            filterId;

        // Reset filter.
        ref.read(inboxViewFilterProvider.notifier).setFilter(null);

        // Show toast.
        if (ctx.mounted) {
          PrismToast.show(
            ctx,
            message: ctx.l10n.boardsToastFronterDeFronted(memberName),
            icon: AppIcons.navBoardsActive,
          );
        }
      }
    }

    _lastActiveIds = activeMembers.map((m) => m.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fronterMembers = ref.watch(currentFronterMembersProvider);
    final filterId = ref.watch(inboxViewFilterProvider);

    // Detect de-front and reset filter.
    _checkFilterStillValid(fronterMembers, filterId, context);

    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(memberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    const firstCursor = BoardPagingCursor();
    final postsAsync = ref.watch(inboxBoardPostsProvider(firstCursor));

    // Filtered posts (if filter is active, only show matching posts).
    final filteredPosts = postsAsync.whenOrNull(
      data: (posts) {
        if (filterId == null) return posts;
        return posts
            .where(
              (p) =>
                  p.targetMemberId == filterId ||
                  p.authorId == filterId,
            )
            .toList();
      },
    );

    return Column(
      children: [
        // View-filter dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: _InboxFilterBar(
            activeMembers: fronterMembers,
            filterId: filterId,
            onChanged: (id) =>
                ref.read(inboxViewFilterProvider.notifier).setFilter(id),
          ),
        ),

        // Posts list
        Expanded(
          child: postsAsync.when(
            loading: () => Center(
        child: Builder(
          builder: (context) => PrismSpinner(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (_) {
              final posts = filteredPosts ?? const [];
              if (posts.isEmpty) {
                return Center(
                  child: fronterMembers.isEmpty
                      ? EmptyState(
                          icon: Icon(AppIcons.forum),
                          title: l10n.boardsTabInbox,
                          subtitle: l10n.boardsComposeNoFronterHint,
                        )
                      : EmptyState(
                          icon: Icon(AppIcons.forum),
                          title: l10n.boardsTabInbox,
                          subtitle: l10n.boardsEmptyInbox,
                        ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  return PostTile(
                    post: posts[index],
                    viewerMember: viewerMember,
                    showAudiencePill: false,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inbox filter bar
// ---------------------------------------------------------------------------

/// A compact [BlurPopupAnchor]-driven dropdown for filtering the inbox.
///
/// Displays the currently-active filter (or "All fronters" when null) as a
/// tappable chip. The popup lists all active fronters plus an "All" option.
class _InboxFilterBar extends StatelessWidget {
  const _InboxFilterBar({
    required this.activeMembers,
    required this.filterId,
    required this.onChanged,
  });

  final List<Member> activeMembers;
  final String? filterId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    // Determine label for the current filter.
    final currentMember = filterId != null
        ? activeMembers.where((m) => m.id == filterId).firstOrNull
        : null;
    final filterLabel = currentMember != null
        ? l10n.boardsViewFilterMember(currentMember.name)
        : l10n.boardsViewFilterAll;

    // Items: "All fronters" + one entry per active member.
    final itemCount = 1 + activeMembers.length;

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: '${l10n.boardsViewFilterAll}, $filterLabel',
        child: BlurPopupAnchor(
          width: 240,
          itemCount: itemCount,
          semanticLabel: l10n.boardsViewFilterAll,
          itemBuilder: (ctx, index, close) {
            if (index == 0) {
              return PrismListRow(
                leading: Icon(
                  AppIcons.navBoards,
                  color: filterId == null
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(
                  l10n.boardsViewFilterAll,
                  style: filterId == null
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
                onTap: () {
                  close();
                  onChanged(null);
                },
              );
            }
            final member = activeMembers[index - 1];
            final isSelected = filterId == member.id;
            return PrismListRow(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? theme.colorScheme.primary : null,
                size: 20,
              ),
              title: Text(
                l10n.boardsViewFilterMember(member.name),
                style: isSelected
                    ? TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
              onTap: () {
                close();
                onChanged(member.id);
              },
            );
          },
          child: _FilterChip(label: filterLabel, theme: theme),
        ),
      ),
    );
  }
}

/// Tappable chip showing the active filter label with a down-arrow indicator.
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(999),
        ),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
