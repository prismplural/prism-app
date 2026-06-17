import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/core/services/media/media_providers.dart';
import 'package:prism_plurality/core/services/media/media_service.dart';
import 'package:prism_plurality/domain/models/media_attachment.dart' as media;
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/models/conversation_permissions.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/voice_recording_provider.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/chat/utils/chat_author_options.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';
import 'package:prism_plurality/features/members/widgets/image_library_picker.dart';
import 'package:prism_plurality/features/chat/widgets/gif_consent_dialog.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';
import 'package:prism_plurality/features/chat/utils/proxy_tag_matcher.dart';
import 'package:prism_plurality/features/chat/widgets/attachment_preview.dart';
import 'package:prism_plurality/features/chat/widgets/gif_picker_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/mention_overlay.dart';
import 'package:prism_plurality/features/chat/widgets/voice_recorder.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_selector_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

final chatImagePickerProvider = Provider<ChatImagePicker>(
  (ref) => const ChatImagePicker(),
);

class ChatImagePicker {
  const ChatImagePicker();

  Future<Uint8List?> pickImageBytes(
    ImageSource source, {
    int? imageQuality,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: imageQuality,
    );
    return picked?.readAsBytes();
  }
}

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
  final _mentionFieldKey = GlobalKey();
  final _mentionOverlayController = OverlayPortalController();
  bool _isSending = false;
  String _mentionFilter = '';
  bool _mentionMenuVisible = false;
  final _mentionOverlayKey = GlobalKey<MentionOverlayState>();
  Uint8List? _stagedImageBytes;
  bool _isRecording = false;

  /// Opens the "ask each time" prompt at most once per composer mount.
  bool _askEachTimePrompted = false;

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

  bool get _canWriteToConversation {
    final conversation = ref
        .read(conversationByIdProvider(widget.conversationId))
        .value;
    if (conversation == null) return false;

    // A proxy-tag match in the current draft makes the matched member the
    // effective author, so the permission check uses that member's identity
    // rather than the null speakingAs. Without this, the participant gate
    // would block sending even though the actual author is a participant.
    final match = _effectiveMatch;
    final speakingAs =
        ref.read(speakingAsProvider) ??
        (match != null && match.strippedText.isNotEmpty
            ? match.memberId
            : null);
    final members = ref.read(activeMembersProvider).value;
    final speakingAsMember = findCurrentChatViewer(members, speakingAs);
    final permissions = conversationPermissionsForViewer(
      conversation,
      speakingAsMemberId: speakingAs,
      speakingAsMember: speakingAsMember,
    );
    return permissions.canSendMessages;
  }

  bool get _canSend {
    if (_isSending) return false;
    if (!_canWriteToConversation) return false;
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

  /// In "ask each time" mode with multiple co-fronters, opens the picker once
  /// on entry. [SpeakingAsNotifier] has already resolved a safe default, so
  /// dismissing leaves a valid selection.
  void _maybePromptAskEachTime(
    ComposerDefaultMember? mode,
    List<Member> candidates,
    Set<String> fronterIds,
    String termPlural,
  ) {
    if (_askEachTimePrompted) return;
    if (mode != ComposerDefaultMember.askEachTime) return;
    // One fronter is already the resolved default — a one-option picker is noise.
    if (fronterIds.length < 2) return;
    _askEachTimePrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final result = await MemberSearchSheet.showSingle(
        context,
        members: candidates,
        termPlural: termPlural,
        fronterIds: fronterIds,
        fronterSectionLabel: context.l10n.memberPickerFrontingSectionLabel,
      );
      if (!mounted || result is! MemberSearchResultSelected) return;
      ref.read(speakingAsProvider.notifier).setMember(result.memberId);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_mentionOverlayController.isShowing) {
      _mentionOverlayController.hide();
    }
    _mentionMenuVisible = false;
    _mentionFilter = '';
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Detect `@` trigger and manage the mention overlay.
  void _onTextChanged() {
    if (!mounted) return;
    final nextText = _controller.text;
    final selection = _controller.selection;
    var nextMentionVisible = false;
    var nextMentionFilter = '';
    if (selection.isValid && selection.isCollapsed) {
      final trigger = detectMentionTrigger(nextText, selection.baseOffset);
      if (trigger != null) {
        nextMentionVisible = true;
        nextMentionFilter = trigger.filter;
      }
    }

    if (_lastText == nextText &&
        _mentionMenuVisible == nextMentionVisible &&
        _mentionFilter == nextMentionFilter) {
      return;
    }

    setState(() {
      _lastText = nextText;
      _mentionMenuVisible = nextMentionVisible;
      _mentionFilter = nextMentionFilter;
    });
  }

  List<Member> _getMentionCandidates(
    List<Member> members,
    Conversation? conversation,
  ) {
    // Functional @mentions follow chat membership. Non-participants can still
    // be referenced as plain text, but autocomplete/badges stay in-room.
    if (conversation == null ||
        conversationIncludesImplicitMembers(conversation) ||
        conversation.participantIds.isEmpty) {
      return members;
    }
    final participantIds = conversation.participantIds.toSet();
    return members
        .where((member) => participantIds.contains(member.id))
        .toList(growable: false);
  }

  List<Member> _getSpeakingAsCandidates(
    BuildContext context,
    List<Member> members,
    Conversation? conversation, {
    String? speakingAsMemberId,
  }) {
    // When there is no conversation yet, treat it as a non-DM so all members
    // are candidates (matches the prior behavior of the inlined logic).
    final conv =
        conversation ??
        Conversation(
          id: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          lastActivityAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
    return chatAuthorCandidates(
      conv,
      members,
      context.l10n,
      currentAuthorId: speakingAsMemberId,
    );
  }

  void _syncMentionOverlayPortal(bool shouldShow) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldShow) {
        if (!_mentionOverlayController.isShowing) {
          _mentionOverlayController.show();
        }
      } else if (_mentionOverlayController.isShowing) {
        _mentionOverlayController.hide();
      }
    });
  }

  double _mentionOverlayAvailableWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final renderBox =
        _mentionFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return screenWidth - 20;
    final anchorLeft = renderBox.localToGlobal(Offset.zero).dx;
    return (screenWidth - anchorLeft - 12)
        .clamp(0.0, screenWidth - 20)
        .toDouble();
  }

  void _dismissMentionOverlay() {
    if (_mentionOverlayController.isShowing) {
      _mentionOverlayController.hide();
    }
    if (!_mentionMenuVisible && _mentionFilter.isEmpty) return;
    setState(() {
      _mentionMenuVisible = false;
      _mentionFilter = '';
    });
  }

  void _onMemberSelected(Member member) {
    _replaceMentionTriggerWith('@[${member.id}] ');
  }

  void _onBroadcastMentionSelected(String alias) {
    _replaceMentionTriggerWith('$alias ');
  }

  void _replaceMentionTriggerWith(String replacement) {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    final trigger = detectMentionTrigger(text, cursorPos);
    if (trigger == null) return;

    final after = text.substring(cursorPos);
    final newText = text.substring(0, trigger.atIndex) + replacement + after;
    final newCursorPos = trigger.atIndex + replacement.length;

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

  Future<bool> _confirmBroadcastMentionIfNeeded(
    String content,
    String authorId,
  ) async {
    if (!containsBroadcastMention(content)) return true;

    final conversation = ref
        .read(conversationByIdProvider(widget.conversationId))
        .value;
    if (conversation == null) return true;

    var activeMembers = const <Member>[];
    if (conversationIncludesImplicitMembers(conversation)) {
      try {
        activeMembers = await ref.read(activeMembersProvider.future);
      } catch (error) {
        if (mounted) {
          PrismToast.error(
            context,
            message: context.l10n.errorWithDetail(error),
          );
        }
        return false;
      }
    }
    final recipientCount = broadcastMentionRecipientIds(
      conversation: conversation,
      activeMembers: activeMembers,
      authorId: authorId,
    ).length;
    if (recipientCount < 5) return true;
    if (!mounted) return false;

    return PrismDialog.confirm(
      context: context,
      title: context.l10n.chatBroadcastMentionConfirmTitle,
      message: context.l10n.chatBroadcastMentionConfirmMessage(recipientCount),
      confirmLabel: context.l10n.confirm,
      cancelLabel: context.l10n.cancel,
      icon: AppIcons.warningAmberRounded,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final bytes = await _pickImageBytes(source);
    if (bytes != null) _stageImageBytes(bytes);
  }

  /// Pick an image from the shared library and insert its `![](tag)` reference
  /// at the cursor. The message renders the encrypted library image inline; no
  /// re-upload — it reuses the existing library blob.
  Future<void> _insertLibraryImage() async {
    final tag = await showImageLibraryPicker(context, ref);
    if (tag == null || !mounted) return;
    final markdown = '![]($tag)';
    final sel = _controller.selection;
    final text = _controller.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    _controller.value = _controller.value.copyWith(
      text: text.replaceRange(start, end, markdown),
      selection: TextSelection.collapsed(offset: start + markdown.length),
    );
    _focusNode.requestFocus();
  }

  Future<Uint8List?> _pickImageBytes(ImageSource source) async {
    if (_isDesktopPlatform(defaultTargetPlatform) &&
        source == ImageSource.gallery) {
      final picked = await ref
          .read(prismFileDialogServiceProvider)
          .pickImageFile();
      return picked?.readAsBytes();
    }

    // Keep picker quality unset so Android does not decode animated GIFs into
    // a single bitmap before Prism's own media pipeline can preserve them.
    return ref.read(chatImagePickerProvider).pickImageBytes(source);
  }

  bool _stageImageBytes(Uint8List bytes) {
    if (!mounted || bytes.isEmpty || !_canWriteToConversation) return false;
    setState(() => _stagedImageBytes = bytes);
    _focusNode.requestFocus();
    return true;
  }

  void _unfocusComposerIfKeyboardClosed() {
    final mediaInset = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
    final viewInset = View.of(context).viewInsets.bottom;
    final keyboardOpen = mediaInset > 0 || viewInset > 0;
    if (!keyboardOpen) {
      _focusNode.unfocus();
    }
  }

  Future<void> _handleInsertedContent(KeyboardInsertedContent content) async {
    if (!content.mimeType.toLowerCase().startsWith('image/')) return;

    final data = content.data;
    if (data != null && data.isNotEmpty) {
      _stageImageBytes(data);
      return;
    }

    final image = await ref
        .read(appClipboardReaderProvider)
        .readImageUri(content.uri);
    if (image != null) {
      _stageImageBytes(image.bytes);
    }
  }

  Future<bool> _pasteImageFromClipboard() async {
    final image = await ref.read(appClipboardReaderProvider).readImage();
    if (image == null) return false;
    return _stageImageBytes(image.bytes);
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
    if (!_canWriteToConversation) return;
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
    if (_isSending || !_canWriteToConversation) return;
    final conversationId = widget.conversationId;
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

    try {
      final confirmed = await _confirmBroadcastMentionIfNeeded(
        content,
        authorId,
      );
      if (!confirmed || !mounted) return;

      // Capture reply state and staged image after confirmation. The composer is
      // read-only while _isSending is true, so the draft cannot drift underneath
      // the confirmation dialog.
      final replyingTo = ref.read(replyingToProvider(conversationId));
      final clearReplyingTo = ref
          .read(replyingToProvider(conversationId).notifier)
          .clear;
      final chatNotifier = ref.read(chatNotifierProvider.notifier);
      final imageBytes = _stagedImageBytes;
      final mediaService = imageBytes != null
          ? ref.read(mediaServiceProvider)
          : null;
      final mediaAttachmentRepository = imageBytes != null
          ? ref.read(mediaAttachmentRepositoryProvider)
          : null;
      MediaAttachmentData? preparedImage;
      if (imageBytes != null && mediaService != null) {
        try {
          preparedImage = await mediaService.prepareImage(imageBytes);
        } catch (_) {
          if (mounted) {
            PrismToast.error(
              context,
              message: context.l10n.chatImageUploadFailed,
            );
          }
          if (content.isEmpty) return;
        }
      }

      // Send the text message (or empty content placeholder if image-only).
      final messageId = await chatNotifier.sendMessage(
        conversationId: conversationId,
        content: content,
        authorId: authorId,
        replyToId: replyingTo?.id,
        replyToAuthorId: replyingTo?.authorId,
        replyToContent: replyingTo?.content,
      );

      if (preparedImage != null &&
          mediaService != null &&
          mediaAttachmentRepository != null) {
        await mediaAttachmentRepository.create(
          media.MediaAttachment(
            id: const Uuid().v4(),
            messageId: messageId,
            mediaId: preparedImage.mediaId,
            mediaType: 'image',
            encryptionKeyB64: base64Encode(preparedImage.encryptionKey),
            contentHash: preparedImage.contentHash,
            plaintextHash: preparedImage.plaintextHash,
            mimeType: preparedImage.mimeType,
            sizeBytes: preparedImage.sizeBytes,
            width: preparedImage.width,
            height: preparedImage.height,
            durationMs: 0,
            blurhash: preparedImage.blurhash,
            waveformB64: '',
            thumbnailMediaId: preparedImage.thumbnailMediaId,
            thumbnailContentHash: preparedImage.thumbnailContentHash,
            thumbnailPlaintextHash: preparedImage.thumbnailPlaintextHash,
            sourceUrl: '',
            previewUrl: '',
          ),
        );

        unawaited(_uploadPreparedImage(mediaService, preparedImage));
      }

      _clearComposerDraft(clearReplyingTo: clearReplyingTo);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _uploadPreparedImage(
    MediaService mediaService,
    MediaAttachmentData data,
  ) async {
    try {
      await mediaService.uploadPreparedOrThrow(data);
    } catch (_) {
      if (!mounted) return;
      PrismToast.error(context, message: context.l10n.chatImageUploadFailed);
    }
  }

  void _clearComposerDraft({required VoidCallback clearReplyingTo}) {
    try {
      clearReplyingTo();
    } catch (_) {
      // The auto-disposed reply provider may already be gone if navigation
      // wins the race against the send completion.
    }
    if (!mounted) return;
    _controller.removeListener(_onTextChanged);
    _controller.clear();
    _controller.addListener(_onTextChanged);
    _dismissMentionOverlay();
    _focusNode.requestFocus();
    setState(() {
      _stagedImageBytes = null;
      _lastText = '';
      _suppressedTag = null;
      _effectiveMatch = null;
    });
  }

  Future<void> _sendVoiceNote(
    Uint8List audioBytes,
    int durationMs,
    String waveformB64,
  ) async {
    if (!_canWriteToConversation) {
      setState(() => _isRecording = false);
      return;
    }
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
    final conversationAsync = ref.watch(
      conversationByIdProvider(widget.conversationId),
    );
    final membersAsync = ref.watch(activeMembersProvider);
    final replyingTo = ref.watch(replyingToProvider(widget.conversationId));
    final useProxyTags =
        ref
            .watch(useProxyTagsForAuthoringProvider)
            .whenOrNull(data: (v) => v) ??
        false;
    final terms = watchTerminology(context, ref);

    final members = membersAsync.value ?? [];
    final conversation = conversationAsync.value;
    final mentionCandidates = _getMentionCandidates(members, conversation);
    final speakingAsCandidates = _getSpeakingAsCandidates(
      context,
      members,
      conversation,
      speakingAsMemberId: speakingAs,
    );
    watchMemberSearchGroupSources(ref);
    final showMentionOverlay =
        _mentionMenuVisible &&
        !_isRecording &&
        (mentionCandidates.isNotEmpty ||
            MentionOverlay.hasBroadcastAliasMatches(_mentionFilter));
    _syncMentionOverlayPortal(showMentionOverlay);
    final memberMap = {for (final m in members) m.id: m};
    _controller.updateMentionMembers(memberMap);
    final currentMember = findChatAuthorOption(context, members, speakingAs);

    final fronterIds =
        ref
            .watch(activeSessionsProvider)
            .value
            ?.map((s) => s.memberId)
            .whereType<String>()
            .toSet() ??
        const <String>{};
    // Watched, not read, so a cold-load settle rebuilds and fires the
    // ask-each-time prompt even when the resolved member is unchanged.
    final composerDefaultMode = ref.watch(composerDefaultMemberProvider).value;
    _maybePromptAskEachTime(
      composerDefaultMode,
      speakingAsCandidates,
      fronterIds,
      terms.plural,
    );

    final rawMatch = useProxyTags ? matchProxyTag(_lastText, members) : null;
    final suppressed = _suppressedTag;
    final effectiveMatch =
        (rawMatch != null &&
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
                      : context.l10n.chatChooseSpeakingMember(
                          terms.singularLower,
                        ),
                  button: true,
                  child: MemberSelectorPopup(
                    preferredDirection: BlurPopupDirection.up,
                    onBeforeShow: _unfocusComposerIfKeyboardClosed,
                    members: speakingAsCandidates,
                    termPlural: terms.plural,
                    selectedMemberId: speakingAs,
                    groupsBuilder: () =>
                        readMemberSearchGroups(ref, speakingAsCandidates),
                    fronterIds: fronterIds,
                    fronterSectionLabel:
                        context.l10n.memberPickerFrontingSectionLabel,
                    onMemberSelected: (memberId) => ref
                        .read(speakingAsProvider.notifier)
                        .setMember(memberId),
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
                    showCamera: !_isDesktopPlatform(defaultTargetPlatform),
                    size: inputHeight,
                    onCamera: () => _pickImage(ImageSource.camera),
                    onPhotoLibrary: () => _pickImage(ImageSource.gallery),
                    onGif: _showGifPicker,
                    onLibrary: _insertLibraryImage,
                  ),
                const SizedBox(width: 8),
                // TextField stays in the tree at all times so the keyboard
                // never dismisses when recording starts. VoiceRecorder
                // overlays it; AbsorbPointer blocks stray touches through.
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Opacity(
                        opacity: _isRecording ? 0.0 : 1.0,
                        child: AbsorbPointer(
                          absorbing: _isRecording,
                          child: OverlayPortal(
                            controller: _mentionOverlayController,
                            overlayChildBuilder: (context) {
                              return CompositedTransformFollower(
                                link: _layerLink,
                                showWhenUnlinked: false,
                                targetAnchor: Alignment.topLeft,
                                followerAnchor: Alignment.bottomLeft,
                                offset: const Offset(0, -8),
                                child: TextFieldTapRegion(
                                  child: MentionOverlay(
                                    key: _mentionOverlayKey,
                                    members: mentionCandidates,
                                    filter: _mentionFilter,
                                    availableWidth:
                                        _mentionOverlayAvailableWidth(context),
                                    onSelect: _onMemberSelected,
                                    onBroadcastSelect:
                                        _onBroadcastMentionSelected,
                                  ),
                                ),
                              );
                            },
                            child: CompositedTransformTarget(
                              key: _mentionFieldKey,
                              link: _layerLink,
                              child: _GlassTextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                minHeight: inputHeight,
                                onChanged: (_) => setState(() {}),
                                onSend: _sendMessage,
                                onContentInserted: _handleInsertedContent,
                                onPasteImage: _pasteImageFromClipboard,
                                onKeyEvent: _mentionMenuVisible
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
                  TextFieldTapRegion(
                    child: _MicButton(
                      size: inputHeight,
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _focusNode.requestFocus();
                        setState(() => _isRecording = true);
                      },
                    ),
                  )
                else
                  TextFieldTapRegion(
                    child: _SendButton(
                      canSend: _canSend,
                      isSending: _isSending,
                      size: inputHeight,
                      onPressed: _sendMessage,
                    ),
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
    required this.showCamera,
    required this.size,
    required this.onCamera,
    required this.onPhotoLibrary,
    required this.onGif,
    required this.onLibrary,
  });

  final bool gifEnabled;
  final bool showCamera;
  final double size;
  final VoidCallback onCamera;
  final VoidCallback onPhotoLibrary;
  final VoidCallback onGif;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_AttachmentMenuItem>[
      if (showCamera)
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
      _AttachmentMenuItem(
        icon: AppIcons.imageOutlined,
        label: 'Prism library',
        onSelected: onLibrary,
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

bool _isDesktopPlatform(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => false,
  };
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
/// On desktop, Enter sends and Ctrl/Cmd/Shift+Enter inserts a newline.
/// On phones/tablets the soft keyboard keeps a normal return key; the visible
/// send button sends the message.
class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.focusNode,
    required this.minHeight,
    required this.onChanged,
    required this.onSend,
    required this.onContentInserted,
    required this.onPasteImage,
    this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double minHeight;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final ValueChanged<KeyboardInsertedContent> onContentInserted;
  final Future<bool> Function() onPasteImage;

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

  void _insertTextAtSelection(String insertedText) {
    if (insertedText.isEmpty) return;

    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, insertedText);

    controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + insertedText.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _pasteTextFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _insertTextAtSelection(text);
  }

  Future<void> _handlePaste({VoidCallback? fallback}) async {
    final handledImage = await onPasteImage();
    if (handledImage) {
      ContextMenuController.removeAny();
      return;
    }

    if (fallback != null) {
      fallback();
    } else {
      await _pasteTextFromClipboard();
      ContextMenuController.removeAny();
    }
  }

  bool _isPasteShortcut(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => HardwareKeyboard.instance.isMetaPressed,
      TargetPlatform.linux ||
      TargetPlatform.windows => HardwareKeyboard.instance.isControlPressed,
      _ => false,
    };
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    var hasPaste = false;
    final items = <ContextMenuButtonItem>[
      for (final item in editableTextState.contextMenuButtonItems)
        if (item.type == ContextMenuButtonType.paste) ...[
          item.copyWith(
            onPressed: () => unawaited(_handlePaste(fallback: item.onPressed)),
          ),
        ] else
          item,
    ];

    for (final item in items) {
      if (item.type == ContextMenuButtonType.paste) {
        hasPaste = true;
        break;
      }
    }

    if (!hasPaste) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () => unawaited(_handlePaste()),
        ),
      );
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
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
      borderRadius: BorderRadius.circular(
        PrismShapes.of(context).pill(minHeight),
      ),
      borderSide: BorderSide(
        color: borderColor,
        width: PrismTokens.hairlineBorderWidth,
      ),
    );

    final useHardwareShortcuts = _isHardwareKeyboardPlatform;

    final textField = Actions(
      actions: <Type, Action<Intent>>{
        PasteTextIntent: _ImageFirstPasteAction(handlePaste: _handlePaste),
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: const [AtomicMentionFormatter()],
        minLines: 1,
        maxLines: 6,
        textInputAction: TextInputAction.newline,
        cursorColor: theme.colorScheme.primary,
        textAlignVertical: TextAlignVertical.top,
        contentInsertionConfiguration: ContentInsertionConfiguration(
          onContentInserted: onContentInserted,
        ),
        contextMenuBuilder: _buildContextMenu,
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
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
          if (_isPasteShortcut(event)) {
            unawaited(_handlePaste());
            return KeyEventResult.handled;
          }

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

class _ImageFirstPasteAction extends Action<PasteTextIntent> {
  _ImageFirstPasteAction({required this.handlePaste});

  final Future<void> Function({VoidCallback? fallback}) handlePaste;

  @override
  Object? invoke(PasteTextIntent intent) {
    final defaultPasteAction = callingAction;
    unawaited(
      handlePaste(
        fallback: defaultPasteAction == null
            ? null
            : () => defaultPasteAction.invoke(intent),
      ),
    );
    return null;
  }

  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? true;

  @override
  bool consumesKey(PasteTextIntent intent) {
    return callingAction?.consumesKey(intent) ?? true;
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
  const _ProxyTagAuthorChip({required this.member, required this.onDismiss});

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
