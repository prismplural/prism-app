import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_attachment_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/chat/providers/voice_playback_provider.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/chat/widgets/media/expired_media.dart';
import 'package:prism_plurality/features/chat/widgets/media/image_bubble.dart';
import 'package:prism_plurality/features/chat/widgets/media/voice_bubble.dart';
import 'package:prism_plurality/features/chat/widgets/reaction_bar.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Individual message widget with author info, bubble, reactions.
class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showAuthorInfo = true,
    this.permissions,
    this.participantIds,
    this.authorMap,
    this.onScrollToReply,
    this.onReply,
    this.isHighlighted = false,
  });

  final ChatMessage message;

  /// Whether to show the avatar and author name.
  /// Set to false for grouped consecutive messages from the same author.
  final bool showAuthorInfo;

  /// Permission model for the current conversation. When provided, controls
  /// which context menu actions are shown (edit/delete). Falls back to
  /// `isOwn`-based logic when null.
  final ConversationPermissions? permissions;

  /// Set of current participant IDs in the conversation. Used to dim the
  /// avatar for members who have left the conversation.
  final Set<String>? participantIds;

  /// Pre-loaded author map from batch loading. If provided and the author is
  /// found in the map, the individual [memberByIdProvider] watch is skipped.
  final Map<String, Member>? authorMap;

  /// Called when the user taps the reply quote chip to scroll to the original message.
  final VoidCallback? onScrollToReply;

  /// Called when the user selects "Reply" from the context menu.
  final void Function(ChatMessage)? onReply;

  /// When true, shows a brief highlight flash overlay on the bubble.
  /// Used to visually indicate the message was scrolled-to.
  final bool isHighlighted;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _showAbsoluteTime = false;

  bool _appeared = false;

  void _toggleTimeFormat() {
    Haptics.light();
    setState(() {
      _showAbsoluteTime = !_showAbsoluteTime;
    });
  }

  // ---------------------------------------------------------------------------
  // Context menu helpers
  // ---------------------------------------------------------------------------

  int _contextMenuItemCount(bool isOwn) => _buildActions(isOwn).length + 2;

  List<_ContextAction> _buildActions(bool isOwn) {
    final actions = <_ContextAction>[];

    if (!widget.message.isSystemMessage) {
      actions.add(_ContextAction(
        icon: AppIcons.replyRounded,
        label: 'Reply',
        onTap: (close) {
          close();
          widget.onReply?.call(widget.message);
        },
      ));
    }

    actions.add(_ContextAction(
      icon: AppIcons.copyOutlined,
      label: 'Copy Text',
      onTap: (close) {
        Clipboard.setData(ClipboardData(text: widget.message.content));
        Haptics.light();
        close();
        PrismToast.show(context, message: 'Copied');
      },
    ));

    final perms = widget.permissions;
    if (perms != null) {
      if (perms.canEditMessage(widget.message.authorId)) {
        actions.add(_ContextAction(
          icon: AppIcons.editOutlined,
          label: 'Edit Message',
          onTap: (close) {
            close();
            _showEditDialog(context);
          },
        ));
      }
      if (perms.canDeleteMessage(widget.message.authorId)) {
        actions.add(_ContextAction(
          icon: AppIcons.deleteOutline,
          label: 'Delete',
          isDestructive: true,
          onTap: (close) {
            close();
            _confirmDelete(context);
          },
        ));
      }
    } else {
      // Fallback: old behavior for backwards compatibility.
      if (isOwn) {
        actions.add(_ContextAction(
          icon: AppIcons.editOutlined,
          label: 'Edit Message',
          onTap: (close) {
            close();
            _showEditDialog(context);
          },
        ));
        actions.add(_ContextAction(
          icon: AppIcons.deleteOutline,
          label: 'Delete',
          isDestructive: true,
          onTap: (close) {
            close();
            _confirmDelete(context);
          },
        ));
      }
    }

    return actions;
  }

  Widget _buildQuickReactionRow(VoidCallback close) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in AppConstants.quickReactions)
            GestureDetector(
              onTap: () {
                _toggleReaction(emoji);
                close();
              },
              child: TintedGlassSurface.circle(
                size: 36,
                child: MemberAvatar.centeredEmoji(emoji, fontSize: 20),
              ),
            ),
          GestureDetector(
            onTap: () async {
              close();
              final emoji = await PrismEmojiPicker.showPicker(context);
              if (emoji != null && mounted) {
                _toggleReaction(emoji);
              }
            },
            child: TintedGlassSurface.circle(
              size: 36,
              child: Icon(AppIcons.add, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleReaction(String emoji) {
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return;
    ref.read(chatNotifierProvider.notifier).toggleReaction(
          messageId: widget.message.id,
          emoji: emoji,
          memberId: speakingAs,
        );
  }

  Widget _buildActionTile(
    _ContextAction action,
    VoidCallback close,
    ThemeData theme,
  ) {
    final color = action.isDestructive ? theme.colorScheme.error : null;
    return PrismListRow(
      leading: Icon(action.icon, color: color),
      title: Text(
        action.label,
        style: color != null ? TextStyle(color: color) : null,
      ),
      onTap: () => action.onTap(close),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.message.content);
    var isSaving = false;
    PrismDialog.show(
      context: context,
      title: 'Edit Message',
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrismTextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              hintText: 'Message content',
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PrismButton(
                  label: 'Cancel',
                  enabled: !isSaving,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                const SizedBox(width: 8),
                PrismButton(
                  label: 'Save',
                  tone: PrismButtonTone.filled,
                  isLoading: isSaving,
                  enabled: !isSaving,
                  onPressed: () async {
                          final newContent = controller.text.trim();
                          if (newContent.isEmpty) {
                            Navigator.of(dialogContext).pop();
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            await ref
                                .read(chatNotifierProvider.notifier)
                                .editMessage(widget.message.id, newContent);
                          } catch (_) {
                            if (builderContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                            return;
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete Message',
      message: 'This message will be permanently deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      ref.read(chatNotifierProvider.notifier).deleteMessage(widget.message.id);
    }
  }

  Color _replyAuthorColor(String? authorId, ThemeData theme) {
    if (authorId == null || widget.authorMap == null) {
      return theme.colorScheme.primary;
    }
    final author = widget.authorMap![authorId];
    if (author != null && author.customColorEnabled && author.customColorHex != null) {
      return AppColors.fromHex(author.customColorHex!);
    }
    return theme.colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isSystemMessage) {
      return _SystemMessage(message: widget.message);
    }

    final theme = Theme.of(context);
    final speakingAs = ref.watch(speakingAsProvider);
    final isOwnMessage =
        speakingAs != null && widget.message.authorId == speakingAs;

    // Use batch-loaded author map if available, otherwise fall back to
    // individual provider watch.
    final batchAuthor = widget.authorMap != null && widget.message.authorId != null
        ? widget.authorMap![widget.message.authorId!]
        : null;

    if (batchAuthor != null) {
      return _buildBubble(
        context,
        author: batchAuthor,
        isOwn: isOwnMessage,
        theme: theme,
      );
    }

    final authorAsync = widget.message.authorId != null
        ? ref.watch(memberByIdProvider(widget.message.authorId!))
        : const AsyncValue<Member?>.data(null);

    return authorAsync.when(
      data: (author) => _buildBubble(
        context,
        author: author,
        isOwn: isOwnMessage,
        theme: theme,
      ),
      loading: () => _buildBubble(
        context,
        author: null,
        isOwn: isOwnMessage,
        theme: theme,
      ),
      error: (_, _) => _buildBubble(
        context,
        author: null,
        isOwn: isOwnMessage,
        theme: theme,
      ),
    );
  }

  Widget _buildAvatar(Member? author, double size) {
    final isDeparted = widget.participantIds != null &&
        widget.message.authorId != null &&
        !widget.participantIds!.contains(widget.message.authorId);

    final avatar = MemberAvatar(
      avatarImageData: author?.avatarImageData,
      emoji: author?.emoji ?? '?',
      customColorEnabled: author?.customColorEnabled ?? false,
      customColorHex: author?.customColorHex,
      size: size,
    );

    if (isDeparted) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0, // R
          0, 1, 0, 0, 0, // G
          0, 0, 1, 0, 0, // B
          0, 0, 0, 0.5, 0, // A
        ]),
        child: avatar,
      );
    }
    return avatar;
  }

  Widget _buildBubble(
    BuildContext context, {
    required Member? author,
    required bool isOwn,
    required ThemeData theme,
  }) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final authorColor =
        (author != null &&
            author.customColorEnabled &&
            author.customColorHex != null)
        ? AppColors.fromHex(author.customColorHex!)
        : theme.colorScheme.primary;

    final timeText = _showAbsoluteTime
        ? _formatTime(widget.message.timestamp)
        : _formatRelativeTime(widget.message.timestamp);
    const avatarSize = 36.0;
    const avatarGap = 12.0;
    final messageTextColor = theme.colorScheme.onSurface;
    final metaTextColor = theme.colorScheme.onSurfaceVariant;
    final topPadding = widget.showAuthorInfo ? 16.0 : 4.0;
    final bottomPadding = widget.message.reactions.isNotEmpty ? 7.0 : 2.0;

    final actions = _buildActions(isOwn);

    final slideWidget = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _appeared ? 1.0 : 0.0, end: 1.0),
      duration: disableAnimations ? Duration.zero : Anim.md,
      curve: Anim.enter,
      onEnd: () {
        if (!_appeared) _appeared = true;
      },
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 4.0),
            child: child,
          ),
        );
      },
      child: BlurPopupAnchor(
          trigger: BlurPopupTrigger.longPress,
          width: 260,
          itemCount: _contextMenuItemCount(isOwn),
          itemBuilder: (context, index, close) {
            if (index == 0) return _buildQuickReactionRow(close);
            if (index == 1) return const Divider(height: 1);
            final actionIndex = index - 2;
            return _buildActionTile(actions[actionIndex], close, theme);
          },
          child: GestureDetector(
            onTap: _toggleTimeFormat,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, topPadding, 14, bottomPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: avatarSize,
                    child: widget.showAuthorInfo
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _buildAvatar(author, avatarSize),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: avatarGap),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.message.replyToId != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _ReplyQuote(
                              authorName: widget.authorMap?[widget.message.replyToAuthorId]?.name
                                  ?? widget.message.replyToAuthorId
                                  ?? 'Unknown',
                              content: widget.message.replyToContent ?? '',
                              authorColor: _replyAuthorColor(widget.message.replyToAuthorId, theme),
                              isDeleted: widget.message.replyToContent == null,
                              onTap: widget.onScrollToReply,
                            ),
                          ),
                        if (widget.showAuthorInfo)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                Text(
                                  author?.name ?? 'Unknown',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: authorColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    height: 1.05,
                                  ),
                                ),
                                Text(
                                  timeText,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: metaTextColor.withValues(alpha: 0.88),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                    height: 1.0,
                                  ),
                                ),
                                if (widget.message.editedAt != null)
                                  Text(
                                    'edited',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: metaTextColor.withValues(alpha: 0.7),
                                      fontStyle: FontStyle.italic,
                                      fontSize: 11,
                                      height: 1.0,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(
                            right: 8,
                            top: widget.showAuthorInfo ? 0 : 1,
                          ),
                          child: Text.rich(
                            _buildContentSpan(
                              widget.message.content,
                              widget.authorMap,
                              theme,
                              messageTextColor,
                            ),
                          ),
                        ),
                        ..._buildAttachments(context, theme, authorColor),
                        if (widget.message.reactions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: ReactionBar(
                              messageId: widget.message.id,
                              reactions: widget.message.reactions,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );

    if (disableAnimations) {
      if (widget.isHighlighted) {
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
              ),
            ),
            slideWidget,
          ],
        );
      }
      return slideWidget;
    }

    if (!widget.isHighlighted) return slideWidget;

    return Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.08, end: 0.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOut,
            builder: (context, value, _) => ColoredBox(
              color: theme.colorScheme.primary.withValues(alpha: value),
            ),
          ),
        ),
        slideWidget,
      ],
    );
  }

  /// Build media attachment widgets for this message.
  ///
  /// Returns an empty list when no attachments exist. Each attachment is
  /// rendered as an [ImageBubble], [VoiceBubble], or [ExpiredMediaPlaceholder]
  /// based on its type and status.
  List<Widget> _buildAttachments(
    BuildContext context,
    ThemeData theme,
    Color authorColor,
  ) {
    final attachmentsAsync = ref.watch(
      mediaAttachmentsForMessageProvider(widget.message.id),
    );

    final attachments = attachmentsAsync.value;
    if (attachments == null || attachments.isEmpty) return const [];

    return [
      for (final attachment in attachments)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _buildSingleAttachment(attachment, authorColor),
        ),
    ];
  }

  Widget _buildSingleAttachment(MediaAttachment attachment, Color authorColor) {
    if (attachment.isDeleted) {
      return const ExpiredMedia();
    }

    switch (attachment.mediaType) {
      case 'image':
        return _buildImageAttachment(attachment);
      case 'voice':
        return _buildVoiceAttachment(attachment, authorColor);
      default:
        return const ExpiredMedia();
    }
  }

  Widget _buildVoiceAttachment(MediaAttachment attachment, Color authorColor) {
    final params = (
      mediaId: attachment.mediaId,
      encryptionKeyB64: attachment.encryptionKeyB64,
      ciphertextHash: attachment.contentHash,
      plaintextHash: attachment.plaintextHash,
    );
    final mediaAsync = ref.watch(mediaAudioFileProvider(params));

    // Select only fields relevant to this bubble so non-active bubbles skip
    // rebuilds from the ~10-20 Hz position stream.
    final mediaId = attachment.mediaId;
    final isActive = ref.watch(
      voicePlaybackProvider.select((s) => s.activeMediaId == mediaId),
    );
    final isPlaying = ref.watch(
      voicePlaybackProvider.select((s) => s.activeMediaId == mediaId && s.isPlaying),
    );
    final progress = ref.watch(
      voicePlaybackProvider.select((s) {
        if (s.activeMediaId != mediaId || s.duration.inMilliseconds <= 0) return 0.0;
        return s.position.inMilliseconds / s.duration.inMilliseconds;
      }),
    );
    final speed = ref.watch(
      voicePlaybackProvider.select((s) => s.activeMediaId == mediaId ? s.speed : 1.0),
    );

    return VoiceBubble(
      durationMs: attachment.durationMs,
      isPlaying: isPlaying,
      progress: progress,
      speed: speed,
      isLoading: mediaAsync.isLoading,
      onPlayPause: mediaAsync.value != null
          ? () => ref
              .read(voicePlaybackProvider.notifier)
              .togglePlayPause(attachment.mediaId, mediaAsync.value!)
          : null,
      onSeek: mediaAsync.value != null
          ? (fraction) {
              final totalMs = attachment.durationMs;
              ref
                  .read(voicePlaybackProvider.notifier)
                  .seek(Duration(milliseconds: (fraction * totalMs).round()));
            }
          : null,
      onSpeedTap: isActive
          ? () => ref.read(voicePlaybackProvider.notifier).cycleSpeed()
          : null,
    );
  }

  Widget _buildImageAttachment(MediaAttachment attachment) {
    final params = (
      mediaId: attachment.mediaId,
      encryptionKeyB64: attachment.encryptionKeyB64,
      ciphertextHash: attachment.contentHash,
      plaintextHash: attachment.plaintextHash,
    );
    final mediaAsync = ref.watch(mediaFileProvider(params));

    return ImageBubble(
      imageBytes: mediaAsync.value,
      isLoading: mediaAsync.isLoading,
      hasError: mediaAsync.hasError,
      width: attachment.width > 0 ? attachment.width.toDouble() : null,
      height: attachment.height > 0 ? attachment.height.toDouble() : null,
      blurhash: attachment.blurhash.isNotEmpty ? attachment.blurhash : null,
    );
  }

  /// Build a TextSpan that renders @[uuid] tokens with member colors.
  TextSpan _buildContentSpan(
    String content,
    Map<String, Member>? authorMap,
    ThemeData theme,
    Color defaultColor,
  ) {
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      color: defaultColor,
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.24,
    );

    final matches = mentionRegex.allMatches(content).toList();
    if (matches.isEmpty) {
      return TextSpan(text: content, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in matches) {
      // Plain text before this mention.
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      final memberId = match.group(1)!;
      final member = authorMap?[memberId];
      final name = member?.name ?? 'Unknown';
      final mentionColor =
          (member != null && member.customColorEnabled && member.customColorHex != null)
              ? AppColors.fromHex(member.customColorHex!)
              : theme.colorScheme.primary;

      spans.add(TextSpan(
        text: '@$name',
        style: baseStyle?.copyWith(
          color: mentionColor,
          fontWeight: FontWeight.w600,
        ),
      ));

      lastEnd = match.end;
    }

    // Trailing plain text.
    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
        style: baseStyle,
      ));
    }

    return TextSpan(children: spans);
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0
        ? 12
        : hour > 12
        ? hour - 12
        : hour;
    return '$displayHour:$minute $period';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatTime(dateTime);
  }
}

/// Helper describing a single action in the context menu.
class _ContextAction {
  const _ContextAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final void Function(VoidCallback close) onTap;
  final bool isDestructive;
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.authorName,
    required this.content,
    required this.authorColor,
    required this.isDeleted,
    this.onTap,
  });

  final String authorName;
  final String content;
  final Color authorColor;
  final bool isDeleted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: isDeleted
          ? 'Original message deleted'
          : 'Replying to $authorName: $content. Double-tap to scroll to message.',
      button: onTap != null && !isDeleted,
      child: GestureDetector(
        onTap: isDeleted ? null : onTap,
        child: Row(
            children: [
              Expanded(
              child: Container(
                decoration: !isDeleted
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(color: authorColor, width: 2),
                        ),
                      )
                    : null,
                padding: !isDeleted ? const EdgeInsets.only(left: 6) : EdgeInsets.zero,
                child: TintedGlassSurface(
                tint: isDeleted ? null : authorColor,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: isDeleted
                    ? Text(
                        'Original message deleted',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            authorName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: authorColor,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            content,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Center(
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
