import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/models/member_board_post_permissions.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/post_detail_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// ---------------------------------------------------------------------------
// Inline markdown stripper — for accessibility labels only.
//
// Strips bold/italic/strikethrough/code, inline links (→ link text), and HTML
// tags so raw markdown syntax never appears in a screen-reader announcement.
// ---------------------------------------------------------------------------

/// Strips common Markdown syntax characters from [text] for use in
/// accessibility (Semantics) labels. Intentionally lossy — only suitable for
/// plain-text summaries passed to [Semantics.label].
String stripMarkdownForA11y(String text) {
  var result = text;

  // Inline links: [text](url) → text
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );

  // Bold (** and __)
  result = result.replaceAll(RegExp(r'\*\*|__'), '');

  // Italic (* and _) — single-character delimiters
  result = result.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
  result = result.replaceAll(RegExp(r'(?<!_)_(?!_)'), '');

  // Strikethrough (~~)
  result = result.replaceAll('~~', '');

  // Inline code (single backtick)
  result = result.replaceAll('`', '');

  // HTML tags
  result = result.replaceAll(RegExp(r'<[^>]*>'), '');

  // Collapse multiple whitespace / newlines
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

  return result;
}

// ---------------------------------------------------------------------------
// PostTile
//
// LOCKED API (E4 owns this file; E1/E3 import from here):
//
//   PostTile({
//     required MemberBoardPost post,
//     required Member? viewerMember,
//     bool showAudiencePill = false,
//     VoidCallback? onTap,
//   })
// ---------------------------------------------------------------------------

/// A list tile for a [MemberBoardPost].
///
/// Renders author avatar + name + recipient chip + timestamp + optional title
/// (bold) + body preview (MarkdownText, max 4 lines). Long-press or the inline
/// `…` button opens a [BlurPopupAnchor] context menu with edit/delete actions
/// gated by [MemberBoardPostPermissions].
///
/// Tap → opens [PostDetailSheet] unless [onTap] is provided.
///
/// **This file is the sole owner of `PostTile`. E1/E3 import from here.**
class PostTile extends ConsumerWidget {
  const PostTile({
    super.key,
    required this.post,
    required this.viewerMember,
    this.showAudiencePill = false,
    this.onTap,
  });

  final MemberBoardPost post;

  /// The member currently viewing — used for permission checks.
  final Member? viewerMember;

  /// When true, shows a small "public" / "private" pill badge.
  final bool showAudiencePill;

  /// Optional tap override. When null, tapping opens [PostDetailSheet].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Load the author and optional target member asynchronously.
    final authorAsync = post.authorId != null
        ? ref.watch(memberByIdProvider(post.authorId!))
        : const AsyncValue<Member?>.data(null);
    final targetAsync = post.targetMemberId != null
        ? ref.watch(memberByIdProvider(post.targetMemberId!))
        : const AsyncValue<Member?>.data(null);

