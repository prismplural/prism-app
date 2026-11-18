import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/models/member_board_post_permissions.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/boards/widgets/compose_post_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/markdown/spoiler_syntax.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// The same visibility word is rendered by the pill and measured by its header.
String _audienceLabel(String audience) =>
    audience == 'public' ? 'public' : 'private';

// ---------------------------------------------------------------------------
// Inline markdown stripper — for accessibility labels only.
// ---------------------------------------------------------------------------

/// Strips common Markdown syntax characters from [text] for use in
/// accessibility (Semantics) labels. Intentionally lossy — only suitable for
/// plain-text summaries passed to [Semantics.label].
String stripMarkdownForA11y(String text) {
  var result = text;
  // Replace `||spoiler||` spans with the word "spoiler" so screen readers
  // never announce the hidden plaintext — the visible body renders these as
  // tap-to-reveal pills, and the a11y label must not leak past them.
  result = result.replaceAll(spoilerRegex, 'spoiler');
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  result = result.replaceAll(RegExp(r'\*\*|__'), '');
  result = result.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
  result = result.replaceAll(RegExp(r'(?<!_)_(?!_)'), '');
  result = result.replaceAll('~~', '');
  result = result.replaceAll('`', '');
  result = result.replaceAll(RegExp(r'<[^>]*>'), '');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return result;
}

