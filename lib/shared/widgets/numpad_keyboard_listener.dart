import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Routes physical keyboard input to numpad callbacks so desktop users can
/// type a PIN (or any digit string) instead of clicking on-screen buttons.
///
/// Wrap a numpad subtree with this widget and forward the same callbacks you
/// pass to the buttons themselves. Handles digits (0–9 on both the top row
/// and the numpad cluster), Backspace/Delete, and optionally Enter and
/// Escape. Modifier keys (Ctrl/Alt/Meta) suppress handling so shortcuts like
/// Ctrl+5 are not interpreted as PIN entry.
///
/// Safe to use on mobile — there's no physical keyboard, so the listener is
/// inert until a Bluetooth/USB keyboard sends events.
class NumpadKeyboardListener extends StatefulWidget {
  const NumpadKeyboardListener({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onSubmit,
    this.onCancel,
    this.enabled = true,
    this.autofocus = true,
    required this.child,
  });

  /// Called with a single-character digit ("0"–"9").
  final void Function(String digit) onDigit;

  /// Called for Backspace or Delete.
  final VoidCallback onBackspace;

  /// Called for Enter or numpad Enter. If null, the keys are not intercepted
  /// and standard focus traversal handles them.
  final VoidCallback? onSubmit;

  /// Called for Escape. If null, Escape is not intercepted.
  final VoidCallback? onCancel;

  /// When false, no key events are intercepted. Use to pause input during
  /// loading or lockout states without unmounting the widget.
  final bool enabled;

  /// When true, requests focus on first build so the user can start typing
  /// without clicking the numpad first.
  final bool autofocus;

  final Widget child;

  @override
  State<NumpadKeyboardListener> createState() => _NumpadKeyboardListenerState();
}

class _NumpadKeyboardListenerState extends State<NumpadKeyboardListener> {
  late final FocusNode _node = FocusNode(
    debugLabel: 'NumpadKeyboardListener',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handle(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final digit = _digitFor(key);
    if (digit != null) {
      widget.onDigit(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }
    final onSubmit = widget.onSubmit;
    if (onSubmit != null &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      onSubmit();
      return KeyEventResult.handled;
    }
    final onCancel = widget.onCancel;
    if (onCancel != null && key == LogicalKeyboardKey.escape) {
      onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String? _digitFor(LogicalKeyboardKey key) => _digitMap[key];

  // Non-const because LogicalKeyboardKey overrides ==/hashCode.
  static final Map<LogicalKeyboardKey, String> _digitMap = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _handle,
      child: widget.child,
    );
  }
}
