import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Full paginated list of public board posts by or about a given member.
///
/// Reached via `/boards/member/:memberId`. The `+` action opens the compose
/// sheet pre-targeted at this member.
class MemberBoardScreen extends ConsumerWidget {
  const MemberBoardScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(activeMemberByIdProvider(memberId));
    final member = memberAsync.value;

    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(activeMemberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    return PrismPageScaffold(
      topBar: _MemberBoardTopBar(
        member: member,
        onComposeTap: () => _openCompose(context),
      ),
      body: _MemberBoardBody(memberId: memberId, viewerMember: viewerMember),
    );
  }

  void _openCompose(BuildContext context) {
    ComposePostSheet.show(context, defaultTargetMemberId: memberId);
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _MemberBoardTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _MemberBoardTopBar({required this.member, required this.onComposeTap});

  final Member? member;
  final VoidCallback onComposeTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final leadingAvatar = member != null
        ? MemberAvatar(
            avatarImageData: member!.avatarImageData,
            memberName: member!.name,
            emoji: member!.emoji,
            customColorEnabled: member!.customColorEnabled,
            customColorHex: member!.customColorHex,
            size: 32,
          )
        : null;

    return PrismTopBar(
      title: l10n.memberBoardScreenTitle,
      subtitle: member?.name,
      leading: leadingAvatar,
      showBackButton: leadingAvatar == null,
      trailing: PrismTopBarAction(
        icon: AppIcons.add,
        tooltip: l10n.add,
        onPressed: onComposeTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — paginated list
// ---------------------------------------------------------------------------

class _MemberBoardBody extends ConsumerStatefulWidget {
  const _MemberBoardBody({required this.memberId, required this.viewerMember});

  final String memberId;
  final Member? viewerMember;

  @override
  ConsumerState<_MemberBoardBody> createState() => _MemberBoardBodyState();
}

class _MemberBoardBodyState extends ConsumerState<_MemberBoardBody> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;

    final feed = ref.read(memberBoardFeedProvider(widget.memberId));
    if (feed.isLoading) return;
    final loaded = feed.value?.length ?? 0;
    final currentLimit = ref.read(memberBoardLimitProvider(widget.memberId));
    if (loaded >= currentLimit) {
      ref
          .read(memberBoardLimitProvider(widget.memberId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final postsAsync = ref.watch(memberBoardFeedProvider(widget.memberId));

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
        if (posts.isEmpty) {
          return EmptyState(
            icon: const Icon(Icons.forum_outlined),
            title: l10n.memberBoardScreenTitle,
            subtitle: l10n.memberBoardEmpty,
          );
        }

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              sliver: SliverList.builder(
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  return PostTile(
                    post: posts[index],
                    viewerMember: widget.viewerMember,
                    showAudiencePill: false,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