/// Social-post style card for a single [MemberBoardPost].
///
/// Layout:
/// ```
/// ┌────────────────────────────────────────────┐
/// │  [avatar]  Author name           · pill    │   ← header
/// │                                             │
/// │   Optional Title (bold)                     │
/// │   Body text here, larger weight,            │   ← body
/// │   prominent middle area...                  │
/// │                                             │
/// │  → recipient · 2h ago · edited       …      │   ← footer
/// └────────────────────────────────────────────┘
/// ```
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

  /// When true, shows a small "public" / "private" pill badge in the header.
  final bool showAudiencePill;

  /// Optional tap override. When null, tapping pushes the post detail route.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorAsync = post.authorId != null
        ? ref.watch(activeMemberByIdProvider(post.authorId!))
        : const AsyncValue<Member?>.data(null);
    final targetAsync = post.targetMemberId != null
        ? ref.watch(activeMemberByIdProvider(post.targetMemberId!))
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

  String _buildA11yLabel(BuildContext context, bool prefer) {
    final l10n = context.l10n;
    final authorName =
        author?.effectiveName(preferDisplayName: prefer) ??
        post.authorId ??
        l10n.boardsTileRemovedMember;
    final isPublic = post.audience == 'public';
    final audienceText = isPublic ? 'public' : 'private';

    String recipientPart = '';
    if (post.targetMemberId != null) {
      final targetName =
          target?.effectiveName(preferDisplayName: prefer) ??
          post.targetMemberId ??
          l10n.boardsTileRemovedMember;
      recipientPart = ' to $targetName';
    } else if (isPublic) {
      recipientPart = ' ${l10n.boardsTileToEveryone}';
    }

    final timestamp = post.writtenAt.toRelativeString();
    final editedSuffix = post.editedAt != null
        ? ', ${l10n.boardsTileEdited}'
        : '';
    final titlePart = post.title != null && post.title!.isNotEmpty
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
            ComposePostSheet.show(context, editingPostId: post.id);
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
        ref.read(memberBoardPostNotifierProvider.notifier).deletePost(post.id),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final prefer = ref.watch(memberNamePreferDisplayProvider);

    final perms = MemberBoardPostPermissions(
      post: post,
      speakingAsMember: viewerMember,
    );
    final hasActions = perms.canEdit || perms.canDelete;

    // Members with a custom color keep it (they opted in to the contrast
    // tradeoff). Members without one fall back to onSurface for max
    // readability against the tinted header banner — primary is too muted
    // here.
    final authorColor =
        (author != null &&
            author!.customColorEnabled &&
            author!.customColorHex != null)
        ? AppColors.fromHex(author!.customColorHex!)
        : theme.colorScheme.onSurface;

    final isDesktopOrWeb =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        kIsWeb;

    final headerBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    final card = PrismSurface(
      tone: PrismSurfaceTone.subtle,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(vertical: 6),
      borderRadius: PrismTokens.radiusMedium,
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else {
          context.push(AppRoutePaths.boardPost(post.id));
        }
      },
      semanticLabel: _buildA11yLabel(context, prefer),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header banner: [avatar] sender → [avatar] receiver  ··· time
          DecoratedBox(
            decoration: BoxDecoration(
              color: headerBgColor,
              border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              // Measured fit, not a container that reflows on its own: the metadata
              // keeps today's inline position beside the participant strip whenever it
              // fits next to the strip's non-shrinkable pieces, and a long user name
              // keeps ellipsising on that one line. Only metadata that genuinely cannot
              // fit - the 3.375x case that overflowed by 90px - takes its own line, and
              // it then wraps internally rather than overflowing the card.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final timestampLabel = _formatTimestamp(
                    post.writtenAt,
                    context,
                  );
                  final hasMenu = hasActions && isDesktopOrWeb;
                  final fitsInline =
                      _headerMetaWidth(
                            context,
                            theme: theme,
                            timestamp: timestampLabel,
                            audience: post.audience,
                            showAudiencePill: showAudiencePill,
                            hasMenu: hasMenu,
                          ) +
                          8 +
                          _headerStripFixedWidth(
                            context,
                            theme: theme,
                            hasTargetAvatar: post.targetMemberId != null,
                          ) <=
                      constraints.maxWidth;

                  final participants = _PostHeaderParticipants(
                    author: author,
                    target: target,
                    post: post,
                    authorColor: authorColor,
                    theme: theme,
                    l10n: l10n,
                    prefer: prefer,
                  );
                  final timestamp = Text(
                    timestampLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 11,
                    ),
                  );
                  final pill = showAudiencePill
                      ? _AudiencePill(audience: post.audience, theme: theme)
                      : null;
                  final menu = hasMenu
                      ? _InlineMenuButton(
                          post: post,
                          viewerMember: viewerMember,
                          buildActions: _buildActions,
                        )
                      : null;

                  if (fitsInline) {
                    // Unchanged default geometry: names ellipsise, metadata inline.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: participants),
                        const SizedBox(width: 8),
                        if (pill != null) ...[pill, const SizedBox(width: 8)],
                        timestamp,
                        if (menu != null) ...[const SizedBox(width: 4), menu],
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: participants),
                          if (menu != null) ...[const SizedBox(width: 4), menu],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [?pill, timestamp],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── Body: optional title + body text + edited footnote
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title != null && post.title!.isNotEmpty) ...[
                  Text(
                    redactSpoilers(post.title!),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],
                // Body text is copyable. `SelectionArea` keeps the body's
                // plain-text semantics (a selectable text field would announce
                // itself as an editable field) and lets one selection span
                // every rendered block of the body.
                //
                // Interaction: long-press/drag on the body selects text, so
                // the tile's long-press action menu is offered from the
                // header/footer instead (plus the trailing "…" menu on
                // desktop/web and the detail screen's app-bar actions). On
                // Android/Fuchsia a gesture starting on the body selects
                // rather than pages, so board paging comes from header/footer
                // space or the segmented control.
                SelectionArea(
                  child: PrismMarkdownText(
                    // Keyed by post id so a recycled tile never carries spoiler
                    // reveal state onto a different post with identical body
                    // text.
                    key: ValueKey('post-body-${post.id}'),
                    data: post.body,
                    baseStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.45,
                    ),
                  ),
                ),
                if (post.editedAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.boardsTileEdited,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                      fontStyle: FontStyle.italic,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (hasActions) {
      return BlurPopupAnchor(
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
        child: card,
      );
    }

    return card;
  }

  /// Width of one line of [text] as the header paints it.
  ///
  /// [style] is the style handed to `Text`; [prismTextStyleForMeasurement] applies the
  /// ambient [DefaultTextStyle] merge and the bold-text flag exactly as `Text` does, and
  /// the painter gets the inherited locale and height behaviour, so the measured line and
  /// the painted line resolve the same face.
  double _headerLineWidth(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: prismTextStyleForMeasurement(context, style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: prismTextHeightBehaviorFor(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Width the header metadata needs side by side, from the strings and styles it
  /// actually renders: the visibility word in the pill (+ its 16dp padding and the
  /// 8dp gap before it), the formatted timestamp, and the desktop menu when present.
  double _headerMetaWidth(
    BuildContext context, {
    required ThemeData theme,
    required String timestamp,
    required String audience,
    required bool showAudiencePill,
    required bool hasMenu,
  }) {
    var width = _headerLineWidth(
      context,
      timestamp,
      theme.textTheme.labelMedium?.copyWith(fontSize: 11),
    );
    if (showAudiencePill) {
      width +=
          8 +
          16 +
          _headerLineWidth(
            context,
            _audienceLabel(audience),
            theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          );
    }
    if (hasMenu) width += 4 + 26; // 4dp gap + the 18dp icon in its 4dp padding.
    return width;
  }

  /// Width the participant strip cannot give away: the author avatar and its gap, the
  /// gaps around the "to" connector, the connector itself, and the target avatar when
  /// the post has one. Both names are flexible and ellipsise, so they count as zero -
  /// a long name must never force the metadata off the line on its own.
  double _headerStripFixedWidth(
    BuildContext context, {
    required ThemeData theme,
    required bool hasTargetAvatar,
  }) {
    final to = _headerLineWidth(
      context,
      'to',
      theme.textTheme.labelMedium?.copyWith(fontSize: 12),
    );
    return 22 + 6 + 8 + to + 8 + (hasTargetAvatar ? 22 + 6 : 0);
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
// Header participants — [avatar] sender → [avatar] receiver (or "everyone")
// ---------------------------------------------------------------------------

/// Renders the inline participant strip for the card header banner.
///
/// Layout: `[author avatar] {author name} → [target avatar] {target name}`
/// for posts with a specific recipient, or `[author avatar] {author name} →
/// everyone` for public posts with no target.
class _PostHeaderParticipants extends StatelessWidget {
  const _PostHeaderParticipants({
    required this.author,
    required this.target,
    required this.post,
    required this.authorColor,
    required this.theme,
    required this.l10n,
    required this.prefer,
  });

  final Member? author;
  final Member? target;
  final MemberBoardPost post;
  final Color authorColor;
  final ThemeData theme;
  final AppLocalizations l10n;
  final bool prefer;

  @override
  Widget build(BuildContext context) {
    // Sender carries the new info — full strength + bold. Receiver is
    // predictable from context, so same size/family but lighter weight
    // and reduced opacity. The "to" connector stays compact + muted.
    final connectorStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      fontSize: 12,
    );
    final authorStyle = theme.textTheme.labelLarge?.copyWith(
      // 0.8 sits between the receiver (0.55) and body (1.0) — sender is
      // emphasised over context, but doesn't compete with the post body.
      color: authorColor.withValues(alpha: 0.8),
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );
    final receiverStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      fontWeight: FontWeight.w500,
      fontSize: 13,
    );

    final showTargetAvatar = post.targetMemberId != null;
    final authorName =
        author?.effectiveName(preferDisplayName: prefer) ??
        post.authorId ??
        l10n.boardsTileRemovedMember;
    final receiverName = post.targetMemberId != null
        ? (target?.effectiveName(preferDisplayName: prefer) ??
              l10n.boardsTileRemovedMember)
        : l10n.boardsTileEveryone;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MemberAvatar(
          avatarImageData: author?.avatarImageData,
          memberName: author?.effectiveName(preferDisplayName: prefer),
          emoji: author?.emoji ?? '❔',
          customColorEnabled: author?.customColorEnabled ?? false,
          customColorHex: author?.customColorHex,
          size: 22,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            authorName,
            style: authorStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text('to', style: connectorStyle),
        const SizedBox(width: 8),
        if (showTargetAvatar) ...[
          Opacity(
            opacity: 0.55,
            child: MemberAvatar(
              avatarImageData: target?.avatarImageData,
              memberName: target?.effectiveName(preferDisplayName: prefer),
              emoji: target?.emoji ?? '❔',
              customColorEnabled: target?.customColorEnabled ?? false,
              customColorHex: target?.customColorHex,
              size: 22,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            receiverName,
            style: showTargetAvatar ? receiverStyle : connectorStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
    final color = isPublic
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(8)),
      ),
      child: Text(
        _audienceLabel(audience),
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
  )
  buildActions;

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
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