    return _PostTileContent(
      post: post,
      author: authorAsync.value,
      target: targetAsync.value,
      viewerMember: viewerMember,
      showAudiencePill: showAudiencePill,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal tile content widget
// ---------------------------------------------------------------------------

class _PostTileContent extends ConsumerWidget {
  const _PostTileContent({
    required this.post,
    required this.author,
    required this.target,
    required this.viewerMember,
    required this.showAudiencePill,
    required this.onTap,
  });

  final MemberBoardPost post;
  final Member? author;
  final Member? target;
  final Member? viewerMember;
  final bool showAudiencePill;
  final VoidCallback? onTap;

  /// Plain-text Semantics label composed per spec.
  String _buildA11yLabel(BuildContext context) {
    final l10n = context.l10n;
    final authorName =
        author?.name ?? post.authorId ?? l10n.boardsTileRemovedMember;
    final isPublic = post.audience == 'public';
    final audienceText = isPublic ? 'public' : 'private';

    String recipientPart = '';
    if (post.targetMemberId != null) {
      final targetName =
          target?.name ?? post.targetMemberId ?? l10n.boardsTileRemovedMember;
      recipientPart = ' to $targetName';
    } else if (isPublic) {
      recipientPart = ' ${l10n.boardsTileToEveryone}';
    }

    final timestamp = post.writtenAt.toRelativeString();
    final editedSuffix =
        post.editedAt != null ? ', ${l10n.boardsTileEdited}' : '';
    final titlePart =
        post.title != null && post.title!.isNotEmpty
        ? '${stripMarkdownForA11y(post.title!)}: '
        : '';
    final plainBody = stripMarkdownForA11y(post.body);

    return '$audienceText message from $authorName$recipientPart, '
        '$timestamp$editedSuffix: $titlePart$plainBody';
  }

  List<_ContextAction> _buildActions(
    BuildContext context,
    WidgetRef ref,
    VoidCallback closePopup,
  ) {
    final perms = MemberBoardPostPermissions(
      post: post,
      speakingAsMember: viewerMember,
    );
    final l10n = context.l10n;
    final actions = <_ContextAction>[];

    if (perms.canEdit) {
      actions.add(
        _ContextAction(
          icon: Icons.edit_outlined,
          label: l10n.boardsDetailEdit,
          isDestructive: false,
          onTap: () {
            closePopup();
            // TODO(E2): Replace with ComposePostSheet.show(context, editingPostId: post.id)
            // once E2 lands.
            PrismToast.show(context, message: 'Edit coming soon');
          },
        ),
      );
    }

    if (perms.canDelete) {
      actions.add(
        _ContextAction(
          icon: Icons.delete_outline,
          label: l10n.boardsDetailDelete,
          isDestructive: true,
          onTap: () {
            closePopup();
            _confirmDelete(context, ref);
          },
        ),
      );
    }

    return actions;
  }

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
    final hasActions = perms.canEdit || perms.canDelete;

    final authorColor =
        (author != null &&
            author!.customColorEnabled &&
            author!.customColorHex != null)
        ? AppColors.fromHex(author!.customColorHex!)
        : theme.colorScheme.primary;

    // Show inline … always on desktop/web for parity with mouse-only UX.
    final isDesktopOrWeb =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        kIsWeb;

    Widget tileBody = Semantics(
      button: true,
      label: _buildA11yLabel(context),
      child: InkWell(
        onTap: () {
          if (onTap != null) {
            onTap!();
          } else {
            PostDetailSheet.show(context, postId: post.id);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(
                avatarImageData: author?.avatarImageData,
                memberName: author?.name,
                emoji: author?.emoji ?? '❔',
                customColorEnabled: author?.customColorEnabled ?? false,
                customColorHex: author?.customColorHex,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: name, recipient chip, timestamp, edited suffix
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        Text(
                          author?.name ??
                              post.authorId ??
                              l10n.boardsTileRemovedMember,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: authorColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.05,
                          ),
                        ),
                        _RecipientChip(
                          post: post,
                          target: target,
                          theme: theme,
                          l10n: l10n,
                        ),
                        Text(
                          _formatTimestamp(post.writtenAt, context),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                            fontSize: 11,
                            height: 1.0,
                          ),
                        ),
                        if (post.editedAt != null)
                          Text(
                            l10n.boardsTileEdited,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                              fontSize: 11,
                              height: 1.0,
                            ),
                          ),
                        if (showAudiencePill)
                          _AudiencePill(
                            audience: post.audience,
                            theme: theme,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Optional bold title
                    if (post.title != null && post.title!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          post.title!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // Body — MarkdownText (4-line clamp via paragraph style)
                    MarkdownText(
                      data: post.body,
                      baseStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              // Inline … always visible on desktop/web.
              if (hasActions && isDesktopOrWeb)
                _InlineMenuButton(
                  post: post,
                  viewerMember: viewerMember,
                  buildActions: _buildActions,
                ),
            ],
          ),
        ),
      ),
    );

    // Wrap in BlurPopupAnchor for long-press on all platforms.
    if (hasActions) {
      tileBody = BlurPopupAnchor(
        trigger: BlurPopupTrigger.longPress,
        width: 240,
        itemCount: _buildActions(context, ref, () {}).length,
        itemBuilder: (ctx, index, close) {
          final actions = _buildActions(ctx, ref, close);
          if (index >= actions.length) return const SizedBox.shrink();
          final action = actions[index];
          return PrismListRow(
            leading: Icon(
              action.icon,
              color: action.isDestructive ? theme.colorScheme.error : null,
            ),
            title: Text(
              action.label,
              style: action.isDestructive
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            onTap: action.onTap,
          );
        },
        child: tileBody,
      );
    }

    return tileBody;
  }

  String _formatTimestamp(DateTime dt, BuildContext context) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd(context.dateLocale).format(dt);
  }
}

// ---------------------------------------------------------------------------
// Recipient chip
// ---------------------------------------------------------------------------

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({
    required this.post,
    required this.target,
    required this.theme,
    required this.l10n,
  });

  final MemberBoardPost post;
  final Member? target;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final isPublic = post.audience == 'public';

    if (post.targetMemberId == null && isPublic) {
      return Text(
        '· ${l10n.boardsTileToEveryone}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 11,
        ),
      );
    }

    if (post.targetMemberId != null) {
      final name = target?.name ?? l10n.boardsTileRemovedMember;
      return Text(
        '→ $name',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 11,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Audience pill
// ---------------------------------------------------------------------------

class _AudiencePill extends StatelessWidget {
  const _AudiencePill({required this.audience, required this.theme});

  final String audience;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isPublic = audience == 'public';
    final color =
        isPublic ? theme.colorScheme.primary : theme.colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(8),
        ),
      ),
      child: Text(
        isPublic ? 'public' : 'private',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline … button (desktop/web parity)
// ---------------------------------------------------------------------------

class _InlineMenuButton extends ConsumerWidget {
  const _InlineMenuButton({
    required this.post,
    required this.viewerMember,
    required this.buildActions,
  });

  final MemberBoardPost post;
  final Member? viewerMember;
  final List<_ContextAction> Function(
    BuildContext context,
    WidgetRef ref,
    VoidCallback closePopup,
  ) buildActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = buildActions(context, ref, () {});
    if (actions.isEmpty) return const SizedBox.shrink();

    return BlurPopupAnchor(
      trigger: BlurPopupTrigger.tap,
      width: 240,
      itemCount: actions.length,
      itemBuilder: (ctx, index, close) {
        final freshActions = buildActions(ctx, ref, close);
        if (index >= freshActions.length) return const SizedBox.shrink();
        final action = freshActions[index];
        return PrismListRow(
          leading: Icon(
            action.icon,
            color: action.isDestructive ? theme.colorScheme.error : null,
          ),
          title: Text(
            action.label,
            style: action.isDestructive
                ? TextStyle(color: theme.colorScheme.error)
                : null,
          ),
          onTap: action.onTap,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.more_horiz,
          size: 18,
          color:
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context-menu action descriptor
// ---------------------------------------------------------------------------

class _ContextAction {
  const _ContextAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
}
