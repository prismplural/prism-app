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
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
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

  /// Subtitle line under the author name: "to {recipient} · {full datetime}".
  /// Includes "(edited)" suffix when applicable.
  String _composeDetailSubtitle(
    BuildContext context,
    AppLocalizations l10n,
    Member? target,
  ) {
    final parts = <String>[];
    if (post.targetMemberId != null) {
      parts.add('to ${target?.name ?? l10n.boardsTileRemovedMember}');
    } else if (post.audience == 'public') {
      parts.add(l10n.boardsTileToEveryone);
    }
    parts.add(post.writtenAt.toDateTimeString(context.dateLocale));
    if (post.editedAt != null) {
      parts.add('(${l10n.boardsTileEdited})');
    }
    return parts.join(' · ');
  }

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
                    Text(
                      _composeDetailSubtitle(context, l10n, target),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
