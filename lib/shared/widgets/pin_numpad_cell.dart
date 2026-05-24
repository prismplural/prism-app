import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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

  @override
  Widget build(BuildContext context) {
    final isIconOnly = icon != null && label == null;
    final backspaceLabel =
        isIconOnly ? context.l10n.syncSetupNumpadBackspaceLabel : null;

    Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: label != null
            ? Text(
                label!,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 24, color: theme.colorScheme.onSurface),
      ),
    );

    if (isIconOnly) {
      button = Semantics(
        label: backspaceLabel,
        button: true,
        child: Tooltip(
          message: backspaceLabel!,
          child: button,
        ),
      );
    }

    return button;
  }
}
