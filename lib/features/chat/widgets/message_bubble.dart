import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/widgets/bio_image_element_builder.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_attachment_providers.dart';
import 'package:prism_plurality/features/chat/providers/media_state_providers.dart';
import 'package:prism_plurality/features/chat/providers/voice_playback_provider.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';
import 'package:prism_plurality/features/chat/utils/chat_author_options.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/utils/markdown_utils.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';
import 'package:prism_plurality/features/chat/widgets/chat_message_text.dart';
import 'package:prism_plurality/features/chat/widgets/media/expired_media.dart';
import 'package:prism_plurality/features/chat/widgets/gif_consent_dialog.dart';
import 'package:prism_plurality/features/chat/widgets/media/gif_bubble.dart';
import 'package:prism_plurality/features/chat/widgets/media/image_bubble.dart';
import 'package:prism_plurality/features/chat/widgets/media/voice_bubble.dart';
import 'package:prism_plurality/features/chat/widgets/reaction_bar.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/member_selector_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';

// Spoiler plaintext must not reach the accessibility label; keeping this as a
// named helper lets the screen-reader redaction test call the production path
// directly instead of mirroring the composition.
@visibleForTesting
String buildReplyQuoteA11yLabel(
  AppLocalizations l10n, {
  required String authorName,
  required String content,
  required bool isDeleted,
}) {
  if (isDeleted) return l10n.chatReplyQuoteDeletedSemantics;
  return l10n.chatReplyQuoteSemantics(authorName, redactSpoilers(content));
}

