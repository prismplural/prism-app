import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/members/widgets/markdown_table_button.dart';
import 'package:prism_plurality/features/members/widgets/remote_markdown_image_import_prompt.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/image_first_paste.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_mention_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

Future<String?> showFullScreenMarkdownEditor({
  required BuildContext context,
  required String title,
  required String initialText,
  required String hintText,
  String? memberId,
}) {
  return PrismSheet.showFullScreen<String>(
    context: context,
    builder: (context, scrollController) => FullScreenMarkdownEditorSheet(
      title: title,
      initialText: initialText,
      hintText: hintText,
      scrollController: scrollController,
      memberId: memberId,
    ),
  );
}

/// Full-screen markdown editor for longer profile text fields.
///
/// Returns trimmed text when saved, or null when cancelled without saving.
class FullScreenMarkdownEditorSheet extends ConsumerStatefulWidget {
  const FullScreenMarkdownEditorSheet({
    super.key,
    required this.title,
    required this.initialText,
    required this.hintText,
    required this.scrollController,
    this.memberId,
  });

  final String title;
  final String initialText;
  final String hintText;
  final ScrollController scrollController;
  final String? memberId;

  @override
  ConsumerState<FullScreenMarkdownEditorSheet> createState() =>
      _FullScreenMarkdownEditorSheetState();
}

class _FullScreenMarkdownEditorSheetState
    extends ConsumerState<FullScreenMarkdownEditorSheet> {
  late final MarkdownEditingController _controller;
  late final FocusNode _focusNode;
  // Isolates staged images to this editor instance.
  final String _editSessionId = const Uuid().v4();
  // Drives the add-image dialog when an image is pasted into the field, reusing
  // the same staging flow as the floating image button.
  final GlobalKey<MarkdownImageButtonState> _imageButtonKey = GlobalKey();
  bool _showPreview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = MarkdownEditingController(text: widget.initialText);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text != widget.initialText;

  // The image library is user-scoped, so the processor is available on every
  // surface — no memberId required. Keyed by this editor's session id.
  BioImageProcessor _getProcessor() =>
      ref.read(bioImageProcessorProvider(_editSessionId));

  bool get _hasStagedImages {
    try {
      return _getProcessor().staged.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _hasUnsavedChanges => _isDirty || _hasStagedImages;

  /// Routes a pasted clipboard image into the add-image dialog; false lets the
  /// default text paste run.
  Future<bool> _handlePasteImage() async {
    final image = await ref.read(appClipboardReaderProvider).readImage();
    if (image == null || !mounted) return false;
    final button = _imageButtonKey.currentState;
    if (button == null) return false;
    await button.insertImageFromBytes(image.bytes);
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final shouldContinue = await promptAndStageRemoteMarkdownImages(
        context: context,
        ref: ref,
        controller: _controller,
        sessionId: _editSessionId,
      );
      if (!shouldContinue || !mounted) return;

      // Upload staged images while the editor's processor is still mounted.
      var failedTags = const <String>[];
      try {
        failedTags = await _getProcessor().commitStaged();
      } catch (_) {
        // Leave refs in place; they resolve once the library entry syncs.
      }
      if (!mounted) return;
      if (failedTags.isNotEmpty) {
        PrismToast.error(
          context,
          message: context.l10n.mediaSomeImagesNotSaved,
        );
      }
      Navigator.of(context).pop(_controller.text.trim());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    _controller.updateTheme(context);

    // Keep staged images alive until save or discard.
    try {
      ref.watch(bioImageProcessorProvider(_editSessionId));
    } catch (_) {}

    final processingState = ref.watch(bioImageProcessingStateProvider);
    final isProcessing =
        processingState.status == BioImageProcessingStatus.processing;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => UnsavedChangesGuard<String?>(
        hasUnsavedChanges: _hasUnsavedChanges,
        onDiscard: () {
          try {
            _getProcessor().discardStaged();
          } catch (_) {}
        },
        discardResult: null,
        child: Stack(
          children: [
            Column(
              children: [
                PrismSheetTopBar(
                  title: widget.title,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrismGlassIconButton(
                        icon: _showPreview ? AppIcons.edit : AppIcons.preview,
                        onPressed: () =>
                            setState(() => _showPreview = !_showPreview),
                        tooltip: _showPreview
                            ? l10n.memberBioEditorTooltip
                            : l10n.memberBioPreviewTooltip,
                        size: PrismTokens.topBarActionSize,
                      ),
                      const SizedBox(width: 4),
                      PrismGlassIconButton(
                        icon: AppIcons.check,
                        onPressed: _saving ? null : _save,
                        tooltip: l10n.save,
                        size: PrismTokens.topBarActionSize,
                        tint: theme.colorScheme.primary,
                        isLoading: _saving,
                        accentIcon: true,
                      ),
                    ],
                  ),
                ),
                if (isProcessing) const LinearProgressIndicator(),
                Expanded(
                  child: _showPreview
                      ? ListView(
                          controller: widget.scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: PrismTokens.pageHorizontalPadding + 8,
                            vertical: 16,
                          ),
                          children: [
                            if (_controller.text.trim().isEmpty)
                              Text(
                                widget.hintText,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                              )
                            else
                              PrismMarkdownText(
                                data: _controller.text,
                                enabled: true,
                                baseStyle: theme.textTheme.bodyLarge,
                                memberId: widget.memberId,
                                memberName: '',
                                editSessionId: _editSessionId,
                                mentionsInteractive: false,
                              ),
                          ],
                        )
                      : GestureDetector(
                          onTap: () => _focusNode.requestFocus(),
                          behavior: HitTestBehavior.translucent,
                          child: ListView(
                            controller: widget.scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: PrismTokens.pageHorizontalPadding + 8,
                              vertical: 16,
                            ),
                            children: [
                              ImagePasteRegion(
                                onPasteImage: _handlePasteImage,
                                builder: (context, contextMenuBuilder) =>
                                    MemberMentionTextField(
                                      controller: _controller,
                                      focusNode: _focusNode,
                                      hintText: widget.hintText,
                                      fieldStyle:
                                          PrismTextFieldStyle.borderless,
                                      style: theme.textTheme.bodyLarge,
                                      hintStyle: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.4),
                                          ),
                                      minLines: 12,
                                      maxLines: null,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      autofocus: true,
                                      contextMenuBuilder: contextMenuBuilder,
                                    ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
            // Floating image button — sits above keyboard when open. Available
            // on every surface; the image library is user-scoped.
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarkdownTableButton(controller: _controller),
                  const SizedBox(width: 4),
                  MarkdownImageButton(
                    key: _imageButtonKey,
                    controller: _controller,
                    sessionId: _editSessionId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
