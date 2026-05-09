import 'dart:async';

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

class UnsavedChangesDismissController {
  final _guards = <_UnsavedChangesGuardState<dynamic>>{};

  bool get hasUnsavedChanges =>
      _guards.any((guard) => guard.mounted && guard.hasUnsavedChanges);

  Future<bool> confirmDiscardIfNeeded() async {
    for (final guard in List<_UnsavedChangesGuardState<dynamic>>.of(_guards)) {
      if (guard.mounted && guard.hasUnsavedChanges) {
        return guard.confirmDiscardForDismiss();
      }
    }
    return true;
  }

  void _register(_UnsavedChangesGuardState<dynamic> guard) {
    _guards.add(guard);
  }

  void _unregister(_UnsavedChangesGuardState<dynamic> guard) {
    _guards.remove(guard);
  }
}

class UnsavedChangesDismissScope extends InheritedWidget {
  const UnsavedChangesDismissScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final UnsavedChangesDismissController controller;

  static UnsavedChangesDismissController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<UnsavedChangesDismissScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(UnsavedChangesDismissScope oldWidget) {
    return oldWidget.controller != controller;
  }
}

/// Blocks route dismissal while an editor has unsaved local state.
class UnsavedChangesGuard<T> extends StatefulWidget {
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
  State<UnsavedChangesGuard<T>> createState() => _UnsavedChangesGuardState<T>();
}

class _UnsavedChangesGuardState<T> extends State<UnsavedChangesGuard<T>> {
  UnsavedChangesDismissController? _dismissController;

  bool get hasUnsavedChanges => widget.hasUnsavedChanges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = UnsavedChangesDismissScope.maybeOf(context);
    if (_dismissController == nextController) return;

    _dismissController?._unregister(this);
    _dismissController = nextController;
    _dismissController?._register(this);
  }

  @override
  void dispose() {
    _dismissController?._unregister(this);
    super.dispose();
  }

  Future<bool> confirmDiscardForDismiss() async {
    if (!widget.hasUnsavedChanges) return true;

    final shouldDiscard = await UnsavedChangesGuard.confirmDiscard(context);
    if (!shouldDiscard || !mounted) return false;

    await widget.onDiscard?.call();
    return mounted;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<T>(
      canPop: !widget.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldDiscard = await confirmDiscardForDismiss();
        if (shouldDiscard && context.mounted) {
          Navigator.of(context).pop<T>(widget.discardResult);
        }
      },
      child: widget.child,
    );
  }
}
