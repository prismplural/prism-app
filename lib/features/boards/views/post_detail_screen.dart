import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/models/member_board_post_permissions.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Full-screen detail view for a single [MemberBoardPost].
///
/// Reached via push to `/boards/post/:postId`. Shows the complete body
/// (no clamping), title, author, timestamp, and edit/delete affordances.
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final postAsync = ref.watch(_postByIdStreamProvider(postId));

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: l10n.boardsPostDetailTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
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

          final speakingAsId = ref.watch(speakingAsProvider);
          final viewerAsync = speakingAsId != null
              ? ref.watch(memberByIdProvider(speakingAsId))
              : const AsyncValue<Member?>.data(null);
          final viewerMember = viewerAsync.value;

          return _PostDetailBody(post: post, viewerMember: viewerMember);
        },
      ),
    );
  }
}

final _postByIdStreamProvider =
    StreamProvider.autoDispose.family<MemberBoardPost?, String>((ref, id) {
  final repo = ref.watch(memberBoardPostsRepositoryProvider);
  return repo.watchPostById(id);
});

class _PostDetailBody extends ConsumerWidget {
  const _PostDetailBody({required this.post, required this.viewerMember});

  final MemberBoardPost post;
  final Member? viewerMember;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
        ref
            .read(memberBoardPostNotifierProvider.notifier)
            .deletePost(post.id),
      );
      if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final perms = MemberBoardPostPermissions(
      post: post,
      speakingAsMember: viewerMember,
    );

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

    return SingleChildScrollView(
      padding: PrismTokens.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Author header
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MemberAvatar(
                avatarImageData: author?.avatarImageData,
                memberName: author?.name,
                emoji: author?.emoji ?? '❔',
                customColorEnabled: author?.customColorEnabled ?? false,
                customColorHex: author?.customColorHex,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author?.name ??
                          post.authorId ??
                          l10n.boardsTileRemovedMember,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: authorColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        if (post.targetMemberId != null)
                          Text(
                            '→ ${target?.name ?? l10n.boardsTileRemovedMember}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else if (post.audience == 'public')
                          Text(
                            l10n.boardsTileToEveryone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          '·',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        Text(
                          post.writtenAt.toDateTimeString(context.dateLocale),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (post.editedAt != null)
                          Text(
                            '(${l10n.boardsTileEdited})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Optional title
          if (post.title != null && post.title!.isNotEmpty) ...[
            Text(
              post.title!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Body — no line clamp
          MarkdownText(
            data: post.body,
            baseStyle: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // ── Edit / delete actions
          if (perms.canEdit || perms.canDelete)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (perms.canEdit) ...[
                  PrismButton(
                    icon: Icons.edit_outlined,
                    label: l10n.boardsDetailEdit,
                    onPressed: () =>
                        ComposePostSheet.show(context, editingPostId: post.id),
                  ),
                  if (perms.canDelete) const SizedBox(width: 8),
                ],
                if (perms.canDelete)
                  PrismButton(
                    icon: Icons.delete_outline,
                    label: l10n.boardsDetailDelete,
                    tone: PrismButtonTone.destructive,
                    onPressed: () => _confirmDelete(context, ref),
                  ),
              ],
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
