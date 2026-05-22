import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
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
    final isDark = theme.brightness == Brightness.dark;
    final useAccentFill =
        widget.accentColor != null || widget.tone == PrismSurfaceTone.accent;
    final baseColor = widget.accentColor ?? theme.colorScheme.primary;
    final canPress = widget.onTap != null;

    final backgroundColor =
        widget.fillColor ??
        (useAccentFill
            ? switch (widget.tone) {
                PrismSurfaceTone.subtle => baseColor.withValues(
                  alpha: _pressed
                      ? (isDark ? 0.14 : 0.12)
                      : (isDark ? 0.10 : 0.08),
                ),
                PrismSurfaceTone.strong => baseColor.withValues(
                  alpha: _pressed
                      ? (isDark ? 0.18 : 0.16)
                      : (isDark ? 0.14 : 0.10),
                ),
                PrismSurfaceTone.accent => baseColor.withValues(
                  alpha: _pressed
                      ? (isDark ? 0.22 : 0.18)
                      : (isDark ? 0.16 : 0.12),
                ),
              }
            : _surfaceFillColor(theme, widget.tone, _pressed));
    final borderColor =
        widget.borderColor ??
        (useAccentFill
            ? switch (widget.tone) {
                PrismSurfaceTone.subtle => baseColor.withValues(
                  alpha: _pressed
                      ? (isDark ? 0.16 : 0.18)
                      : (isDark ? 0.12 : 0.14),
                ),
                PrismSurfaceTone.strong => baseColor.withValues(
                  alpha: _pressed
                      ? (isDark ? 0.20 : 0.20)
                      : (isDark ? 0.15 : 0.16),
                ),
                PrismSurfaceTone.accent => baseColor.withValues(
                  alpha: _pressed
                      ? (isDark ? 0.24 : 0.24)
                      : (isDark ? 0.17 : 0.18),
                ),
              }
            : _surfaceBorderColor(theme, widget.tone, _pressed));

    final borderRadius = BorderRadius.circular(
      PrismShapes.of(context).radius(widget.borderRadius),
    );
    final content = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: Anim.sm,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border: borderColor.a == 0 ? null : Border.all(color: borderColor),
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

Color _surfaceFillColor(ThemeData theme, PrismSurfaceTone tone, bool pressed) {
  final baseColor = switch (tone) {
    PrismSurfaceTone.subtle => theme.cardColor,
    PrismSurfaceTone.strong => theme.colorScheme.surfaceContainerHigh,
    PrismSurfaceTone.accent => theme.colorScheme.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.16 : 0.12,
    ),
  };

  if (!pressed) return baseColor;

  return Color.alphaBlend(
    theme.colorScheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.06 : 0.04,
    ),
    baseColor,
  );
}

Color _surfaceBorderColor(
  ThemeData theme,
  PrismSurfaceTone tone,
  bool pressed,
) {
  final isDark = theme.brightness == Brightness.dark;
  final baseColor = switch (tone) {
    PrismSurfaceTone.subtle => theme.colorScheme.outlineVariant,
    PrismSurfaceTone.strong => theme.colorScheme.outlineVariant,
    PrismSurfaceTone.accent => theme.colorScheme.primary,
  };

  final alpha = switch (tone) {
    PrismSurfaceTone.subtle =>
      pressed ? (isDark ? 0.60 : 0.62) : (isDark ? 0.50 : 0.52),
    PrismSurfaceTone.strong =>
      pressed ? (isDark ? 0.62 : 0.70) : (isDark ? 0.52 : 0.60),
    PrismSurfaceTone.accent => pressed ? 0.24 : 0.18,
  };

  return baseColor.withValues(alpha: alpha);
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
