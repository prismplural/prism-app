import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';

/// Lightweight icon button for inline row, header, and editor actions.
///
/// Defaults to a 32 dp hit target ([size] = 32). This is below the recommended
/// 44 dp (iOS) / 48 dp (Android) minimum. In non-constrained layouts, wrap in
/// [Padding] with at least 6 dp on all sides to reach the platform minimum.
class PrismInlineIconButton extends StatefulWidget {
  const PrismInlineIconButton({
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
  State<PrismInlineIconButton> createState() => _PrismInlineIconButtonState();
}

class _PrismInlineIconButtonState extends State<PrismInlineIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.color ?? theme.colorScheme.onSurfaceVariant;
    final canPress = widget.enabled && widget.onPressed != null;
    final iconColor = canPress
        ? baseColor.withValues(alpha: 0.88)
        : baseColor.withValues(alpha: 0.32);
    final fillColor = canPress
        ? baseColor.withValues(alpha: _pressed ? 0.14 : 0)
        : Colors.transparent;
    final borderRadius = BorderRadius.circular(PrismTokens.radiusSmall);

    Widget button = Semantics(
      button: true,
      enabled: canPress,
      label: widget.semanticLabel ?? widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: Anim.xs,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: canPress ? widget.onPressed : null,
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() => _pressed = value);
              }
            },
            borderRadius: borderRadius,
            child: AnimatedContainer(
              duration: Anim.xs,
              curve: Anim.standard,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: borderRadius,
              ),
              child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
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
