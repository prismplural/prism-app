import 'package:flutter/material.dart';

/// App-wide text input behavior for dismissing the soft keyboard.
///
/// Flutter's default mobile touch behavior keeps text fields focused when users
/// tap outside them. Prism opts into the common app behavior of dismissing the
/// keyboard on outside taps while still respecting [TextFieldTapRegion] for
/// controls that belong to the active field.
class PrismKeyboardDismissScope extends StatelessWidget {
  const PrismKeyboardDismissScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent: _DismissKeyboardOnTapOutsideAction(),
      },
      child: child,
    );
  }
}

class _DismissKeyboardOnTapOutsideAction
    extends ContextAction<EditableTextTapOutsideIntent> {
  @override
  void invoke(EditableTextTapOutsideIntent intent, [BuildContext? context]) {
    intent.focusNode.unfocus();
  }
}
