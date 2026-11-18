import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_metrics.dart';

/// Flat circular numpad cell for PIN entry sheets. Icon-only cells (backspace)
/// get a [Semantics] + [Tooltip] wrapper automatically.
///
/// For the glass-surface spring-animation variant used on the PIN lock screen,
/// see [PinNumpadButton] in `pin_numpad_button.dart`.
class PinNumpadCell extends StatelessWidget {
  const PinNumpadCell({
    super.key,
    this.label,
    this.icon,
    required this.onTap,
    required this.theme,
  }) : assert(label != null || icon != null, 'Provide label or icon');

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final ThemeData theme;

  /// Requested key width; the painted size follows the digit and only ever grows
  /// past it (see [pinNumpadKeyExtent]).
  static const double _keyWidth = 72;

  @override
  Widget build(BuildContext context) {
    final isIconOnly = icon != null && label == null;
    final backspaceLabel = isIconOnly
        ? context.l10n.syncSetupNumpadBackspaceLabel
        : null;

    final digitStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontSize: 24,
      fontWeight: FontWeight.w500,
    );
    // Keep the 24pt digit at the requested scale and let the key grow; a fixed
    // 72dp box clipped it above ~2.1x. Square keys still render as a circle
    // because the radius is half the width.
    final keyExtent = label != null
        ? pinNumpadKeyExtent(context, size: _keyWidth, style: digitStyle)
        : (width: _keyWidth, height: _keyWidth);

    Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: keyExtent.width,
        height: keyExtent.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(keyExtent.width / 2),
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: label != null
            ? Text(label!, style: digitStyle)
            : Icon(icon, size: 24, color: theme.colorScheme.onSurface),
      ),
    );

    if (isIconOnly) {
      button = Semantics(
        label: backspaceLabel,
        button: true,
        child: Tooltip(message: backspaceLabel!, child: button),
      );
    }

    return button;
  }
}