/// Individual message widget with author info, bubble, reactions.
class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.permissions,
    this.showAuthorInfo = true,
    this.authorMap,
    this.messageAuthorMap,
    this.onScrollToReply,
    this.onReply,
    this.isHighlighted = false,
  });

  final ChatMessage message;

  /// Whether to show the avatar and author name.
  /// Set to false for grouped consecutive messages from the same author.
  final bool showAuthorInfo;

  /// Permission model for the current conversation.
  final ConversationPermissions permissions;

  /// Pre-loaded author map from batch loading. If provided and the author is
  /// found in the map, the individual [activeMemberByIdProvider] watch is skipped.
  final Map<String, Member>? authorMap;

  /// Live messageId → current authorId map. The reply chip reads this so a
  /// later changeMessageAuthor on the parent is reflected immediately,
  /// bypassing the denormalized [ChatMessage.replyToAuthorId].
  final Map<String, String?>? messageAuthorMap;

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

  /// Anchors the offstage author picker so it can be shown programmatically
  /// after the long-press context menu dismisses.
  final _authorPickerKey = GlobalKey<BlurPopupAnchorState>();

  void _toggleTimeFormat() {
    Haptics.light();
    setState(() {
      _showAbsoluteTime = !_showAbsoluteTime;
    });
  }

  // ---------------------------------------------------------------------------
  // Context menu helpers
  // ---------------------------------------------------------------------------

  int _contextMenuItemCount() {
    final baseCount = _buildActions().length;
    final canReact = widget.permissions.canReact;
    return canReact ? baseCount + 1 : baseCount;
  }

  List<_ContextAction> _buildActions() {
    final actions = <_ContextAction>[];

    if (!widget.message.isSystemMessage) {
      actions.add(
        _ContextAction(
          icon: AppIcons.replyRounded,
          label: context.l10n.chatContextReply,
          onTap: (close) {
            close();
            widget.onReply?.call(widget.message);
          },
        ),
      );
    }

    actions.add(
      _ContextAction(
        icon: AppIcons.copyOutlined,
        label: context.l10n.chatContextCopyText,
        onTap: (close) {
          Clipboard.setData(ClipboardData(text: widget.message.content));
          Haptics.light();
          close();
          PrismToast.show(context, message: context.l10n.chatCopied);
        },
      ),
    );

    final perms = widget.permissions;
    final authorId = widget.message.authorId;
    if (perms.canChangeMessageAuthor(authorId) &&
        !widget.message.isSystemMessage) {
      final activeMembers =
          ref.watch(activeMemberListProvider).value ?? const [];
      // Pass currentAuthor so a departed-author DM still surfaces the action.
      final currentAuthor = (authorId != null)
          ? (widget.authorMap?[authorId])
          : null;
      final candidateIds = chatAuthorCandidateIds(
        perms.conversation,
        activeMembers,
        currentAuthorId: authorId,
        currentAuthor: currentAuthor,
      );
      if (candidateIds.length >= 2) {
        actions.add(
          _ContextAction(
            icon: Icons.swap_horiz,
            label: context.l10n.chatMessageChangeAuthor,
            onTap: _showAuthorPicker,
          ),
        );
      }
    }
    if (perms.canEditMessage(widget.message.authorId)) {
      actions.add(
        _ContextAction(
          icon: AppIcons.editOutlined,
          label: context.l10n.chatContextEditMessage,
          onTap: (close) {
            close();
            _showEditDialog(context);
          },
        ),
      );
    }
    if (perms.canDeleteMessage(widget.message.authorId)) {
      actions.add(
        _ContextAction(
          icon: AppIcons.deleteOutline,
          label: context.l10n.chatContextDelete,
          isDestructive: true,
          onTap: (close) {
            close();
            _confirmDelete(context);
          },
        ),
      );
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
            Semantics(
              button: true,
              label: context.l10n.chatMessageToggleReaction(emoji),
              child: GestureDetector(
                onTap: () {
                  _toggleReaction(emoji);
                  close();
                },
                child: TintedGlassSurface.circle(
                  size: 36,
                  child: MemberAvatar.centeredEmoji(emoji, fontSize: 20),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: context.l10n.chatMessageAddCustomReaction,
            child: GestureDetector(
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
          ),
        ],
      ),
    );
  }

  void _toggleReaction(String emoji) {
    if (!widget.permissions.canReact) return;
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return;
    ref
        .read(chatNotifierProvider.notifier)
        .toggleReaction(
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
    final controller = ChatMarkdownEditingController(
      text: widget.message.content,
    );
    var isSaving = false;
    PrismDialog.show(
      context: context,
      title: context.l10n.chatEditMessageTitle,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          controller.updateTheme(builderContext);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrismTextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                hintText: context.l10n.chatMessageContentHint,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PrismButton(
                    label: context.l10n.cancel,
                    enabled: !isSaving,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                  const SizedBox(width: 8),
                  PrismButton(
                    label: context.l10n.save,
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
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.chatDeleteMessageTitle,
      message: context.l10n.chatDeleteMessageMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      unawaited(
        ref
            .read(chatNotifierProvider.notifier)
            .deleteMessage(widget.message.id),
      );
    }
  }

  void _showAuthorPicker(VoidCallback close) {
    close();
    // Wait a frame so the context menu overlay dismisses before the picker
    // overlay opens.
    Future<void>.delayed(Duration.zero, () {
      if (!mounted) return;
      _authorPickerKey.currentState?.show();
    });
  }

  Color _replyAuthorColor(String? authorId, ThemeData theme) {
    if (authorId == null || widget.authorMap == null) {
      return theme.colorScheme.primary;
    }
    final author = widget.authorMap![authorId];
    if (author != null &&
        author.customColorEnabled &&
        author.customColorHex != null) {
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
    // Use batch-loaded author map if available, otherwise fall back to
    // individual provider watch.
    final batchAuthor =
        widget.authorMap != null && widget.message.authorId != null
        ? widget.authorMap![widget.message.authorId!]
        : null;

    if (batchAuthor != null) {
      return _buildBubble(context, author: batchAuthor, theme: theme);
    }

    final authorAsync = widget.message.authorId != null
        ? ref.watch(activeMemberByIdProvider(widget.message.authorId!))
        : const AsyncValue<Member?>.data(null);

    return authorAsync.when(
      data: (author) => _buildBubble(context, author: author, theme: theme),
      loading: () => _buildBubble(context, author: null, theme: theme),
      error: (_, _) => _buildBubble(context, author: null, theme: theme),
    );
  }

  Widget _buildAvatar(Member? author, double size) {
    final authorId = widget.message.authorId;
    final isDeparted = authorId != null
        ? widget.permissions.isMemberDeparted(authorId, member: author)
        : false;

    final prefer = ref.watch(memberNamePreferDisplayProvider);
    return MemberAvatar(
      memberId: authorId,
      avatarImageData: author?.avatarImageData,
      memberName: author?.effectiveName(preferDisplayName: prefer),
      emoji: author?.emoji ?? '?',
      customColorEnabled: author?.customColorEnabled ?? false,
      customColorHex: author?.customColorHex,
      size: size,
      opacity: isDeparted ? 0.5 : 1.0,
      deferAvatarLookup: true,
    );
  }

  Widget _buildBubble(
    BuildContext context, {
    required Member? author,
    required ThemeData theme,
  }) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final prefer = ref.watch(memberNamePreferDisplayProvider);

    final authorColor =
        (author != null &&
            author.customColorEnabled &&
            author.customColorHex != null)
        ? AppColors.fromHex(author.customColorHex!)
        : theme.colorScheme.primary;

    final timeText = _showAbsoluteTime
        ? context.formatTime(widget.message.timestamp)
        : _formatRelativeTime(widget.message.timestamp);
    const avatarSize = 36.0;
    const avatarGap = 12.0;
    final messageTextColor = theme.colorScheme.onSurface;
    final metaTextColor = theme.colorScheme.onSurfaceVariant;
    final topPadding = widget.showAuthorInfo ? 16.0 : 4.0;
    final bottomPadding = widget.message.reactions.isNotEmpty ? 7.0 : 2.0;

    final actions = _buildActions();

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
        itemCount: _contextMenuItemCount(),
        itemBuilder: (context, index, close) {
          final canReact = widget.permissions.canReact;
          if (canReact) {
            if (index == 0) return _buildQuickReactionRow(close);
          }
          final actionIndex = canReact ? index - 1 : index;
          return _buildActionTile(actions[actionIndex], close, theme);
        },
        child: Semantics(
          button: true,
          label: context.l10n.chatMessageToggleTimeFormat,
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
                            child: Builder(
                              builder: (context) {
                                // Prefer the parent's live authorId so a later
                                // re-attribution shows here too; fall back to
                                // the denormalized replyToAuthorId when the
                                // parent is unknown or a system message.
                                final replyToId = widget.message.replyToId!;
                                final bool parentKnown =
                                    widget.messageAuthorMap?.containsKey(
                                      replyToId,
                                    ) ??
                                    false;
                                final String? liveAuthorId = parentKnown
                                    ? widget.messageAuthorMap![replyToId]
                                    : null;
                                final String? effectiveAuthorId =
                                    liveAuthorId ??
                                    widget.message.replyToAuthorId;

                                return _ReplyQuote(
                                  authorName:
                                      widget.authorMap?[effectiveAuthorId]
                                          ?.effectiveName(
                                            preferDisplayName: prefer,
                                          ) ??
                                      effectiveAuthorId ??
                                      context.l10n.unknown,
                                  content: widget.message.replyToContent ?? '',
                                  authorColor: _replyAuthorColor(
                                    effectiveAuthorId,
                                    theme,
                                  ),
                                  isDeleted:
                                      widget.message.replyToContent == null,
                                  onTap: widget.onScrollToReply,
                                  authorMap: widget.authorMap,
                                );
                              },
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
                                  author?.effectiveName(
                                        preferDisplayName: prefer,
                                      ) ??
                                      context.l10n.unknown,
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
                                    color: metaTextColor.withValues(
                                      alpha: 0.88,
                                    ),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                    height: 1.0,
                                  ),
                                ),
                                if (widget.message.editedAt != null)
                                  Text(
                                    context.l10n.chatMessageEdited,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: metaTextColor.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontStyle: FontStyle.italic,
                                          fontSize: 11,
                                          height: 1.0,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        if (widget.message.content.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              right: 8,
                              top: widget.showAuthorInfo ? 4 : 1,
                            ),
                            child: ChatMessageText(
                              content: widget.message.content,
                              authorMap: widget.authorMap,
                              preferDisplayName: prefer,
                              baseStyle:
                                  (theme.textTheme.bodyLarge ??
                                          const TextStyle())
                                      .copyWith(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w400,
                                        height: 1.24,
                                      ),
                              defaultColor: messageTextColor,
                              imgElementBuilder: BioImageElementBuilder(
                                library:
                                    ref.watch(imageLibraryProvider).value ??
                                    const [],
                              ),
                              imageLibraryVersion: ref.watch(
                                imageLibraryVersionProvider,
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
                              canToggle: widget.permissions.canReact,
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
      ),
    );

    // Build the invisible author-picker anchor only for bubbles where the
    // picker can actually be shown. Cheap gate first (no provider reads), then
    // watch activeMembers only if the cheap gate passes.
    final perms = widget.permissions;
    final authorId = widget.message.authorId;
    final cheapGate =
        perms.canChangeMessageAuthor(authorId) &&
        !widget.message.isSystemMessage;

    Widget buildFinalWidget(Widget content) {
      if (!cheapGate) return content;

      // Only read activeMembers / terminology once the cheap gate passes —
      // avoids per-bubble subscriptions in chats where the action can't run.
      final activeMembers =
          ref.watch(activeMemberListProvider).value ?? const [];
      final currentAuthor = (authorId != null)
          ? (widget.authorMap?[authorId])
          : null;
      final candidateIds = chatAuthorCandidateIds(
        perms.conversation,
        activeMembers,
        currentAuthorId: authorId,
        currentAuthor: currentAuthor,
      );
      if (candidateIds.length < 2) return content;

      // Offstage keeps the picker anchor in the layout/overlay system without
      // painting — BlurPopupAnchor needs it mounted to measure position.
      final terms = watchTerminology(context, ref);
      final authorPickerAnchor = Offstage(
        child: MemberSelectorPopup(
          manualAnchorKey: _authorPickerKey,
          anchorChild: const SizedBox.shrink(),
          members: chatAuthorCandidates(
            perms.conversation,
            activeMembers,
            context.l10n,
            currentAuthorId: authorId,
            currentAuthor: currentAuthor,
          ),
          termPlural: terms.plural,
          selectedMemberId: authorId,
          searchTitle: context.l10n.chatMessageSetAuthorPickerTitle,
          searchLabel: context.l10n.chatMessageSetAuthorPickerTitle,
          onMemberSelected: (id) => unawaited(
            ref
                .read(chatNotifierProvider.notifier)
                .changeMessageAuthor(widget.message.id, id),
          ),
          child: const SizedBox.shrink(),
        ),
      );

      return Stack(
        children: [
          content,
          Positioned(top: 0, left: 0, child: authorPickerAnchor),
        ],
      );
    }

    if (disableAnimations) {
      if (widget.isHighlighted) {
        return buildFinalWidget(
          Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                ),
              ),
              slideWidget,
            ],
          ),
        );
      }
      return buildFinalWidget(slideWidget);
    }

    if (!widget.isHighlighted) return buildFinalWidget(slideWidget);

    return buildFinalWidget(
      Stack(
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.08, end: 0.0),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOut,
              builder: (context, value, child) => ColoredBox(
                color: theme.colorScheme.primary.withValues(alpha: value),
                child: child,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          slideWidget,
        ],
      ),
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
          padding: const EdgeInsets.only(top: 2),
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
      case 'gif':
        return _buildGifAttachment(attachment);
      default:
        return const ExpiredMedia();
    }
  }

  Widget _buildVoiceAttachment(MediaAttachment attachment, Color authorColor) {
    return _VoiceAttachmentBubble(attachment: attachment);
  }

  Widget _buildImageAttachment(MediaAttachment attachment) {
    final params = (
      mediaId: attachment.mediaId,
      encryptionKeyB64: attachment.encryptionKeyB64,
      ciphertextHash: attachment.contentHash,
      plaintextHash: attachment.plaintextHash,
    );
    final mediaAsync = ref.watch(mediaFileProvider(params));

    // Thumbnail tier (media thumbnails): while the full blob is still
    // downloading, show the small thumbnail for a crisp preview. Resolved only
    // while the full image is absent — once it lands we drop the thumbnail watch
    // (the autoDispose provider tears down), so a cached full never fetches a
    // thumbnail. Shares the main blob's key; its own hashes are synced.
    Uint8List? thumbnailBytes;
    if (mediaAsync.value == null &&
        attachment.thumbnailMediaId.isNotEmpty &&
        attachment.thumbnailContentHash.isNotEmpty &&
        attachment.thumbnailPlaintextHash.isNotEmpty) {
      final thumbParams = (
        mediaId: attachment.thumbnailMediaId,
        encryptionKeyB64: attachment.encryptionKeyB64,
        ciphertextHash: attachment.thumbnailContentHash,
        plaintextHash: attachment.thumbnailPlaintextHash,
      );
      thumbnailBytes = ref.watch(mediaFileProvider(thumbParams)).value;
    }

    return ImageBubble(
      imageBytes: mediaAsync.value,
      thumbnailBytes: thumbnailBytes,
      isLoading: mediaAsync.isLoading,
      hasError: mediaAsync.hasError,
      onRetry: mediaAsync.hasError
          ? () => ref.invalidate(mediaFileProvider(params))
          : null,
      width: attachment.width > 0 ? attachment.width.toDouble() : null,
      height: attachment.height > 0 ? attachment.height.toDouble() : null,
      blurhash: attachment.blurhash.isNotEmpty ? attachment.blurhash : null,
    );
  }

  Widget _buildGifAttachment(MediaAttachment attachment) {
    final gifEnabled = ref.watch(gifRenderingEnabledProvider);
    final consent = ref.watch(gifConsentStateProvider);
    final config = ref.watch(gifServiceConfigProvider).asData?.value;
    return GifBubble(
      sourceUrl: attachment.sourceUrl,
      previewUrl: attachment.previewUrl,
      width: attachment.width > 0 ? attachment.width.toDouble() : null,
      height: attachment.height > 0 ? attachment.height.toDouble() : null,
      contentDescription: attachment.blurhash.isNotEmpty
          ? attachment.blurhash
          : null,
      gifEnabled: gifEnabled,
      onEnableTap: config?.enabled == true && consent != GifConsentState.enabled
          ? _requestGifConsent
          : null,
    );
  }

  Future<void> _requestGifConsent() async {
    final accepted = await GifConsentDialog.show(context);
    if (!mounted) return;
    await ref
        .read(settingsNotifierProvider.notifier)
        .updateGifConsentState(
          accepted ? GifConsentState.enabled : GifConsentState.declined,
        );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return context.formatTime(dateTime);
  }
}

