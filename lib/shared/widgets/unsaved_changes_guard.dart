import 'dart:async';

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

/// Blocks route dismissal while an editor has unsaved local state.
class UnsavedChangesGuard<T> extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.hasUnsavedChanges,
    required this.child,
    this.onDiscard,
    this.discardResult,
  });

  final bool hasUnsavedChanges;
  final Widget child;
  final FutureOr<void> Function()? onDiscard;
  final T? discardResult;

  static Future<bool> confirmDiscard(BuildContext context) {
    return PrismDialog.confirm(
      context: context,
      title: context.l10n.memberNoteDiscardTitle,
      message: context.l10n.memberNoteDiscardMessage,
      confirmLabel: context.l10n.memberNoteDiscardConfirm,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<T>(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldDiscard = await confirmDiscard(context);
        if (!shouldDiscard || !context.mounted) return;

        await onDiscard?.call();
        if (context.mounted) {
          Navigator.of(context).pop<T>(discardResult);
        }
      },
      child: child,
    );
  }
}
