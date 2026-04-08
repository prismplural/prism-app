import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';

/// Compact icon button sized for text-field suffixes and inline field actions.
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
        ? baseColor.withValues(alpha: 0.82)
        : baseColor.withValues(alpha: 0.32);
    final fillColor = canPress
        ? baseColor.withValues(alpha: _pressed ? 0.16 : 0.09)
        : baseColor.withValues(alpha: 0.04);
    final borderColor = canPress
        ? baseColor.withValues(alpha: _pressed ? 0.18 : 0.1)
        : baseColor.withValues(alpha: 0.05);
    final borderRadius = BorderRadius.circular(PrismTokens.radiusSmall);

    Widget button = Semantics(
      button: true,
      enabled: canPress,
      label: widget.semanticLabel ?? widget.tooltip,
      child: Center(
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
                  border: Border.all(color: borderColor),
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: iconColor,
                ),
              ),
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