class _VoiceAttachmentBubble extends ConsumerStatefulWidget {
  const _VoiceAttachmentBubble({required this.attachment});

  final MediaAttachment attachment;

  @override
  ConsumerState<_VoiceAttachmentBubble> createState() =>
      _VoiceAttachmentBubbleState();
}

class _VoiceAttachmentBubbleState
    extends ConsumerState<_VoiceAttachmentBubble> {
  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final params = (
      mediaId: attachment.mediaId,
      encryptionKeyB64: attachment.encryptionKeyB64,
      ciphertextHash: attachment.contentHash,
      plaintextHash: attachment.plaintextHash,
    );
    final mediaAsync = ref.watch(mediaFileProvider(params));
    final mediaId = attachment.mediaId;

    ref.listen<bool>(
      voicePlaybackProvider.select(
        (state) => state.activeMediaId == mediaId && state.error != null,
      ),
      (previous, next) {
        if ((previous ?? false) || !next || !mounted) {
          return;
        }
        SemanticsService.sendAnnouncement(
          View.of(context),
          context.l10n.chatVoiceNoteError,
          Directionality.of(context),
        );
      },
    );

    final playbackState = ref.watch(
      voicePlaybackProvider.select(
        (state) =>
            state.activeMediaId == mediaId ? state : const VoicePlaybackState(),
      ),
    );
    final isActive = playbackState.activeMediaId == mediaId;
    final effectiveDuration = playbackState.duration.inMilliseconds > 0
        ? playbackState.duration
        : Duration(milliseconds: attachment.durationMs);
    final progress = effectiveDuration.inMilliseconds <= 0
        ? 0.0
        : (playbackState.position.inMilliseconds /
                  effectiveDuration.inMilliseconds)
              .clamp(0.0, 1.0);
    final isLoading = mediaAsync.isLoading || playbackState.isLoading;
    final hasPlaybackError = playbackState.error != null;
    final bytes = mediaAsync.value;

    return VoiceBubble(
      durationMs: effectiveDuration.inMilliseconds,
      waveformB64: attachment.waveformB64,
      isPlaying: playbackState.isPlaying,
      progress: progress,
      speed: playbackState.speed,
      isLoading: isLoading,
      hasError: mediaAsync.hasError || hasPlaybackError,
      onPlayPause: bytes == null
          ? null
          : () => ref
                .read(voicePlaybackProvider.notifier)
                .togglePlayPause(
                  VoicePlaybackSource.bytes(
                    bytes: bytes,
                    mimeType: attachment.mimeType,
                    mediaId: attachment.mediaId,
                  ),
                ),
      onRetry: mediaAsync.hasError
          ? () => ref.invalidate(mediaFileProvider(params))
          : bytes != null && hasPlaybackError
          ? () => ref
                .read(voicePlaybackProvider.notifier)
                .togglePlayPause(
                  VoicePlaybackSource.bytes(
                    bytes: bytes,
                    mimeType: attachment.mimeType,
                    mediaId: attachment.mediaId,
                  ),
                )
          : null,
      onSeek: bytes != null && !hasPlaybackError
          ? (fraction) {
              ref
                  .read(voicePlaybackProvider.notifier)
                  .seek(
                    Duration(
                      milliseconds:
                          (fraction * effectiveDuration.inMilliseconds).round(),
                    ),
                  );
            }
          : null,
      onSpeedTap: isActive && !hasPlaybackError && !isLoading
          ? () => ref.read(voicePlaybackProvider.notifier).cycleSpeed()
          : null,
    );
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
    this.authorMap,
  });

  final String authorName;
  final String content;
  final Color authorColor;
  final bool isDeleted;
  final VoidCallback? onTap;
  final Map<String, Member>? authorMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: buildReplyQuoteA11yLabel(
        context.l10n,
        authorName: authorName,
        content: content,
        isDeleted: isDeleted,
      ),
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
                padding: !isDeleted
                    ? const EdgeInsets.only(left: 6)
                    : EdgeInsets.zero,
                child: TintedGlassSurface(
                  tint: isDeleted ? null : authorColor,
                  borderRadius: BorderRadius.circular(
                    PrismShapes.of(context).radius(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: isDeleted
                      ? Text(
                          context.l10n.chatReplyQuoteDeleted,
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
                              stripChatMarkdown(
                                redactSpoilers(content),
                                authorMap,
                              ),
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
