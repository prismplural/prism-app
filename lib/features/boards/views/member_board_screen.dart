import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/post_tile.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

// ---------------------------------------------------------------------------
// MemberBoardScreen
//
// LOCKED API:
//   MemberBoardScreen({required String memberId})
// ---------------------------------------------------------------------------

/// Full paginated list of public board posts by or about a given member.
///
/// Navigated to via `/boards/member/:memberId` (registered in C3').
///
/// Shows a [PrismTopBar] with the member's name as title and avatar as leading,
/// a [SliverList.builder] over [memberBoardPostsProvider], and a `+` app-bar
/// button that opens the compose sheet when E2 lands.
class MemberBoardScreen extends ConsumerWidget {
  const MemberBoardScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));
    final member = memberAsync.value;

    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(memberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    return PrismPageScaffold(
      topBar: _MemberBoardTopBar(
        member: member,
        onComposeTap: () => _openCompose(context),
      ),
      body: _MemberBoardBody(
        memberId: memberId,
        viewerMember: viewerMember,
      ),
    );
  }

  void _openCompose(BuildContext context) {
    // TODO(E2): Replace with ComposePostSheet.show(context, defaultTargetMemberId: memberId)
    // once E2 lands.
    PrismToast.show(context, message: 'Compose coming soon');
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _MemberBoardTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _MemberBoardTopBar({
    required this.member,
    required this.onComposeTap,
  });

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

class _MemberBoardBody extends ConsumerWidget {
  const _MemberBoardBody({
    required this.memberId,
    required this.viewerMember,
  });

  final String memberId;
  final Member? viewerMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    // v1: render the first page only.
    // TODO(pagination): implement infinite scroll with keyset cursor.
    final firstPage = MemberBoardCursor(memberId: memberId);
    final postsAsync = ref.watch(memberBoardPostsProvider(firstPage));

    return postsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
          slivers: [
            SliverList.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PostTile(
                      post: post,
                      viewerMember: viewerMember,
                      showAudiencePill: false,
                    ),
                    if (index < posts.length - 1)
                      const Divider(height: 1, indent: 64),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}
