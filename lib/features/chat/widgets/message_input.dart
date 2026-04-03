import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Message composition widget with inline "speaking as" avatar and text input.
class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  bool _isSending = false;
  OverlayEntry? _mentionOverlay;
  String _mentionFilter = '';
  final _mentionOverlayKey = GlobalKey<MentionOverlayState>();

  bool get _canSend =>
      _controller.text.trim().isNotEmpty &&
      ref.read(speakingAsProvider) != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _dismissMentionOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Detect `@` trigger and manage the mention overlay.
  void _onTextChanged() {
    if (!mounted) return;
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _dismissMentionOverlay();
      return;
    }

    final trigger = detectMentionTrigger(_controller.text, selection.baseOffset);
    if (trigger == null) {
      _dismissMentionOverlay();
      return;
    }

    _mentionFilter = trigger.filter;
    if (_mentionOverlay == null) {
      _showMentionOverlay();
    } else {
      // Update filter by rebuilding overlay.
      _mentionOverlay!.markNeedsBuild();
    }
  }

  List<Member> _getMentionCandidates() {
    final members = ref.read(activeMembersProvider).value ?? [];
    final conversationAsync =
        ref.read(conversationByIdProvider(widget.conversationId));
    final participantIds =
        conversationAsync.value?.participantIds.toSet();
    return participantIds != null
        ? members.where((m) => participantIds.contains(m.id)).toList()
        : members;
  }

  void _showMentionOverlay() {
    final overlay = Overlay.of(context);
    final candidates = _getMentionCandidates();
    _mentionOverlay = OverlayEntry(
      builder: (context) {
        return MentionOverlay(
          key: _mentionOverlayKey,
          members: candidates,
          filter: _mentionFilter,
          layerLink: _layerLink,
          onSelect: _onMemberSelected,
        );
      },
    );
    overlay.insert(_mentionOverlay!);
  }

  void _dismissMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _mentionFilter = '';
  }

  void _onMemberSelected(Member member) {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    final before = text.substring(0, cursorPos);
    final atIndex = before.lastIndexOf('@');
    if (atIndex < 0) return;

    final after = text.substring(cursorPos);
    final replacement = '@[${member.id}] ';
    final newText = text.substring(0, atIndex) + replacement + after;
    final newCursorPos = atIndex + replacement.length;

    // Temporarily remove listener to avoid re-triggering overlay.
    _controller.removeListener(_onTextChanged);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
    _controller.addListener(_onTextChanged);

    _dismissMentionOverlay();
    _focusNode.requestFocus();
    setState(() {}); // Update _canSend.
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return;

    setState(() => _isSending = true);

    // Capture reply state before the async gap
    final replyingTo = ref.read(replyingToProvider(widget.conversationId));

    try {
      await ref.read(chatNotifierProvider.notifier).sendMessage(
            conversationId: widget.conversationId,
            content: text,
            authorId: speakingAs,
            replyToId: replyingTo?.id,
            replyToAuthorId: replyingTo?.authorId,
            replyToContent: replyingTo?.content,
          );
      _controller.removeListener(_onTextChanged);
      _controller.clear();
      _controller.addListener(_onTextChanged);
      _dismissMentionOverlay();
      _focusNode.requestFocus();
      ref.read(replyingToProvider(widget.conversationId).notifier).clear();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speakingAs = ref.watch(speakingAsProvider);
    final membersAsync = ref.watch(activeMembersProvider);
    final replyingTo = ref.watch(replyingToProvider(widget.conversationId));

    final members = membersAsync.value ?? [];
    final memberMap = {for (final m in members) m.id: m};
    final currentMember = speakingAs != null
        ? members.where((m) => m.id == speakingAs).firstOrNull
        : null;

    const double inputHeight = 38.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            curve: replyingTo != null ? Curves.easeOut : Curves.easeIn,
            opacity: replyingTo != null ? 1.0 : 0.0,
            child: replyingTo != null
                ? _ReplyBanner(
                    message: replyingTo,
                    memberMap: memberMap,
                    onDismiss: () => ref
                        .read(replyingToProvider(widget.conversationId).notifier)
                        .clear(),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BlurPopupAnchor(
                  preferredDirection: BlurPopupDirection.up,
                  itemCount: members.length,
                  itemBuilder: (context, index, close) {
                    final member = members[index];
                    final isSelected = member.id == speakingAs;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: MemberAvatar(
                        avatarImageData: member.avatarImageData,
                        emoji: member.emoji,
                        customColorEnabled: member.customColorEnabled,
                        customColorHex: member.customColorHex,
                        size: 32,
                      ),
                      title: Text(
                        member.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        ref
                            .read(speakingAsProvider.notifier)
                            .setMember(member.id);
                        close();
                      },
                    );
                  },
                  child: currentMember != null
                      ? MemberAvatar(
                          avatarImageData: currentMember.avatarImageData,
                          emoji: currentMember.emoji,
                          customColorEnabled: currentMember.customColorEnabled,
                          customColorHex: currentMember.customColorHex,
                          size: inputHeight,
                        )
                      : TintedGlassSurface.circle(
                          size: inputHeight,
                          child: Icon(
                            Icons.person,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CompositedTransformTarget(
                    link: _layerLink,
                    child: _GlassTextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minHeight: inputHeight,
                      onChanged: (_) => setState(() {}),
                      onSend: _sendMessage,
                      onKeyEvent: _mentionOverlay != null
                          ? (event) {
                              final consumed =
                                  _mentionOverlayKey.currentState?.handleKeyEvent(event) ?? false;
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.escape) {
                                _dismissMentionOverlay();
                                return true;
                              }
                              return consumed;
                            }
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(
                  canSend: _canSend,
                  isSending: _isSending,
                  size: inputHeight,
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A pill-shaped text field with glass-style fill and border, built natively
/// via [InputDecoration] so the shape is proper rather than clipped.
///
/// On desktop/tablet, Enter sends and Ctrl/Cmd+Enter inserts a newline.
/// On phones the soft keyboard's action button sends instead.
class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.focusNode,
    required this.minHeight,
    required this.onChanged,
    required this.onSend,
    this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double minHeight;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Optional key event handler for mention overlay navigation.
  /// Returns true if the event was consumed.
  final bool Function(KeyEvent event)? onKeyEvent;

  bool get _isHardwareKeyboardPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      default:
        return false;
    }
  }

  /// Insert a newline at the current cursor position.
  void _insertNewline() {
    final text = controller.text;
    final sel = controller.selection;
    final before = text.substring(0, sel.baseOffset);
    final after = text.substring(sel.extentOffset);
    controller.value = TextEditingValue(
      text: '$before\n$after',
      selection: TextSelection.collapsed(offset: sel.baseOffset + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOled = theme.scaffoldBackgroundColor == AppColors.warmBlack;

    final fillColor = isDark
        ? (isOled
            ? AppColors.warmWhite.withValues(alpha: 0.08)
            : AppColors.warmWhite.withValues(alpha: 0.08))
        : AppColors.warmWhite.withValues(alpha: 0.65);

    final borderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.1)
        : AppColors.warmBlack.withValues(alpha: 0.06);

    final roundedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(minHeight / 2),
      borderSide: BorderSide(
        color: borderColor,
        width: PrismTokens.hairlineBorderWidth,
      ),
    );

    final useHardwareShortcuts = _isHardwareKeyboardPlatform;

    final textField = TextField(
      controller: controller,
      focusNode: focusNode,
      textCapitalization: TextCapitalization.sentences,
      minLines: 1,
      maxLines: 6,
      // On phones, show the send action on the soft keyboard
      textInputAction:
          useHardwareShortcuts ? TextInputAction.newline : TextInputAction.send,
      cursorColor: theme.colorScheme.primary,
      textAlignVertical: TextAlignVertical.top,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 15.5,
        height: 1.2,
      ),
      decoration: InputDecoration(
        hintText: 'Message',
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          fontSize: 15.5,
        ),
        filled: true,
        fillColor: fillColor,
        border: roundedBorder,
        enabledBorder: roundedBorder,
        focusedBorder: roundedBorder,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        isDense: true,
      ),
      onChanged: onChanged,
      // On phones, the soft keyboard send button triggers onSubmitted
      onSubmitted: useHardwareShortcuts ? null : (_) => onSend(),
    );

    if (!useHardwareShortcuts) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: textField,
      );
    }

    // On desktop: Enter sends, Ctrl/Cmd/Shift+Enter inserts a newline.
    // Focus.onKeyEvent fires before the TextField processes the key,
    // so returning handled prevents the default newline insertion.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Focus(
        onKeyEvent: (node, event) {
          // Let the mention overlay handle key events first.
          if (onKeyEvent != null && onKeyEvent!(event)) {
            return KeyEventResult.handled;
          }

          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.numpadEnter) {
            return KeyEventResult.ignored;
          }

          final isModified = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isShiftPressed;

          if (isModified) {
            _insertNewline();
          } else {
            onSend();
          }
          return KeyEventResult.handled;
        },
        child: textField,
      ),
    );
  }
}

