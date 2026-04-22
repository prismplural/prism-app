import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// List tile for a conversation in the conversation list.
///
/// Built on [PrismListRow] for consistent sizing and touch targets.
/// Watches a single [conversationTileDataProvider] to reduce provider fan-out.
class ConversationTile extends ConsumerWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tileData = ref.watch(conversationTileDataProvider(conversation.id));

    if (tileData == null) {
      return const SizedBox.shrink();
    }

    Widget tile = PrismListRow(
      leading: _buildLeading(context, tileData),
      title: Text(
        tileData.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tileData.hasUnread
            ? const TextStyle(fontWeight: FontWeight.w700)
            : null,
      ),
      subtitle: _buildMessagePreview(context, tileData),
      trailing: _buildTrailing(context, tileData),
      onTap: onTap,
    );

    // Dim archived conversations. Opacity is acceptable here — each tile is a
    // shallow subtree and the engine folds constant opacity into the paint.
    if (tileData.isArchived) {
      tile = Opacity(opacity: 0.6, alwaysIncludeSemantics: true, child: tile);
    }

    return tile;
  }

  Widget _buildLeading(BuildContext context, ConversationTileData tileData) {
    if (tileData.conversation.emoji != null) {
      return TintedGlassSurface(
        width: 40,
        height: 40,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(20)),
        child: MemberAvatar.centeredEmoji(
          tileData.conversation.emoji!,
          fontSize: 20,
        ),
      );
    }

    if (isDirectMessageConversation(tileData.conversation) &&
        tileData.dmPartner != null) {
      final member = tileData.dmPartner!;
      return MemberAvatar(
        avatarImageData: member.avatarImageData,
        memberName: member.name,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: 40,
      );
    }

    final icon = isDirectMessageConversation(tileData.conversation)
        ? AppIcons.person
        : AppIcons.group;
    return _fallbackAvatar(context, icon);
  }

  Widget _fallbackAvatar(BuildContext context, IconData icon) {
    final theme = Theme.of(context);
    final shapes = PrismShapes.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: shapes.avatarShape(),
        borderRadius: shapes.avatarBorderRadius(),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildTrailing(BuildContext context, ConversationTileData tileData) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _relativeTimestamp(tileData.conversation.lastActivityAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: tileData.hasUnread
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (tileData.unreadCount > 0) ...[
              const SizedBox(height: 4),
              Badge(
                label: Text(
                  tileData.unreadCount > 99 ? '99+' : '${tileData.unreadCount}',
                ),
                child: const SizedBox.shrink(),
              ),
            ],
          ],
        ),
        const SizedBox(width: 4),
        Icon(
          AppIcons.chevronRightRounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ],
    );
  }

  Widget _buildMessagePreview(
    BuildContext context,
    ConversationTileData tileData,
  ) {
    if (tileData.lastMessage == null) {
      return Text(
        context.l10n.chatTileNoMessages,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final authorName = tileData.lastMessageAuthorName;
    final prefix = authorName != null ? '$authorName: ' : '';
    final displayContent = tileData.lastMessageDisplayContent ?? '';

    // `displayContent` is already `redactSpoilers`-ed upstream, so any
    // `||…||` spans show as `▮` blocks. Screen readers announce `▮`
    // literally as a block glyph, which is noise, so swap in the word
    // "spoiler" in the semantics label while keeping the visual glyphs.
    final contentA11yLabel = displayContent.replaceAll(
      RegExp(r'▮+'),
      'spoiler',
    );

    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty)
            TextSpan(
              text: prefix,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          TextSpan(
            text: displayContent,
            semanticsLabel: contentA11yLabel,
            style: tileData.hasUnread
                ? const TextStyle(fontWeight: FontWeight.w600)
                : null,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _relativeTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dateTime.month}/${dateTime.day}';
  }
}
