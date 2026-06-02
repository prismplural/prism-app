import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/members/widgets/markdown_table_button.dart';
import 'package:prism_plurality/features/members/widgets/remote_markdown_image_import_prompt.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

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
  // Unique per editor instance so staged images are isolated from any other
  // open editor and live exactly as long as this sheet (see
  // [bioImageProcessorProvider]).
  final String _editSessionId = const Uuid().v4();
  bool _showPreview = false;

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

  Future<void> _save() async {
    final shouldContinue = await promptAndStageRemoteMarkdownImages(
      context: context,
      ref: ref,
      controller: _controller,
      sessionId: _editSessionId,
    );
    if (!shouldContinue || !mounted) return;

    // Commit any images staged during this edit (upload + library record)
    // before returning. Done here — while the editor is still mounted and the
    // processor is alive — so it works uniformly across every surface that
    // opens this editor (bios, notes, custom fields, group descriptions).
    var failedTags = const <String>[];
    try {
      failedTags = await _getProcessor().commitStaged();
    } catch (_) {
      // Don't block save if an upload fails; the tag refs resolve once the
      // library entry syncs, or show "unavailable" if it never does.
    }
    if (!mounted) return;
    if (failedTags.isNotEmpty) {
      PrismToast.error(context, message: context.l10n.mediaSomeImagesNotSaved);
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  Future<void> _maybeDiscard() async {
    if (!_isDirty) {
      _getProcessor().discardStaged();
      Navigator.of(context).pop(null);
      return;
    }
    final confirm = await PrismDialog.confirm(
      context: context,
      title: context.l10n.memberNoteDiscardTitle,
      message: context.l10n.memberNoteDiscardMessage,
      confirmLabel: context.l10n.memberNoteDiscardConfirm,
      destructive: true,
    );
    if (confirm && mounted) {
      _getProcessor().discardStaged();
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    _controller.updateTheme(context);

    // Keep this editor's processor session alive for the sheet's whole
    // lifetime so staged images survive until _save() commits them (and are
    // discarded on close). Guarded for test contexts without media infra.
    try {
      ref.watch(bioImageProcessorProvider(_editSessionId));
    } catch (_) {}

    final processingState = ref.watch(bioImageProcessingStateProvider);
    final isProcessing =
        processingState.status == BioImageProcessingStatus.processing;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await _maybeDiscard();
        },
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
                        onPressed: _save,
                        tooltip: l10n.save,
                        size: PrismTokens.topBarActionSize,
                        tint: theme.colorScheme.primary,
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
                              PrismTextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                hintText: widget.hintText,
                                fieldStyle: PrismTextFieldStyle.borderless,
                                style: theme.textTheme.bodyLarge,
                                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                                minLines: 12,
                                maxLines: null,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                autofocus: true,
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