/// Animated send button that crossfades between an untinted glass circle
/// (idle) and a primary-tinted glass circle (ready to send).
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.canSend,
    required this.isSending,
    required this.size,
    required this.onPressed,
  });

  final bool canSend;
  final bool isSending;
  final double size;
  final VoidCallback onPressed;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return GestureDetector(
      onTapDown: widget.canSend ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.canSend
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOut,
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeOut,
          crossFadeState: widget.canSend
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          layoutBuilder: (top, topKey, bottom, bottomKey) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned(key: bottomKey, child: bottom),
                Positioned(key: topKey, child: top),
              ],
            );
          },
          // Idle: plain glass, no tint
          firstChild: TintedGlassSurface.circle(
            size: widget.size,
            child: Icon(
              Icons.arrow_upward_rounded,
              size: 19,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
          // Ready: primary-tinted glass with accent icon
          secondChild: widget.isSending
              ? TintedGlassSurface.circle(
                  size: widget.size,
                  tint: primary,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary,
                    ),
                  ),
                )
              : TintedGlassSurface.circle(
                  size: widget.size,
                  tint: primary,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 19,
                    color: primary,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({
    required this.message,
    required this.memberMap,
    required this.onDismiss,
  });

  final ChatMessage message;
  final Map<String, Member> memberMap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final author = message.authorId != null ? memberMap[message.authorId] : null;
    final authorColor =
        (author?.customColorEnabled == true && author?.customColorHex != null)
            ? AppColors.fromHex(author!.customColorHex!)
            : theme.colorScheme.primary;

    final fillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.08)
        : AppColors.warmWhite.withValues(alpha: 0.65);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      color: fillColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 32,
            margin: const EdgeInsets.only(right: 8),
            color: authorColor,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  author?.name ?? 'Unknown',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: authorColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  message.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PrismIconButton(
            icon: Icons.close,
            iconSize: 18,
            tooltip: 'Cancel reply',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
