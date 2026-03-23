import 'package:flutter/material.dart';

enum PrismButtonTone { subtle, filled, destructive, outlined }

enum PrismControlDensity { regular, compact }

/// A custom button with Prism styling and Material semantics.
class PrismButton extends StatefulWidget {
  const PrismButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.isLoading = false,
    this.tone = PrismButtonTone.subtle,
    this.density = PrismControlDensity.regular,
    this.expanded = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool enabled;
  final bool isLoading;
  final PrismButtonTone tone;
  final PrismControlDensity density;
  final bool expanded;
  final String? semanticLabel;

  @override
  State<PrismButton> createState() => _PrismButtonState();
}

class _PrismButtonState extends State<PrismButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPress = widget.enabled && !widget.isLoading;
    final tone = widget.tone;
    final density = widget.density;
    final color = switch (tone) {
      PrismButtonTone.destructive => theme.colorScheme.error,
      PrismButtonTone.filled => theme.colorScheme.primary,
      PrismButtonTone.subtle => theme.colorScheme.onSurface,
      PrismButtonTone.outlined => theme.colorScheme.onSurface,
    };

    final horizontalPadding = density == PrismControlDensity.compact
        ? 16.0
        : 24.0;
    final verticalPadding = density == PrismControlDensity.compact ? 8.0 : 12.0;
    final borderRadius = density == PrismControlDensity.compact ? 10.0 : 14.0;
    final foregroundColor = switch (tone) {
      PrismButtonTone.filled => canPress
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onPrimary.withValues(alpha: 0.6),
      _ => canPress ? color : color.withValues(alpha: 0.4),
    };

    final backgroundColor = switch (tone) {
      PrismButtonTone.filled =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.9 : 0.8)
            : color.withValues(alpha: 0.3),
      PrismButtonTone.destructive =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.14 : 0.1)
            : color.withValues(alpha: 0.05),
      PrismButtonTone.subtle =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.2 : 0.1)
            : color.withValues(alpha: 0.04),
      PrismButtonTone.outlined =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.06 : 0.0)
            : Colors.transparent,
    };

    final borderColor = switch (tone) {
      PrismButtonTone.filled =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.4 : 0.2)
            : color.withValues(alpha: 0.08),
      PrismButtonTone.destructive =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.28 : 0.18)
            : color.withValues(alpha: 0.08),
      PrismButtonTone.subtle =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.4 : 0.2)
            : color.withValues(alpha: 0.05),
      PrismButtonTone.outlined =>
        canPress
            ? color.withValues(alpha: _pressed ? 0.35 : 0.25)
            : color.withValues(alpha: 0.08),
    };

    return Semantics(
      button: true,
      enabled: canPress,
      label: widget.semanticLabel ?? widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canPress ? widget.onPressed : null,
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() => _pressed = value);
              }
            },
            borderRadius: BorderRadius.circular(borderRadius),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                color: backgroundColor,
                border: Border.all(color: borderColor),
              ),
              child: widget.isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foregroundColor,
                      ),
                    )
                  : Row(
                      mainAxisSize:
                          widget.expanded ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: density == PrismControlDensity.compact
                                ? 16
                                : 18,
                            color: foregroundColor,
                          ),
                          SizedBox(
                            width: density == PrismControlDensity.compact
                                ? 6
                                : 8,
                          ),
                        ],
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: density == PrismControlDensity.compact
                                ? 13
                                : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular icon button with Prism styling and Material semantics.
class PrismIconButton extends StatefulWidget {
  const PrismIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.size = 40,
    this.iconSize,
    this.color,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final double size;
  final double? iconSize;
  final Color? color;
  final String? tooltip;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<PrismIconButton> createState() => _PrismIconButtonState();
}

class _PrismIconButtonState extends State<PrismIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.color ?? theme.colorScheme.onSurface;
    final canPress = widget.enabled;
    final iconColor = canPress
        ? color.withValues(alpha: 0.82)
        : color.withValues(alpha: 0.35);

    Widget button = Semantics(
      button: true,
      enabled: canPress,
      label: widget.semanticLabel ?? widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkResponse(
            onTap: canPress ? widget.onPressed : null,
            onLongPress: canPress ? widget.onLongPress : null,
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() => _pressed = value);
              }
            },
            radius: widget.size / 2,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: canPress
                    ? color.withValues(alpha: _pressed ? 0.2 : 0.12)
                    : color.withValues(alpha: 0.05),
              ),
              child: Icon(
                widget.icon,
                color: iconColor,
                size: widget.iconSize ?? widget.size * 0.5,
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
