import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/models/member_board_post_permissions.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Full-screen detail view for a single [MemberBoardPost].
///
/// Reached via push to `/boards/post/:postId`. Shows the complete body
/// (no clamping), title, author, timestamp, and edit/delete affordances
/// in the app bar (when the viewer has permission).
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final postAsync = ref.watch(_postByIdStreamProvider(postId));

    final speakingAsId = ref.watch(speakingAsProvider);
    final viewerAsync = speakingAsId != null
        ? ref.watch(memberByIdProvider(speakingAsId))
        : const AsyncValue<Member?>.data(null);
    final viewerMember = viewerAsync.value;

    final post = postAsync.value;
    final perms = post == null
        ? null
        : MemberBoardPostPermissions(
            post: post,
            speakingAsMember: viewerMember,
          );

    final actions = <Widget>[
      if (perms?.canEdit ?? false)
        PrismTopBarAction(
          icon: Icons.edit_outlined,
          tooltip: l10n.boardsDetailEdit,
          onPressed: () =>
              ComposePostSheet.show(context, editingPostId: postId),
        ),
      if (perms?.canDelete ?? false)
        PrismTopBarAction(
          icon: Icons.delete_outline,
          tooltip: l10n.boardsDetailDelete,
          tint: Theme.of(context).colorScheme.error,
          onPressed: () => _confirmDelete(context, ref, postId),
        ),
    ];

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.boardsPostDetailTitle,
        showBackButton: true,
        actions: actions,
      ),
      bodyPadding: EdgeInsets.zero,
      safeAreaBottom: false,
      body: postAsync.when(
        loading: () => Center(
          child: PrismSpinner(color: Theme.of(context).colorScheme.primary),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error loading post: $e'),
        ),
        data: (post) {
          if (post == null) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(l10n.boardsPostDetailNotFound)),
            );
          }
          return _PostDetailBody(post: post);
        },
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  String postId,
) async {
  final l10n = context.l10n;
  final confirmed = await PrismDialog.confirm(
    context: context,
    title: l10n.boardsDeleteConfirmTitle,
    message: l10n.boardsDeleteConfirmBody,
    cancelLabel: l10n.cancel,
    confirmLabel: l10n.delete,
  );
  if (confirmed == true) {
    unawaited(
      ref.read(memberBoardPostNotifierProvider.notifier).deletePost(postId),
    );
    if (context.mounted) context.pop();
  }
}

final _postByIdStreamProvider =
    StreamProvider.autoDispose.family<MemberBoardPost?, String>((ref, id) {
  final repo = ref.watch(memberBoardPostsRepositoryProvider);
  return repo.watchPostById(id);
});

class _PostDetailBody extends ConsumerWidget {
  const _PostDetailBody({required this.post});

  final MemberBoardPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final authorAsync = post.authorId != null
        ? ref.watch(memberByIdProvider(post.authorId!))
        : const AsyncValue<Member?>.data(null);
    final author = authorAsync.value;

    final targetAsync = post.targetMemberId != null
        ? ref.watch(memberByIdProvider(post.targetMemberId!))
        : const AsyncValue<Member?>.data(null);
    final target = targetAsync.value;

    final authorColor =
        (author != null &&
            author.customColorEnabled &&
            author.customColorHex != null)
        ? AppColors.fromHex(author.customColorHex!)
        : theme.colorScheme.primary;

    final headerBgColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final dividerColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.07);

    final timestampLine = post.editedAt != null
        ? '${post.writtenAt.toDateTimeString(context.dateLocale)}  ·  ${l10n.boardsTileEdited}'
        : post.writtenAt.toDateTimeString(context.dateLocale);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header banner (full width, tinted, divider at bottom)
          DecoratedBox(
            decoration: BoxDecoration(
              color: headerBgColor,
              border: Border(
                bottom: BorderSide(color: dividerColor, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailParticipantsRow(
                    author: author,
                    target: target,
                    post: post,
                    authorColor: authorColor,
                    theme: theme,
                    l10n: l10n,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    timestampLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body content
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              24,
              20,
              32 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title != null && post.title!.isNotEmpty) ...[
                  Text(
                    post.title!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                MarkdownText(
                  data: post.body,
                  baseStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.55,
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

/// Detail-screen variant of the header participants row: bigger avatars,
/// stacks names beside avatars in an inline strip ([A] Sender → [B] Receiver).
class _DetailParticipantsRow extends StatelessWidget {
  const _DetailParticipantsRow({
    required this.author,
    required this.target,
    required this.post,
    required this.authorColor,
    required this.theme,
    required this.l10n,
  });

  final Member? author;
  final Member? target;
  final MemberBoardPost post;
  final Color authorColor;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final mutedStyle = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      fontWeight: FontWeight.w500,
    );
    final authorStyle = theme.textTheme.titleMedium?.copyWith(
      color: authorColor,
      fontWeight: FontWeight.w700,
    );
    final receiverStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );

    final showTargetAvatar = post.targetMemberId != null;
    final receiverName = post.targetMemberId != null
        ? (target?.name ?? l10n.boardsTileRemovedMember)
        : l10n.boardsTileToEveryone;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MemberAvatar(
              avatarImageData: author?.avatarImageData,
              memberName: author?.name,
              emoji: author?.emoji ?? '❔',
              customColorEnabled: author?.customColorEnabled ?? false,
              customColorHex: author?.customColorHex,
              size: 32,
            ),
            const SizedBox(width: 8),
            Text(
              author?.name ?? post.authorId ?? l10n.boardsTileRemovedMember,
              style: authorStyle,
            ),
          ],
        ),
        Text('to', style: mutedStyle),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTargetAvatar) ...[
              MemberAvatar(
                avatarImageData: target?.avatarImageData,
                memberName: target?.name,
                emoji: target?.emoji ?? '❔',
                customColorEnabled: target?.customColorEnabled ?? false,
                customColorHex: target?.customColorHex,
                size: 32,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              receiverName,
              style: showTargetAvatar ? receiverStyle : mutedStyle,
            ),
          ],
        ),
      ],
    );
  }
}
