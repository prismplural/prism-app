import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/views/post_detail_screen.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/clamped_body.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_selector_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
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
// Post-tap navigation
// ---------------------------------------------------------------------------

/// Opens a board post's detail view. Wide windows present it as a modal side
/// sheet over the clamped feed; narrow windows push the full-screen route
/// (matching [PostTile]'s default tap behavior).
void _openBoardPost(BuildContext context, String postId) {
  showAdaptiveDetailSurface<void>(
    context: context,
    builder: (_) => PostDetailScreen(postId: postId),
    route: (context) => context.push(AppRoutePaths.boardPost(postId)),
  );
}

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(tab.index);
      });
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
      topBarMaxWidth: PrismTokens.contentMaxWidth,
      body: Column(
        children: [
          // Clamp the tab switcher to the same column as the post lists so the
          // header aligns with the content on wide windows.
          ClampedBody(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _BoardsSegmentedControl(
                activeTab: _activeTab,
                hasPublicUnread: hasUnreadDot,
                inboxBadge: badgeCount,
                onTabSelected: _selectTab,
              ),
            ),
          ),
          Expanded(
            child: !_prefsLoaded
                ? const SizedBox.shrink()
                : PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      _PublicPage(activeTab: _activeTab),
                      _InboxPage(activeTab: _activeTab),
                    ],
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
      leading: const _BoardsMemberFilterButton(),
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
    final l10n = context.l10n;
    final controlColors = PrismSegmentedControlColors.resolve(
      theme,
      highContrast: MediaQuery.highContrastOf(context),
    );

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: controlColors.trackColor,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(999),
        ),
        border: Border.all(color: controlColors.trackBorderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: l10n.boardsTabPublic,
              isSelected: activeTab == _BoardsSubTab.public,
              onTap: () => onTabSelected(_BoardsSubTab.public),
              pillColor: controlColors.pillColor,
              pillBorderColor: controlColors.pillBorderColor,
              pillShadowColor: controlColors.shadowColor,
              theme: theme,
              suffix: hasPublicUnread
                  ? _UnreadDot(color: theme.colorScheme.primary)
                  : null,
              semanticsLabel: hasPublicUnread
                  ? '${l10n.boardsTabPublic}, unread'
                  : l10n.boardsTabPublic,
            ),
          ),
          Expanded(
            child: _SegmentButton(
              label: l10n.boardsTabInbox,
              isSelected: activeTab == _BoardsSubTab.inbox,
              onTap: () => onTabSelected(_BoardsSubTab.inbox),
              pillColor: controlColors.pillColor,
              pillBorderColor: controlColors.pillBorderColor,
              pillShadowColor: controlColors.shadowColor,
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
    required this.pillShadowColor,
    required this.theme,
    this.suffix,
    this.semanticsLabel,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color pillColor;
  final Color pillBorderColor;
  final Color pillShadowColor;
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
                      color: pillShadowColor,
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
                if (suffix != null) ...[const SizedBox(width: 4), suffix!],
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
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
  final _scrollController = ScrollController();
  bool _markedViewed = false;

  bool get _isActive => widget.activeTab == _BoardsSubTab.public;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markPublicViewedIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant _PublicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab && _isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _markPublicViewedIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _markPublicViewedIfNeeded() {
    if (!_isActive || _markedViewed) return;
    _markedViewed = true;
    ref.read(memberBoardPostNotifierProvider.notifier).markPublicViewed();
  }

  void _onScroll() {
    if (!_isActive) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;

    final feed = ref.read(publicBoardFeedProvider);
    if (feed.isLoading) return;
    final loaded = feed.value?.length ?? 0;
    final currentLimit = ref.read(publicBoardLimitProvider);
    if (loaded >= currentLimit) {
      ref.read(publicBoardLimitProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActive) return const SizedBox.shrink();

    final l10n = context.l10n;
    final speakingAsId = ref.watch(speakingAsProvider);
    final filterId = ref.watch(inboxViewFilterProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(activeMemberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    final postsAsync = ref.watch(publicBoardFeedProvider);

    return postsAsync.when(
      skipLoadingOnReload: true,
      loading: () => Center(
        child: Builder(
          builder: (context) =>
              PrismSpinner(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (posts) {
        final filteredPosts = filterId == null
            ? posts
            : posts
                  .where(
                    (p) =>
                        p.targetMemberId == filterId || p.authorId == filterId,
                  )
                  .toList(growable: false);

        if (filteredPosts.isEmpty) {
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
            ref.invalidate(publicBoardFeedProvider);
            ref.invalidate(publicBoardLimitProvider);
          },
          child: ClampedBody(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: filteredPosts.length,
              itemBuilder: (context, index) {
                final post = filteredPosts[index];
                return PostTile(
                  post: post,
                  viewerMember: viewerMember,
                  showAudiencePill: true,
                  onTap: () => _openBoardPost(context, post.id),
                );
              },
            ),
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
  final _scrollController = ScrollController();
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
    _scrollController.addListener(_onScroll);
    // If the inbox is the initial tab, mark on first frame.
    if (widget.activeTab == _BoardsSubTab.inbox) {
      _inboxOpenedCalled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _markInboxOpened());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  void _onScroll() {
    if (widget.activeTab != _BoardsSubTab.inbox) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;

    final feed = ref.read(inboxBoardFeedProvider);
    if (feed.isLoading) return;
    final loaded = feed.value?.length ?? 0;
    final currentLimit = ref.read(inboxBoardLimitProvider);
    if (loaded >= currentLimit) {
      ref.read(inboxBoardLimitProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeTab != _BoardsSubTab.inbox) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final frontingTerms = watchFrontingTerms(ref);
    final fronterMembers = ref.watch(currentFronterMembersProvider);
    final filterId = ref.watch(inboxViewFilterProvider);

    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(activeMemberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    final postsAsync = ref.watch(inboxBoardFeedProvider);

    final filteredPosts = postsAsync.whenOrNull(
      data: (posts) {
        if (filterId == null) return posts;
        return posts
            .where(
              (p) => p.targetMemberId == filterId || p.authorId == filterId,
            )
            .toList();
      },
    );

    return postsAsync.when(
      skipLoadingOnReload: true,
      loading: () => Center(
        child: PrismSpinner(color: Theme.of(context).colorScheme.primary),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (_) {
        final posts = filteredPosts ?? const [];
        if (posts.isEmpty) {
          return Center(
            child: filterId == null && fronterMembers.isEmpty
                ? EmptyState(
                    icon: Icon(AppIcons.forum),
                    title: l10n.boardsTabInbox,
                    subtitle:
                        '${frontingTerms.emptyCurrentState} right now - start a session to post.',
                  )
                : EmptyState(
                    icon: Icon(AppIcons.forum),
                    title: l10n.boardsTabInbox,
                    subtitle: l10n.boardsEmptyInbox,
                  ),
          );
        }
        return ClampedBody(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return PostTile(
                post: post,
                viewerMember: viewerMember,
                showAudiencePill: false,
                onTap: () => _openBoardPost(context, post.id),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Inbox filter bar
// ---------------------------------------------------------------------------

/// Top-bar leading button that drives the board member filter.
///
/// Displays:
///   - filter null (All): a group icon
///   - filter == memberId: that member's [MemberAvatar]
///
/// Tap opens a [BlurPopupAnchor] dropdown with one row per visible member plus
/// an "All members" entry. Mirrors the avatar-trigger style of the chat member
/// selector.
class _BoardsMemberFilterButton extends ConsumerWidget {
  const _BoardsMemberFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final membersAsync = ref.watch(userVisibleMemberListProvider);
    final members = membersAsync.value ?? const <Member>[];
    final filterId = ref.watch(inboxViewFilterProvider);
    final terms = watchTerminology(context, ref);
    final allMembersLabel = l10n.onboardingChatChannelAllMembers(
      terms.plural,
      terms.pluralLower,
    );

    if (members.isEmpty) return const SizedBox.shrink();

    final currentMember = filterId != null
        ? members.where((m) => m.id == filterId).firstOrNull
        : null;
    final prefer = ref.watch(memberNamePreferDisplayProvider);
    final currentMemberName = currentMember?.effectiveName(
      preferDisplayName: prefer,
    );

    // Trigger: full 44pt avatar matching the + button's circle, with a
    // small down-chevron pip overlaying the bottom-right corner.
    const hitSize = PrismTokens.topBarActionSize; // 44
    const avatarSize = hitSize;
    final trigger = SizedBox(
      width: hitSize,
      height: hitSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (currentMember != null)
            MemberAvatar(
              memberId: currentMember.id,
              avatarImageData: currentMember.avatarImageData,
              memberName: currentMemberName,
              emoji: currentMember.emoji,
              customColorEnabled: currentMember.customColorEnabled,
              customColorHex: currentMember.customColorHex,
              size: avatarSize,
              deferAvatarLookup: true,
            )
          else
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                AppIcons.group,
                size: 23,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          // Down-chevron pip at the bottom-right, signaling the dropdown
          // affordance without crowding the avatar.
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.85,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final filterLabel = currentMemberName != null
        ? l10n.boardsViewFilterMember(currentMemberName)
        : allMembersLabel;

    return Semantics(
      label: '$allMembersLabel, $filterLabel',
      button: true,
      child: MemberSelectorPopup(
        preferredDirection: BlurPopupDirection.down,
        members: members,
        termPlural: terms.plural,
        searchTitle: allMembersLabel,
        selectedMemberId: filterId,
        semanticLabel: allMembersLabel,
        specialRows: [
          MemberSelectorPopupSpecialRow(
            title: allMembersLabel,
            selected: filterId == null,
            selectedColor: theme.colorScheme.primary,
            leading: SizedBox(
              width: 32,
              height: 32,
              child: Icon(AppIcons.group, size: 22),
            ),
            onSelected: () =>
                ref.read(inboxViewFilterProvider.notifier).setFilter(null),
          ),
        ],
        onMemberSelected: (memberId) =>
            ref.read(inboxViewFilterProvider.notifier).setFilter(memberId),
        child: trigger,
      ),
    );
  }
}
