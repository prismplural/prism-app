import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// List tile for a conversation in the conversation list.
///
/// Uses the same row layout as session tiles: avatar + title/subtitle + trailing.
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
    final theme = Theme.of(context);
    final tileData = ref.watch(conversationTileDataProvider(conversation.id));

    // While the batched provider is loading, show a minimal placeholder.
    if (tileData == null) {
      return const SizedBox.shrink();
    }

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildLeading(context, tileData),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tileData.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: tileData.hasUnread
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _buildMessagePreview(context, tileData),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
                        tileData.unreadCount > 99
                            ? '99+'
                            : '${tileData.unreadCount}',
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
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );

    // Use ColorFiltered instead of Opacity to avoid an extra compositing layer.
    if (tileData.isArchived) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0, // R
          0, 1, 0, 0, 0, // G
          0, 0, 1, 0, 0, // B
          0, 0, 0, 0.6, 0, // A
        ]),
        child: child,
      );
    }
    return child;
  }

  Widget _buildLeading(BuildContext context, ConversationTileData tileData) {
    if (tileData.conversation.emoji != null) {
      return TintedGlassSurface.circle(
        size: 40,
        child: MemberAvatar.centeredEmoji(
          tileData.conversation.emoji!,
          fontSize: 20,
        ),
      );
    }

    // For DMs, show the other participant's avatar.
    if (tileData.conversation.isDirectMessage && tileData.dmPartner != null) {
      final member = tileData.dmPartner!;
      return MemberAvatar(
        avatarImageData: member.avatarImageData,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: 40,
      );
    }

    // DM with unknown partner or group without emoji.
    final icon = tileData.conversation.isDirectMessage
        ? AppIcons.person
        : AppIcons.group;
    return _fallbackAvatar(context, icon);
  }

  Widget _fallbackAvatar(BuildContext context, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Icon(
        icon,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildMessagePreview(
    BuildContext context,
    ConversationTileData tileData,
  ) {
    final theme = Theme.of(context);

    if (tileData.lastMessage == null) {
      return Text(
        'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final authorName = tileData.lastMessageAuthorName;
    final prefix = authorName != null ? '$authorName: ' : '';
    final displayContent = tileData.lastMessageDisplayContent ?? '';

    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty)
            TextSpan(
              text: prefix,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          TextSpan(
            text: displayContent,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: tileData.hasUnread ? FontWeight.w600 : null,
            ),
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
