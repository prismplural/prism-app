import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// List tile for a conversation in the conversation list.
///
/// Uses the same row layout as session tiles: avatar + title/subtitle + trailing.
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
    final speakingAs = ref.watch(speakingAsProvider);
    final lastMessageAsync = ref.watch(lastMessageProvider(conversation.id));
    final participantMapAsync = ref.watch(
      membersByIdsProvider(memberIdsKey(conversation.participantIds)),
    );

    final bool hasUnread = _hasUnread(speakingAs);
    final unreadCount = ref.watch(unreadMessageCountProvider(conversation.id));
    final bool isArchived =
        speakingAs != null && conversation.archivedByMemberIds.contains(speakingAs);

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildLeading(context, ref),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayTitle(participantMapAsync, speakingAs),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            hasUnread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    lastMessageAsync.when(
                      data: (lastMessage) {
                        if (lastMessage == null) {
                          return Text(
                            'No messages yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        }
                        return _MessagePreview(
                          message: lastMessage,
                          hasUnread: hasUnread,
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _relativeTimestamp(conversation.lastActivityAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasUnread
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Badge(
                      label: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                      ),
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );

    // Use ColorFiltered instead of Opacity to avoid an extra compositing layer.
    if (isArchived) {
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

  Widget _buildLeading(BuildContext context, WidgetRef ref) {
    if (conversation.emoji != null) {
      return TintedGlassSurface.circle(
        size: 40,
        child: MemberAvatar.centeredEmoji(
          conversation.emoji!,
          fontSize: 20,
        ),
      );
    }

    // For DMs, show the other participant's avatar
    if (conversation.isDirectMessage) {
      final speakingAs = ref.watch(speakingAsProvider);
      final otherId = conversation.participantIds
          .where((id) => id != speakingAs)
          .firstOrNull;
      if (otherId != null) {
        final memberAsync = ref.watch(memberByIdProvider(otherId));
        return memberAsync.when(
          data: (member) {
            if (member == null) {
              return _fallbackAvatar(context, Icons.person);
            }
            return MemberAvatar(
              avatarImageData: member.avatarImageData,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 40,
            );
          },
          loading: () => _fallbackAvatar(context, Icons.person),
          error: (_, _) => _fallbackAvatar(context, Icons.person),
        );
      }
    }

    return _fallbackAvatar(context, Icons.group);
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

  String _displayTitle(
    AsyncValue<Map<String, Member>> participantMapAsync,
    String? speakingAs,
  ) {
    if (conversation.title != null &&
        conversation.title!.isNotEmpty) {
      return conversation.title!;
    }

    // For DMs, show the other participant's name
    return participantMapAsync.when(
      data: (participantMap) {
        final otherNames = conversation.participantIds
            .where((id) => id != speakingAs)
            .map((id) => participantMap[id]?.name ?? 'Unknown')
            .toList();
        if (otherNames.isEmpty) return 'Conversation';
        return otherNames.join(', ');
      },
      loading: () => 'Loading...',
      error: (_, _) => 'Conversation',
    );
  }

  bool _hasUnread(String? speakingAs) {
    if (speakingAs == null) return false;
    final lastRead = conversation.lastReadTimestamps[speakingAs];
    if (lastRead == null) {
      return conversation.lastActivityAt.isAfter(conversation.createdAt);
    }
    return conversation.lastActivityAt.isAfter(lastRead);
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

/// Separate ConsumerWidget so it can watch [memberByIdProvider] for the author.
class _MessagePreview extends ConsumerWidget {
  const _MessagePreview({
    required this.message,
    required this.hasUnread,
  });

  final ChatMessage message;
  final bool hasUnread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authorId = message.authorId;
    final authorName = authorId != null
        ? ref.watch(memberByIdProvider(authorId)).whenOrNull(
              data: (m) => m?.name,
            )
        : null;
    final prefix = authorName != null ? '$authorName: ' : '';

    // Resolve mention tokens to display names in the preview.
    final nameMap = ref.watch(memberNameMapProvider);
    final displayContent = replaceMentionsWithNames(message.content, nameMap);

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
              fontWeight: hasUnread ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
