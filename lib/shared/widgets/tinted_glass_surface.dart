import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// A cheap faux-glass surface that achieves a glassy appearance through
/// translucent fill, directional highlight gradient, hairline border, and
/// drop shadow — with NO BackdropFilter.
///
/// Use this instead of [GlassSurface] for list-level widgets where repeated
/// backdrop blur would be too expensive. Visually "glassy enough" at lower
/// rendering cost.
///
/// Responds to [VisualEffectsMode.accessible]: raises fill opacity, strengthens
/// border, and removes the highlight gradient for better contrast.
class TintedGlassSurface extends ConsumerWidget {
  const TintedGlassSurface({
    super.key,
    required this.child,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.width,
    this.height,
    this.tint,
    this.tintStrength = PrismTokens.tintedTintAlpha,
    this.padding,
    this.borderColor,
    this.borderWidth = PrismTokens.hairlineBorderWidth,
    this.showHighlight = true,
  });

  /// Convenience constructor for circular tinted glass surfaces.
  const TintedGlassSurface.circle({
    super.key,
    required this.child,
    required double size,
    this.tint,
    this.tintStrength = PrismTokens.tintedTintAlpha,
    this.padding,
    this.borderColor,
    this.borderWidth = PrismTokens.hairlineBorderWidth,
    this.showHighlight = true,
  }) : shape = BoxShape.circle,
       borderRadius = null,
       width = size,
       height = size;

  final Widget child;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final double? width;
  final double? height;

  /// Optional tint color blended into the fill. Same pattern as [GlassSurface].
  final Color? tint;
  final double tintStrength;
  final EdgeInsets? padding;
  final Color? borderColor;
  final double borderWidth;
  final bool showHighlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final mode = VisualEffectsModeX.of(context, ref);
    final isAccessible = mode.highContrast;
    final shapes = PrismShapes.of(context);
    final effectiveShape =
        shape == BoxShape.circle && shapes.cornerStyle == CornerStyle.angular
        ? BoxShape.rectangle
        : shape;

    // --- Fill color ---
    // Base translucency differs by brightness; accessible mode raises opacity.
    final double baseFillAlpha = isDark
        ? PrismTokens.tintedFillAlphaDark + (isAccessible ? 0.15 : 0.0)
        : PrismTokens.tintedFillAlphaLight + (isAccessible ? 0.15 : 0.0);

    final Color baseColor = colors.surfaceContainerHigh.withValues(
      alpha: isDark ? baseFillAlpha * 2.4 : baseFillAlpha,
    );

    final effectiveTint = tint ?? colors.primary;
    final effectiveTintStrength = tint != null
        ? tintStrength
        : isDark
        ? PrismTokens.tintedDefaultTintAlphaDark
        : PrismTokens.tintedDefaultTintAlphaLight;
    final Color fillColor = Color.alphaBlend(
      effectiveTint.withValues(alpha: effectiveTintStrength),
      baseColor,
    );

    // --- Border color ---
    final double borderAlpha = isDark
        ? PrismTokens.tintedBorderAlphaDark + (isAccessible ? 0.10 : 0.0)
        : PrismTokens.tintedBorderAlphaLight + (isAccessible ? 0.10 : 0.0);

    final Color effectiveBorderColor =
        borderColor ??
        colors.outlineVariant.withValues(
          alpha: isDark ? borderAlpha * 2.2 : borderAlpha * 1.4,
        );

    // --- Shadow ---
    final double shadowAlpha = isDark
        ? PrismTokens.tintedShadowAlphaDark
        : PrismTokens.tintedShadowAlphaLight;

    final List<BoxShadow> shadow = [
      BoxShadow(
        color: colors.shadow.withValues(alpha: shadowAlpha),
        blurRadius: PrismTokens.tintedShadowBlur,
        offset: const Offset(0, 1),
      ),
    ];

    // --- Shape helpers ---
    final effectiveBorderRadius = effectiveShape == BoxShape.circle
        ? null
        : shape == BoxShape.circle
        ? BorderRadius.zero
        : (borderRadius ??
              BorderRadius.circular(shapes.radius(PrismTokens.radiusMedium)));

    // --- Highlight gradient (suppressed in accessible mode) ---
    final Decoration? highlightDecoration = isAccessible || !showHighlight
        ? null
        : BoxDecoration(
            shape: effectiveShape,
            borderRadius: effectiveBorderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                effectiveTint.withValues(
                  alpha: PrismTokens.tintedHighlightAlpha,
                ),
                Colors.transparent,
              ],
            ),
          );

    // --- Noise texture (suppressed in accessible mode) ---
    final DecorationImage? noiseImage = isAccessible
        ? null
        : DecorationImage(
            image: const AssetImage('assets/textures/noise_64x64.png'),
            repeat: ImageRepeat.repeat,
            opacity: isDark
                ? PrismTokens.tintedNoiseOpacityDark
                : PrismTokens.tintedNoiseOpacityLight,
          );

    return Container(
      width: width,
      height: height,
      padding: padding,
      foregroundDecoration: highlightDecoration,
      decoration: BoxDecoration(
        color: fillColor,
        shape: effectiveShape,
        borderRadius: effectiveBorderRadius,
        border: Border.all(color: effectiveBorderColor, width: borderWidth),
        boxShadow: shadow,
        image: noiseImage,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
