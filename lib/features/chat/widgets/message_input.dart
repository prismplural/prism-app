import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart' as media;
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';
import 'package:prism_plurality/features/chat/widgets/gif_consent_dialog.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/chat/utils/proxy_tag_matcher.dart';
import 'package:prism_plurality/features/chat/widgets/attachment_preview.dart';
import 'package:prism_plurality/features/chat/widgets/gif_picker_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';
import 'package:prism_plurality/features/chat/widgets/voice_recorder.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Message composition widget with inline "speaking as" avatar and text input.
class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = ChatMarkdownEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  bool _isSending = false;
  OverlayEntry? _mentionOverlay;
  String _mentionFilter = '';
  final _mentionOverlayKey = GlobalKey<MentionOverlayState>();
  Uint8List? _stagedImageBytes;
  bool _isRecording = false;

  /// Mirror of `_controller.text` used by the proxy-tag matcher. Riverpod
  /// providers can only be read in `build`, so the controller listener
  /// stores the latest text here and `build` recomputes the match against
  /// watched providers.
  String _lastText = '';

  /// Proxy-tag match dismissed by the user for the current draft. Keyed by
  /// `(prefix, suffix, memberId)` so retyping a different tag re-opens the
  /// chip. Cleared when the draft is sent or cleared.
  (String, String, String)? _suppressedTag;

  /// Effective proxy-tag match for the current draft, recomputed in `build`.
  /// Snapshotted on send so the post-async path uses the intent the user
  /// actually saw when they tapped send.
  ProxyTagMatch? _effectiveMatch;

  bool get _canSend {
    final hasText = _controller.text.trim().isNotEmpty;
    final hasImage = _stagedImageBytes != null;
    if (!hasText && !hasImage) return false;
    // build() watches speakingAsProvider, so ref.read here is safe — rebuild
    // happens when it changes. Image-only / GIF / voice paths only author via
    // speakingAs; proxy tags apply to text content only.
    if (!hasText && hasImage) return ref.read(speakingAsProvider) != null;
    // Text (with or without image): either speakingAs or a live proxy match
    // covers authorship.
    final match = _effectiveMatch;
    return ref.read(speakingAsProvider) != null ||
        (match != null && match.strippedText.isNotEmpty);
  }

  bool get _showMicButton =>
      _controller.text.trim().isEmpty &&
      _stagedImageBytes == null &&
      !_isRecording;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.updateTheme(context);
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
    if (_lastText != _controller.text) {
      setState(() => _lastText = _controller.text);
    }
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _dismissMentionOverlay();
      return;
    }

    final trigger = detectMentionTrigger(
      _controller.text,
      selection.baseOffset,
    );
    if (trigger == null) {
      _dismissMentionOverlay();
      return;
    }

    _mentionFilter = trigger.filter;
    if (_mentionOverlay == null) {
      _showMentionOverlay();
    } else {
      // Update filter by rebuilding overlay.
      _mentionOverlay?.markNeedsBuild();
    }
  }

  List<Member> _getMentionCandidates() {
    final members = ref.read(activeMembersProvider).value ?? [];
    final conversationAsync = ref.read(
      conversationByIdProvider(widget.conversationId),
    );
    final participantIds = conversationAsync.value?.participantIds.toSet();
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
    // Listener was detached across the programmatic edit above so it didn't
    // fire _onTextChanged; sync _lastText manually so the next build's
    // proxy-tag match and _canSend see the inserted mention.
    setState(() => _lastText = _controller.text);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() => _stagedImageBytes = bytes);
      }
    }
  }

  Future<void> _showGifPicker() async {
    final consent = ref.read(gifConsentStateProvider);
    if (consent == GifConsentState.unknown) {
      final accepted = await GifConsentDialog.show(context);
      if (!mounted) return;
      await ref
          .read(settingsNotifierProvider.notifier)
          .updateGifConsentState(
            accepted ? GifConsentState.enabled : GifConsentState.declined,
          );
      if (!accepted) return;
    }

    if (!mounted) {
      return;
    }

    final gif = await GifPickerSheet.show(context);
    if (gif != null && mounted) {
      await _sendGif(gif);
    }
  }

  Future<void> _sendGif(KlipyGif gif) async {
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return;

    setState(() => _isSending = true);

    try {
      final messageId = await ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            conversationId: widget.conversationId,
            content: '',
            authorId: speakingAs,
          );

      final repo = ref.read(mediaAttachmentRepositoryProvider);
      await repo.create(
        media.MediaAttachment(
          id: const Uuid().v4(),
          messageId: messageId,
          mediaId: '',
          mediaType: 'gif',
          encryptionKeyB64: '',
          contentHash: '',
          plaintextHash: '',
          mimeType: 'video/mp4',
          sizeBytes: 0,
          width: gif.width,
          height: gif.height,
          durationMs: 0,
          blurhash: gif.contentDescription,
          waveformB64: '',
          thumbnailMediaId: '',
          sourceUrl: gif.mp4Url,
          previewUrl: gif.previewUrl,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final hasImage = _stagedImageBytes != null;
    if (text.isEmpty && !hasImage) return;

    final speakingAs = ref.read(speakingAsProvider);
    final match = _effectiveMatch;

    String? authorId;
    String? content;

    if (hasImage && text.isEmpty) {
      // Image-only: proxy tags do not apply to attachments.
      authorId = speakingAs;
      content = '';
    } else if (match != null &&
        text.isNotEmpty &&
        match.strippedText.isNotEmpty) {
      // Re-verify the match target is still authorable — active membership
      // can change between build and the send path.
      final freshMembers =
          ref.read(activeMembersProvider).value ?? const <Member>[];
      final stillValid = freshMembers.any(
        (m) => m.id == match.memberId && !m.isDeleted && m.isActive,
      );
      if (stillValid) {
        authorId = match.memberId;
        content = match.strippedText;
      }
    }

    authorId ??= speakingAs;
    content ??= text;

    if (authorId == null) return;

    setState(() => _isSending = true);

    // Capture reply state and staged image before the async gap.
    final replyingTo = ref.read(replyingToProvider(widget.conversationId));
    final imageBytes = _stagedImageBytes;

    try {
      // Send the text message (or empty content placeholder if image-only).
      final messageId = await ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            conversationId: widget.conversationId,
            content: content,
            authorId: authorId,
            replyToId: replyingTo?.id,
            replyToAuthorId: replyingTo?.authorId,
            replyToContent: replyingTo?.content,
          );

      if (imageBytes != null) {
        final mediaService = ref.read(mediaServiceProvider);
        final repo = ref.read(mediaAttachmentRepositoryProvider);
        final data = await mediaService.prepareImage(imageBytes);

        await repo.create(
          media.MediaAttachment(
            id: const Uuid().v4(),
            messageId: messageId,
            mediaId: data.mediaId,
            mediaType: 'image',
            encryptionKeyB64: base64Encode(data.encryptionKey),
            contentHash: data.contentHash,
            plaintextHash: data.plaintextHash,
            mimeType: data.mimeType,
            sizeBytes: data.sizeBytes,
            width: data.width,
            height: data.height,
            durationMs: 0,
            blurhash: data.blurhash,
            waveformB64: '',
            thumbnailMediaId: data.thumbnailMediaId,
            sourceUrl: '',
            previewUrl: '',
          ),
        );

        try {
          await mediaService.uploadPreparedOrThrow(data);
        } catch (_) {
          if (mounted) {
            PrismToast.error(
              context,
              message: context.l10n.chatImageUploadFailed,
            );
          }
        }
      }

      _controller.removeListener(_onTextChanged);
      _controller.clear();
      _controller.addListener(_onTextChanged);
      _dismissMentionOverlay();
      _focusNode.requestFocus();
      ref.read(replyingToProvider(widget.conversationId).notifier).clear();
      if (mounted) {
        setState(() {
          _stagedImageBytes = null;
          _lastText = '';
          _suppressedTag = null;
          _effectiveMatch = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _sendVoiceNote(
    Uint8List audioBytes,
    int durationMs,
    String waveformB64,
  ) async {
    final recorderState = ref.read(voiceRecordingProvider);
    final artifact = recorderState.artifact;
    final effectiveAudioBytes = artifact?.bytes ?? audioBytes;
    final effectiveDurationMs = artifact?.durationMs ?? durationMs;
    final effectiveWaveformB64 = artifact?.waveformB64 ?? waveformB64;
    setState(() {
      _isRecording = false;
      _isSending = true;
    });

    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) {
      if (mounted) setState(() => _isSending = false);
      return;
    }

    try {
      final mediaService = ref.read(mediaServiceProvider);
      final data = await mediaService.prepareVoiceNote(
        effectiveAudioBytes,
        effectiveDurationMs,
        effectiveWaveformB64,
      );

      final messageId = await ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            conversationId: widget.conversationId,
            content: '',
            authorId: speakingAs,
          );

      final repo = ref.read(mediaAttachmentRepositoryProvider);

      await repo.create(
        media.MediaAttachment(
          id: const Uuid().v4(),
          messageId: messageId,
          mediaId: data.mediaId,
          mediaType: 'voice',
          encryptionKeyB64: base64Encode(data.encryptionKey),
          contentHash: data.contentHash,
          plaintextHash: data.plaintextHash,
          mimeType: data.mimeType,
          sizeBytes: data.sizeBytes,
          width: 0,
          height: 0,
          durationMs: data.durationMs,
          blurhash: '',
          waveformB64: data.waveformB64,
          thumbnailMediaId: '',
          sourceUrl: '',
          previewUrl: '',
        ),
      );

      try {
        await mediaService.uploadVoiceOrThrow(data);
      } catch (_) {
        if (mounted) {
          PrismToast.error(
            context,
            message: context.l10n.chatVoiceNoteUploadFailed,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speakingAs = ref.watch(speakingAsProvider);
    final membersAsync = ref.watch(activeMembersProvider);
    final replyingTo = ref.watch(replyingToProvider(widget.conversationId));
    final useProxyTags = ref
            .watch(useProxyTagsForAuthoringProvider)
            .whenOrNull(data: (v) => v) ??
        false;

    final members = membersAsync.value ?? [];
    final memberMap = {for (final m in members) m.id: m};
    final currentMember = speakingAs != null
        ? members.where((m) => m.id == speakingAs).firstOrNull
        : null;

    final rawMatch =
        useProxyTags ? matchProxyTag(_lastText, members) : null;
    final suppressed = _suppressedTag;
    final effectiveMatch = (rawMatch != null &&
            suppressed != null &&
            suppressed.$1 == rawMatch.matchedPrefix &&
            suppressed.$2 == rawMatch.matchedSuffix &&
            suppressed.$3 == rawMatch.memberId)
        ? null
        : rawMatch;
    _effectiveMatch = effectiveMatch;
    final matchedMember = effectiveMatch != null
        ? memberMap[effectiveMatch.memberId]
        : null;

    const double inputHeight = 38.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Staged image preview strip
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: _stagedImageBytes != null
              ? AttachmentPreview(
                  attachments: [_stagedImageBytes!],
                  onRemove: (_) => setState(() => _stagedImageBytes = null),
                )
              : const SizedBox.shrink(),
        ),
        // Reply banner
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            curve: replyingTo != null ? Curves.easeOut : Curves.easeIn,
            opacity: replyingTo != null ? 1.0 : 0.0,
            child: replyingTo != null
                ? ReplyBanner(
                    message: replyingTo,
                    memberMap: memberMap,
                    onDismiss: () => ref
                        .read(
                          replyingToProvider(widget.conversationId).notifier,
                        )
                        .clear(),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        // Proxy-tag authoring chip: sits below the reply banner so the
        // broader reply-context row stays above the per-message author hint.
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: effectiveMatch != null && matchedMember != null
              ? _ProxyTagAuthorChip(
                  member: matchedMember,
                  onDismiss: () {
                    setState(() {
                      _suppressedTag = (
                        effectiveMatch.matchedPrefix,
                        effectiveMatch.matchedSuffix,
                        effectiveMatch.memberId,
                      );
                    });
                  },
                )
              : const SizedBox.shrink(),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Semantics(
                  label: currentMember != null
                      ? context.l10n.chatSpeakingAs(currentMember.name)
                      : context.l10n.chatChooseSpeakingMember,
                  button: true,
                  child: BlurPopupAnchor(
                    preferredDirection: BlurPopupDirection.up,
                    itemCount: members.length,
                    itemBuilder: (context, index, close) {
                      final member = members[index];
                      final isSelected = member.id == speakingAs;
                      return PrismListRow(
                        dense: true,
                        leading: MemberAvatar(
                          avatarImageData: member.avatarImageData,
                          memberName: member.name,
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
                                AppIcons.check,
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
                            memberName: currentMember.name,
                            emoji: currentMember.emoji,
                            customColorEnabled:
                                currentMember.customColorEnabled,
                            customColorHex: currentMember.customColorHex,
                            size: inputHeight,
                          )
                        : TintedGlassSurface.circle(
                            size: inputHeight,
                            child: Icon(
                              AppIcons.person,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Left action button swaps between attachment and cancel.
                if (_isRecording)
                  VoiceRecorderCancelButton(
                    size: inputHeight,
                    onCancel: () => setState(() => _isRecording = false),
                  )
                else
                  AttachmentMenuButton(
                    gifEnabled: ref.watch(gifAttachmentEnabledProvider),
                    size: inputHeight,
                    onCamera: () => _pickImage(ImageSource.camera),
                    onPhotoLibrary: () => _pickImage(ImageSource.gallery),
                    onGif: _showGifPicker,
                  ),
                const SizedBox(width: 8),
                // TextField stays in the tree at all times so the keyboard
                // never dismisses when recording starts. VoiceRecorder
                // overlays it; AbsorbPointer blocks stray touches through.
                Expanded(
                  child: Stack(
                    children: [
                      Opacity(
                        opacity: _isRecording ? 0.0 : 1.0,
                        child: AbsorbPointer(
                          absorbing: _isRecording,
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
                                          _mentionOverlayKey.currentState
                                              ?.handleKeyEvent(event) ??
                                          false;
                                      if (event is KeyDownEvent &&
                                          event.logicalKey ==
                                              LogicalKeyboardKey.escape) {
                                        _dismissMentionOverlay();
                                        return true;
                                      }
                                      return consumed;
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      if (_isRecording)
                        VoiceRecorder(
                          onCancel: () => setState(() => _isRecording = false),
                          height: inputHeight,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Right action button swaps between send variants and mic.
                if (_isRecording)
                  VoiceRecorderSendButton(
                    size: inputHeight,
                    onSend: _sendVoiceNote,
                  )
                else if (_showMicButton && ref.watch(voiceNotesEnabledProvider))
                  _MicButton(
                    size: inputHeight,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      _focusNode.requestFocus();
                      setState(() => _isRecording = true);
                    },
                  )
                else
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

class AttachmentMenuButton extends StatelessWidget {
  const AttachmentMenuButton({
    super.key,
    required this.gifEnabled,
    required this.size,
    required this.onCamera,
    required this.onPhotoLibrary,
    required this.onGif,
  });

  final bool gifEnabled;
  final double size;
  final VoidCallback onCamera;
  final VoidCallback onPhotoLibrary;
  final VoidCallback onGif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_AttachmentMenuItem>[
      _AttachmentMenuItem(
        icon: AppIcons.cameraAlt,
        label: context.l10n.chatCamera,
        onSelected: onCamera,
      ),
      _AttachmentMenuItem(
        icon: AppIcons.photoLibrary,
        label: context.l10n.chatPhotoLibrary,
        onSelected: onPhotoLibrary,
      ),
      if (gifEnabled)
        _AttachmentMenuItem(
          icon: AppIcons.gif,
          label: context.l10n.chatGifsTitle,
          onSelected: onGif,
        ),
    ];

    return BlurPopupAnchor(
      preferredDirection: BlurPopupDirection.up,
      itemCount: items.length,
      semanticLabel: context.l10n.chatAddAttachment,
      itemBuilder: (context, index, close) {
        final item = items[index];
        return PrismListRow(
          dense: true,
          leading: Icon(
            item.icon,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(item.label),
          onTap: () {
            close();
            item.onSelected();
          },
        );
      },
      child: TintedGlassSurface(
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(size / 2),
        ),
        child: Icon(
          AppIcons.add,
          size: 19,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _AttachmentMenuItem {
  const _AttachmentMenuItem({
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
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
    final isOled = theme.scaffoldBackgroundColor == Colors.black;

    final fillColor = isDark
        ? (isOled
              ? AppColors.warmWhite.withValues(alpha: 0.08)
              : AppColors.warmWhite.withValues(alpha: 0.08))
        : AppColors.warmWhite.withValues(alpha: 0.65);

    final borderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.1)
        : AppColors.warmBlack.withValues(alpha: 0.06);

    final roundedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PrismShapes.of(context).pill(minHeight)),
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
      textInputAction: useHardwareShortcuts
          ? TextInputAction.newline
          : TextInputAction.send,
      cursorColor: theme.colorScheme.primary,
      textAlignVertical: TextAlignVertical.top,
      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.5, height: 1.2),
      decoration: InputDecoration(
        hintText: context.l10n.chatMessagePlaceholder,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          fontSize: 15.5,
        ),
        filled: true,
        fillColor: fillColor,
        border: roundedBorder,
        enabledBorder: roundedBorder,
        focusedBorder: roundedBorder,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

          final isModified =
              HardwareKeyboard.instance.isControlPressed ||
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

    return Semantics(
      label: widget.canSend
          ? context.l10n.chatSendMessage
          : context.l10n.chatSendMessageDisabled,
      button: true,
      enabled: widget.canSend,
      child: GestureDetector(
        onTapDown: widget.canSend
            ? (_) => setState(() => _pressed = true)
            : null,
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
            firstChild: TintedGlassSurface(
              width: widget.size,
              height: widget.size,
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(widget.size / 2),
              ),
              child: Icon(
                AppIcons.arrowUpwardRounded,
                size: 19,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
            // Ready: primary-tinted glass with accent icon
            secondChild: widget.isSending
                ? TintedGlassSurface(
                    width: widget.size,
                    height: widget.size,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(widget.size / 2),
                    ),
                    tint: primary,
                    child: PrismSpinner(color: primary, size: 18),
                  )
                : TintedGlassSurface(
                    width: widget.size,
                    height: widget.size,
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(widget.size / 2),
                    ),
                    tint: primary,
                    child: Icon(
                      AppIcons.arrowUpwardRounded,
                      size: 19,
                      color: primary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.size, required this.onPressed});

  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.chatRecordVoiceNote,
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        child: TintedGlassSurface(
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(size / 2),
          ),
          child: Icon(
            AppIcons.microphone,
            size: 19,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class ReplyBanner extends StatelessWidget {
  const ReplyBanner({
    super.key,
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
    final author = message.authorId != null
        ? memberMap[message.authorId]
        : null;
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
                  author?.name ?? context.l10n.unknown,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: authorColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  redactSpoilers(message.content),
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
            icon: AppIcons.close,
            iconSize: 18,
            tooltip: context.l10n.chatCancelReply,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _ProxyTagAuthorChip extends StatelessWidget {
  const _ProxyTagAuthorChip({
    required this.member,
    required this.onDismiss,
  });

  final Member member;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authorColor =
        (member.customColorEnabled && member.customColorHex != null)
            ? AppColors.fromHex(member.customColorHex!)
            : theme.colorScheme.primary;

    final fillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: 0.08)
        : AppColors.warmWhite.withValues(alpha: 0.65);

    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      color: fillColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          MemberAvatar(
            avatarImageData: member.avatarImageData,
            memberName: member.name,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.chatPostingAsProxy(member.name),
              style: theme.textTheme.bodySmall?.copyWith(
                color: authorColor,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PrismIconButton(
            icon: AppIcons.close,
            iconSize: 18,
            tooltip: context.l10n.chatPostingAsProxyDismiss,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
