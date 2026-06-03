import 'dart:async';

import 'package:flutter/material.dart';

/// Overrides paste so an image on the clipboard is handled before falling back
/// to the platform's default text paste. Register under [PasteTextIntent] in an
/// [Actions] ancestor of a text field (see [ImagePasteRegion]).
///
/// [handlePaste] receives the default text-paste action as [fallback] (null
/// when there is no default in the action chain); it must invoke [fallback]
/// when no image was handled so ordinary text paste still works.
class ImageFirstPasteAction extends Action<PasteTextIntent> {
  ImageFirstPasteAction({required this.handlePaste});

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
  bool consumesKey(PasteTextIntent intent) =>
      callingAction?.consumesKey(intent) ?? true;
}

/// Wraps a text field so that pasting an image — via Cmd/Ctrl+V on desktop or
/// the long-press / right-click "Paste" toolbar everywhere — routes through
/// [onPasteImage] first. When [onPasteImage] reports it handled an image, the
/// default text paste is suppressed; otherwise text paste proceeds normally.
///
/// The field is built by [builder], which receives an
/// [EditableTextContextMenuBuilder] that MUST be forwarded to the field's
/// `contextMenuBuilder` so the selection toolbar's "Paste" is intercepted too
/// (the keyboard shortcut alone does not cover the toolbar/long-press path).
class ImagePasteRegion extends StatefulWidget {
  const ImagePasteRegion({
    super.key,
    required this.onPasteImage,
    required this.builder,
  });

  /// Pulls an image off the clipboard and handles it (e.g. opens the add-image
  /// dialog). Returns true when an image was found and handled — text paste is
  /// then suppressed — or false to let the default text paste run.
  final Future<bool> Function() onPasteImage;

  /// Builds the wrapped text field. Forward [contextMenuBuilder] to the field's
  /// `contextMenuBuilder` parameter.
  final Widget Function(
    BuildContext context,
    EditableTextContextMenuBuilder contextMenuBuilder,
  )
  builder;

  @override
  State<ImagePasteRegion> createState() => _ImagePasteRegionState();
}

class _ImagePasteRegionState extends State<ImagePasteRegion> {
  // Built once so per-keystroke rebuilds of the field don't reallocate the map
  // or re-notify Actions dependents; the action reads widget.onPasteImage live.
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    PasteTextIntent: ImageFirstPasteAction(handlePaste: _handlePaste),
  };

  Future<void> _handlePaste({VoidCallback? fallback}) async {
    final handled = await widget.onPasteImage();
    if (handled) {
      ContextMenuController.removeAny();
      return;
    }
    fallback?.call();
  }

  Widget _contextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    var hasPaste = false;
    final items = <ContextMenuButtonItem>[];
    for (final item in editableTextState.contextMenuButtonItems) {
      if (item.type == ContextMenuButtonType.paste) {
        hasPaste = true;
        items.add(
          item.copyWith(
            onPressed: () => unawaited(_handlePaste(fallback: item.onPressed)),
          ),
        );
      } else {
        items.add(item);
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
    return Actions(
      actions: _actions,
      child: widget.builder(context, _contextMenuBuilder),
    );
  }
}
