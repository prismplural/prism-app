import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/entity_mention_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/entity_mention_text_field.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

Future<String?> showFullScreenMarkdownEditor({
  required BuildContext context,
  required String title,
  required String initialText,
  required String hintText,
  bool entityMentionsEnabled = false,
  bool markdownEnabled = true,
}) {
  return PrismSheet.showFullScreen<String>(
    context: context,
    builder: (context, scrollController) => FullScreenMarkdownEditorSheet(
      title: title,
      initialText: initialText,
      hintText: hintText,
      scrollController: scrollController,
      entityMentionsEnabled: entityMentionsEnabled,
      markdownEnabled: markdownEnabled,
    ),
  );
}

/// Full-screen markdown editor for longer profile text fields.
///
/// Returns trimmed text when saved, or null when cancelled without saving.
class FullScreenMarkdownEditorSheet extends StatefulWidget {
  const FullScreenMarkdownEditorSheet({
    super.key,
    required this.title,
    required this.initialText,
    required this.hintText,
    required this.scrollController,
    this.entityMentionsEnabled = false,
    this.markdownEnabled = true,
  });

  final String title;
  final String initialText;
  final String hintText;
  final ScrollController scrollController;
  final bool entityMentionsEnabled;
  final bool markdownEnabled;

  @override
  State<FullScreenMarkdownEditorSheet> createState() =>
      _FullScreenMarkdownEditorSheetState();
}

class _FullScreenMarkdownEditorSheetState
    extends State<FullScreenMarkdownEditorSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = widget.entityMentionsEnabled
        ? EntityMentionEditingController(text: widget.initialText)
        : MarkdownEditingController(text: widget.initialText);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text != widget.initialText;

  Future<void> _save() async {
    Navigator.of(context).pop(_controller.text.trim());
  }

  Future<void> _maybeDiscard() async {
    if (!_isDirty) {
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
    if (confirm && mounted) Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final controller = _controller;
    if (controller is MarkdownEditingController) {
      controller.updateTheme(context);
    }

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          await _maybeDiscard();
        },
        child: Column(
          children: [
            PrismSheetTopBar(
              title: widget.title,
              trailing: PrismGlassIconButton(
                icon: AppIcons.check,
                onPressed: _save,
                tooltip: l10n.save,
                size: PrismTokens.topBarActionSize,
                tint: theme.colorScheme.primary,
                accentIcon: true,
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                behavior: HitTestBehavior.translucent,
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrismTokens.pageHorizontalPadding + 8,
                    vertical: 16,
                  ),
                  children: [
                    if (controller is EntityMentionEditingController)
                      EntityMentionTextField(
                        controller: controller,
                        focusNode: _focusNode,
                        hintText: widget.hintText,
                        markdownEnabled: widget.markdownEnabled,
                        fieldStyle: PrismTextFieldStyle.borderless,
                        style: theme.textTheme.bodyLarge,
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        minLines: 12,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        autofocus: true,
                      )
                    else
                      PrismTextField(
                        controller: controller,
                        focusNode: _focusNode,
                        hintText: widget.hintText,
                        fieldStyle: PrismTextFieldStyle.borderless,
                        style: theme.textTheme.bodyLarge,
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        minLines: 12,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        autofocus: true,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
