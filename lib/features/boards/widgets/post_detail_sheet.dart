import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/models/member_board_post_permissions.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// ---------------------------------------------------------------------------
// PostDetailSheet
//
// LOCKED API:
//   static Future<void> show(BuildContext context, {required String postId})
// ---------------------------------------------------------------------------

/// Full-detail view for a [MemberBoardPost].
///
/// Shows the complete body (no line-count clamp), title, author, timestamp,
/// and edit/delete affordances per [MemberBoardPostPermissions].
///
/// Use [PostDetailSheet.show] to present this as a [PrismSheet] bottom sheet.
class PostDetailSheet {
  // Utility class — not instantiable.
  PostDetailSheet._();

  /// Present the detail sheet via [PrismSheet].
  ///
  /// Reads the post by [postId] from the repository and resolves the
  /// viewer's identity from [speakingAsProvider].
  static Future<void> show(
    BuildContext context, {
    required String postId,
  }) {
    return PrismSheet.show(
      context: context,
      maxHeightFactor: 0.9,
      builder: (sheetCtx) => _PostDetailSheetBody(postId: postId),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal: loading/error gate
// ---------------------------------------------------------------------------

class _PostDetailSheetBody extends ConsumerWidget {
  const _PostDetailSheetBody({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(_postByIdStreamProvider(postId));

    return postAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: PrismSpinner(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error loading post: $e'),
      ),
      data: (post) {
        if (post == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Post not found')),
          );
        }

        // Resolve viewer for permission checks.
        final speakingAsId = ref.watch(speakingAsProvider);
        final viewerAsync = speakingAsId != null
            ? ref.watch(memberByIdProvider(speakingAsId))
            : const AsyncValue<Member?>.data(null);
        final viewerMember = viewerAsync.value;

        return _PostDetailContent(
          post: post,
          viewerMember: viewerMember,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Internal: provider — post-by-ID stream
// ---------------------------------------------------------------------------

final _postByIdStreamProvider =
    StreamProvider.autoDispose.family<MemberBoardPost?, String>((ref, id) {
  final repo = ref.watch(memberBoardPostsRepositoryProvider);
  return repo.watchPostById(id);
});

// ---------------------------------------------------------------------------
// Internal: detail content
// ---------------------------------------------------------------------------

class _PostDetailContent extends ConsumerWidget {
  const _PostDetailContent({
    required this.post,
    required this.viewerMember,
  });

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
      if (context.mounted) Navigator.of(context).pop();
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MemberAvatar(
                avatarImageData: author?.avatarImageData,
                memberName: author?.name,
                emoji: author?.emoji ?? '❔',
                customColorEnabled: author?.customColorEnabled ?? false,
                customColorHex: author?.customColorHex,
                size: 40,
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
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: authorColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        // Recipient chip
                        if (post.targetMemberId != null)
                          Text(
                            '→ ${target?.name ?? l10n.boardsTileRemovedMember}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else if (post.audience == 'public')
                          Text(
                            '· ${l10n.boardsTileToEveryone}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        // Full timestamp
                        Text(
                          post.writtenAt.toDateTimeString(
                            context.dateLocale,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                          ),
                        ),
                        // Edited marker
                        if (post.editedAt != null)
                          Text(
                            '(${l10n.boardsTileEdited})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
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

          const SizedBox(height: 16),

          // Optional title
          if (post.title != null && post.title!.isNotEmpty) ...[
            Text(
              post.title!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Full body — no line-count clamp
          MarkdownText(
            data: post.body,
            baseStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          // Edit / delete action row
          if (perms.canEdit || perms.canDelete)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (perms.canEdit) ...[
                  PrismButton(
                    icon: Icons.edit_outlined,
                    label: l10n.boardsDetailEdit,
                    onPressed: () {
                      // TODO(E2): Replace with
                      // ComposePostSheet.show(context, editingPostId: post.id)
                      // once E2 lands.
                      Navigator.of(context).pop();
                      PrismToast.show(context, message: 'Edit coming soon');
                    },
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

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
