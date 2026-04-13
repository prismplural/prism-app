import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/utils/animations.dart';

/// Compact icon button sized for text-field suffixes and inline field actions.
///
/// Defaults to a 32 dp hit target ([size] = 32), matched to text-field suffix
/// affordances. This button is designed for constrained contexts; for
/// standalone buttons, prefer [PrismInlineIconButton] (44 dp default).
class PrismFieldIconButton extends StatefulWidget {
  const PrismFieldIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.color,
    this.size = 32,
    this.iconSize = 18,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? semanticLabel;
  final Color? color;
  final double size;
  final double iconSize;
  final bool enabled;

  @override
  State<PrismFieldIconButton> createState() => _PrismFieldIconButtonState();
}

class _PrismFieldIconButtonState extends State<PrismFieldIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.color ?? theme.colorScheme.onSurfaceVariant;
    final canPress = widget.enabled && widget.onPressed != null;
    final iconColor = canPress
        ? baseColor.withValues(alpha: _pressed ? 1.0 : 0.7)
        : baseColor.withValues(alpha: 0.32);

    Widget button = Semantics(
      button: true,
      enabled: canPress,
      label: widget.semanticLabel ?? widget.tooltip,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: Anim.xs,
          child: GestureDetector(
            onTap: canPress ? widget.onPressed : null,
            onTapDown: (_) { if (canPress) setState(() => _pressed = true); },
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }
}
