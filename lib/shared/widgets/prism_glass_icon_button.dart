import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A reusable circular icon button using Prism's glass treatment.
class PrismGlassIconButton extends StatefulWidget {
  const PrismGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.tooltip,
    this.semanticLabel,
    this.size = 40,
    this.iconSize = 20,
    this.tint,
    this.enabled = true,
    this.isLoading = false,
    this.accentIcon = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final String? semanticLabel;
  final double size;
  final double iconSize;
  final Color? tint;
  final bool enabled;

  /// When true, shows a loading spinner instead of the icon.
  final bool isLoading;

  /// When true, the icon uses the [tint] color instead of [onSurface].
  final bool accentIcon;

  @override
  State<PrismGlassIconButton> createState() => _PrismGlassIconButtonState();
}

class _PrismGlassIconButtonState extends State<PrismGlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPress = widget.onPressed != null && !widget.isLoading;
    final visuallyEnabled = widget.enabled && !widget.isLoading;

    Widget button = Semantics(
      button: true,
      enabled: canPress,
      label: widget.semanticLabel ?? widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: TintedGlassSurface.circle(
          size: widget.size,
          tint: widget.tint,
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
              customBorder: const CircleBorder(),
              radius: widget.size / 2,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: widget.isLoading
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: visuallyEnabled
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.35),
                          ),
                        ),
                      )
                    : Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: visuallyEnabled
                            ? (widget.accentIcon && widget.tint != null
                                ? widget.tint!
                                : theme.colorScheme.onSurface)
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.35),
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
