import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';

enum PrismSurfaceTone { subtle, strong, accent }

/// Shared rounded surface for cards and grouped containers.
class PrismSurface extends StatefulWidget {
  const PrismSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = PrismTokens.radiusMedium,
    this.tone = PrismSurfaceTone.subtle,
    this.accentColor,
    this.fillColor,
    this.borderColor,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double borderRadius;
  final PrismSurfaceTone tone;
  final Color? accentColor;
  final Color? fillColor;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  State<PrismSurface> createState() => _PrismSurfaceState();
}

class _PrismSurfaceState extends State<PrismSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor =
        widget.accentColor ?? theme.colorScheme.onSurface.withValues(alpha: 1);
    final canPress = widget.onTap != null;

    final backgroundColor =
        widget.fillColor ??
        switch (widget.tone) {
          PrismSurfaceTone.subtle => baseColor.withValues(
            alpha: _pressed ? 0.12 : 0.08,
          ),
          PrismSurfaceTone.strong => baseColor.withValues(
            alpha: _pressed ? 0.16 : 0.12,
          ),
          PrismSurfaceTone.accent => baseColor.withValues(
            alpha: _pressed ? 0.18 : 0.13,
          ),
        };
    final borderColor =
        widget.borderColor ??
        switch (widget.tone) {
          PrismSurfaceTone.subtle => baseColor.withValues(
            alpha: _pressed ? 0.16 : 0.1,
          ),
          PrismSurfaceTone.strong => baseColor.withValues(
            alpha: _pressed ? 0.22 : 0.14,
          ),
          PrismSurfaceTone.accent => baseColor.withValues(
            alpha: _pressed ? 0.24 : 0.16,
          ),
        };

    final borderRadius = BorderRadius.circular(widget.borderRadius);
    final content = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: Anim.sm,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor),
        ),
        child: widget.child,
      ),
    );

    return Padding(
      padding: widget.margin,
      child: Semantics(
        button: canPress ? true : null,
        enabled: canPress ? true : null,
        label: widget.semanticLabel,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: Anim.xs,
          child: canPress
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onTap,
                    onLongPress: widget.onLongPress,
                    onHighlightChanged: (value) {
                      if (_pressed != value) {
                        setState(() => _pressed = value);
                      }
                    },
                    borderRadius: borderRadius,
                    child: content,
                  ),
                )
              : content,
        ),
      ),
    );
  }
}

/// A compact all-caps section label.
class PrismSectionHeader extends StatelessWidget {
  const PrismSectionHeader({
    super.key,
    required this.title,
    this.padding = PrismTokens.sectionPadding,
  });

  final String title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
